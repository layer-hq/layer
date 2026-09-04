import Foundation

enum OpenAIClientError: LocalizedError, Sendable {
    case invalidResponse
    case api(message: String)
    case streamEndedUnexpectedly

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "OpenAI returned an invalid response."
        case .api(let message):
            return message
        case .streamEndedUnexpectedly:
            return "The response stream ended before completion."
        }
    }
}

struct OpenAIClient: ChatResponseStreaming {
    private nonisolated static let endpoint = URL(
        string: "https://api.openai.com/v1/responses"
    )!

    func streamResponse(
        for chatRequest: ChatResponseRequest
    ) -> AsyncThrowingStream<ChatResponseEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    var body: [String: Any] = [
                        "model": "gpt-5.4",
                        "input": Self.input(for: chatRequest),
                        "stream": true,
                        "store": true,
                        "tools": [["type": "web_search"]]
                    ]
                    if let instructions = chatRequest.instructions {
                        body["instructions"] = instructions
                    }
                    if let continuationID = chatRequest.continuationID {
                        body["previous_response_id"] = continuationID
                    }

                    var request = URLRequest(url: Self.endpoint)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 300
                    request.setValue(
                        "Bearer \(chatRequest.credential)",
                        forHTTPHeaderField: "Authorization"
                    )
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw OpenAIClientError.invalidResponse
                    }

                    guard (200..<300).contains(httpResponse.statusCode) else {
                        var errorData = Data()
                        for try await byte in bytes {
                            errorData.append(byte)
                        }
                        throw Self.apiError(
                            from: errorData,
                            statusCode: httpResponse.statusCode
                        )
                    }

                    var completed = false
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }

                        let payload = line.dropFirst(5).trimmingCharacters(
                            in: .whitespaces
                        )
                        guard payload != "[DONE]", let data = payload.data(using: .utf8) else {
                            continue
                        }

                        guard let json = try JSONSerialization.jsonObject(with: data)
                                as? [String: Any],
                              let eventType = json["type"] as? String else {
                            continue
                        }

                        switch eventType {
                        case "response.output_text.delta":
                            if let delta = json["delta"] as? String {
                                continuation.yield(.textDelta(delta))
                            }

                        case "response.completed":
                            guard let response = json["response"] as? [String: Any],
                                  let responseID = response["id"] as? String else {
                                throw OpenAIClientError.invalidResponse
                            }
                            completed = true
                            continuation.yield(.completed(responseID))

                        case "response.failed", "error":
                            throw Self.eventError(from: json)

                        default:
                            break
                        }
                    }

                    guard completed else {
                        throw OpenAIClientError.streamEndedUnexpectedly
                    }
                    continuation.finish()
                } catch is CancellationError {
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

    private nonisolated static func input(for request: ChatResponseRequest) -> Any {
        guard let screenAttachment = request.screenAttachment else {
            return request.prompt
        }

        return [
            [
                "role": "user",
                "content": [
                    [
                        "type": "input_text",
                        "text": request.prompt
                    ],
                    [
                        "type": "input_image",
                        "image_url": screenAttachment.dataURL,
                        "detail": "auto"
                    ]
                ]
            ]
        ]
    }

    private nonisolated static func apiError(
        from data: Data,
        statusCode: Int
    ) -> Error {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return OpenAIClientError.api(
            message: errorMessage(in: json)
                ?? "OpenAI request failed (HTTP \(statusCode))."
        )
    }

    private nonisolated static func eventError(from json: [String: Any]) -> Error {
        OpenAIClientError.api(
            message: errorMessage(in: json)
                ?? errorMessage(in: json["response"] as? [String: Any])
                ?? "OpenAI could not complete the response."
        )
    }

    private nonisolated static func errorMessage(in json: [String: Any]?) -> String? {
        (json?["error"] as? [String: Any])?["message"] as? String
    }
}
