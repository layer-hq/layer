import Foundation

struct OpenAIClient: ChatResponseStreaming {
    func streamResponse(
        for chatRequest: ChatResponseRequest
    ) -> AsyncThrowingStream<ChatResponseEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    guard let endpoint = chatRequest.provider.endpointURL("responses") else {
                        throw ModelProviderClientError.invalidConfiguration(
                            "The selected OpenAI connection has an invalid URL."
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
                        throw ModelProviderClientError.invalidResponse("OpenAI")
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
                                throw ModelProviderClientError.invalidResponse("OpenAI")
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
                        throw ModelProviderClientError.streamEndedUnexpectedly("OpenAI")
                    }
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
        for chatRequest: ChatResponseRequest
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": chatRequest.provider.model,
            "input": ModelContextPayload.chatInput(
                prompt: chatRequest.prompt,
                selectedContent: chatRequest.selectedContent,
                screenAttachment: chatRequest.screenAttachment
            ),
            "stream": true,
            "store": true,
            "tools": [["type": "web_search"]]
        ]
        if let instructions = chatRequest.instructions {
            body["instructions"] = instructions
        }
        if chatRequest.structuredOutput {
            body["text"] = ["format": InsertResponseFormat.jsonSchema]
        }
        if let continuationID = chatRequest.continuationID {
            body["previous_response_id"] = continuationID
        }
        return body
    }

    private nonisolated static func apiError(
        from data: Data,
        statusCode: Int
    ) -> Error {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return ModelProviderClientError.api(
            message: ProviderResponseParsing.errorMessage(in: json)
                ?? "OpenAI request failed (HTTP \(statusCode))."
        )
    }

    private nonisolated static func eventError(from json: [String: Any]) -> Error {
        ModelProviderClientError.api(
            message: ProviderResponseParsing.errorMessage(in: json)
                ?? ProviderResponseParsing.errorMessage(
                    in: json["response"] as? [String: Any]
                )
                ?? "OpenAI could not complete the response."
        )
    }
}

enum InsertResponseFormat {
    nonisolated static var jsonSchema: [String: Any] {
        [
            "type": "json_schema",
            "name": "insert_result",
            "strict": true,
            "schema": [
                "type": "object",
                "properties": [
                    "kind": [
                        "type": "string",
                        "enum": InsertResult.Kind.allCases.map(\.rawValue)
                    ],
                    "text": ["type": "string"],
                    "rows": [
                        "type": "array",
                        "items": [
                            "type": "array",
                            "items": ["type": "string"]
                        ]
                    ]
                ],
                "required": ["kind", "text", "rows"],
                "additionalProperties": false
            ]
        ]
    }

    nonisolated static var chatCompletions: [String: Any] {
        var definition = jsonSchema
        definition.removeValue(forKey: "type")
        return [
            "type": "json_schema",
            "json_schema": definition
        ]
    }

}
