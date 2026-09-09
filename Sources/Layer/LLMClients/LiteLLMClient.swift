import Foundation

struct LiteLLMClient: ChatResponseStreaming {
    struct StreamChunk: Equatable {
        let responseID: String?
        let delta: String?
        let completed: Bool
    }

    func streamResponse(
        for chatRequest: ChatResponseRequest
    ) -> AsyncThrowingStream<ChatResponseEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    guard let endpoint = chatRequest.provider.endpointURL(
                        "chat/completions"
                    ) else {
                        throw ModelProviderClientError.invalidConfiguration(
                            "The selected LiteLLM connection has an invalid URL."
                        )
                    }

                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 300
                    request.setValue(
                        "Bearer \(chatRequest.provider.apiKey)",
                        forHTTPHeaderField: "Authorization"
                    )
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try JSONSerialization.data(
                        withJSONObject: Self.requestBody(for: chatRequest)
                    )

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw ModelProviderClientError.invalidResponse("LiteLLM")
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        var errorData = Data()
                        for try await byte in bytes {
                            errorData.append(byte)
                        }
                        throw ModelProviderClientError.api(
                            message: ProviderResponseParsing.errorMessage(in: errorData)
                                ?? "LiteLLM request failed (HTTP \(httpResponse.statusCode))."
                        )
                    }

                    var responseID: String?
                    var completed = false
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let chunk = try Self.streamChunk(from: payload) else {
                            continue
                        }
                        responseID = chunk.responseID ?? responseID
                        if let delta = chunk.delta {
                            continuation.yield(.textDelta(delta))
                        }
                        if chunk.completed {
                            completed = true
                            break
                        }
                    }

                    guard completed else {
                        throw ModelProviderClientError.streamEndedUnexpectedly("LiteLLM")
                    }
                    continuation.yield(.completed(responseID ?? UUID().uuidString))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    nonisolated static func requestBody(
        for request: ChatResponseRequest
    ) -> [String: Any] {
        var messages: [[String: Any]] = []
        if let instructions = request.instructions {
            messages.append(["role": "system", "content": instructions])
        }
        messages.append(contentsOf: request.history.map(messagePayload))
        messages.append(
            messagePayload(
                ModelConversationMessage(
                    role: .user,
                    content: ModelContextPayload.chatUserText(
                        prompt: request.prompt,
                        selectedContent: request.selectedContent
                    ),
                    screenAttachment: request.screenAttachment
                )
            )
        )

        var body: [String: Any] = [
            "model": request.provider.model,
            "messages": messages,
            "stream": true
        ]
        if request.structuredOutput {
            body["response_format"] = InsertResponseFormat.chatCompletions
        }
        return body
    }

    nonisolated static func streamChunk(from payload: String) throws -> StreamChunk? {
        if payload == "[DONE]" {
            return StreamChunk(responseID: nil, delta: nil, completed: true)
        }
        guard let data = payload.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data)
                as? [String: Any] else {
            return nil
        }
        if let error = ProviderResponseParsing.errorMessage(in: json) {
            throw ModelProviderClientError.api(message: error)
        }
        let choice = (json["choices"] as? [[String: Any]])?.first
        let delta = (choice?["delta"] as? [String: Any])?["content"] as? String
        return StreamChunk(
            responseID: json["id"] as? String,
            delta: delta?.isEmpty == false ? delta : nil,
            completed: choice?["finish_reason"] is String
        )
    }

    private nonisolated static func messagePayload(
        _ message: ModelConversationMessage
    ) -> [String: Any] {
        let role = message.role == .user ? "user" : "assistant"
        guard let attachment = message.screenAttachment else {
            return ["role": role, "content": message.content]
        }
        return [
            "role": role,
            "content": [
                ["type": "text", "text": message.content],
                [
                    "type": "image_url",
                    "image_url": [
                        "url": attachment.dataURL,
                        "detail": "auto"
                    ]
                ]
            ]
        ]
    }
}
