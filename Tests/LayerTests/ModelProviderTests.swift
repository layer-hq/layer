import Foundation
import Testing
@testable import Layer

@Suite(.serialized)
struct ModelProviderTests {
    @Test
    func normalizesProviderBaseURLsToV1Endpoints() throws {
        let bareHost = ModelProviderConfiguration(
            kind: .liteLLM,
            baseURL: "https://models.example.com/",
            apiKey: "key",
            model: "team-model"
        )
        let versionedHost = ModelProviderConfiguration(
            kind: .liteLLM,
            baseURL: "https://models.example.com/gateway/v1/",
            apiKey: "key",
            model: "team-model"
        )

        #expect(
            bareHost.endpointURL("chat/completions")?.absoluteString
                == "https://models.example.com/v1/chat/completions"
        )
        #expect(
            versionedHost.endpointURL("models")?.absoluteString
                == "https://models.example.com/gateway/v1/models"
        )
    }

    @Test
    func rejectsUnsafeOrIncompleteProviderConfigurations() {
        #expect(
            !ModelProviderConfiguration(
                kind: .liteLLM,
                baseURL: "file:///tmp/proxy",
                apiKey: "key",
                model: "model"
            ).isReady
        )
        #expect(
            !ModelProviderConfiguration(
                kind: .liteLLM,
                baseURL: "https://models.example.com",
                apiKey: "",
                model: "model"
            ).isReady
        )
    }

    @Test
    func savesMultipleConnectionsAndUsesOnlyTheSelectedOne() throws {
        let defaults = try temporaryDefaults()
        defer { clear(defaults) }
        let first = ModelProviderConfiguration(
            kind: .liteLLM,
            name: "Personal",
            baseURL: "https://one.example.com",
            apiKey: "first-key",
            model: "first-model"
        )
        let second = ModelProviderConfiguration(
            kind: .liteLLM,
            name: "Work",
            baseURL: "https://two.example.com",
            apiKey: "second-key",
            model: "second-model"
        )

        ModelProviderPreferences.saveConfigurations([first, second], in: defaults)
        ModelProviderPreferences.select(second.id, in: defaults)

        #expect(ModelProviderPreferences.configurations(in: defaults) == [first, second])
        #expect(ModelProviderPreferences.activeConfiguration(in: defaults) == second)
    }

    @Test
    func liteLLMBodyUsesSelectedModelHistoryImageAndStructuredOutput() throws {
        let attachment = ScreenAttachment(imageData: Data([1, 2, 3]))
        let provider = ModelProviderConfiguration(
            kind: .liteLLM,
            baseURL: "https://models.example.com",
            apiKey: "proxy-key",
            model: "claude-alias"
        )
        let request = ChatResponseRequest(
            prompt: "What changed?",
            provider: provider,
            history: [
                ModelConversationMessage(role: .user, content: "Earlier question"),
                ModelConversationMessage(role: .assistant, content: "Earlier answer")
            ],
            instructions: "Return JSON.",
            structuredOutput: true,
            continuationID: "openai-only-id",
            screenAttachment: attachment,
            selectedContent: "Selected note"
        )

        let body = LiteLLMClient.requestBody(for: request)
        #expect(body["model"] as? String == "claude-alias")
        #expect(body["stream"] as? Bool == true)
        #expect(body["response_format"] != nil)
        #expect(body["previous_response_id"] == nil)

        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 4)
        #expect(messages[0]["role"] as? String == "system")
        #expect(messages[1]["content"] as? String == "Earlier question")
        #expect(messages[2]["content"] as? String == "Earlier answer")
        let currentContent = try #require(messages[3]["content"] as? [[String: Any]])
        #expect(
            (currentContent[0]["text"] as? String)?.contains("Selected note") == true
        )
        let image = try #require(currentContent[1]["image_url"] as? [String: Any])
        #expect(image["url"] as? String == attachment.dataURL)
    }

    @Test
    func openAIResponsesBodyUsesTheConfiguredModel() {
        let provider = ModelProviderConfiguration(
            kind: .openAI,
            apiKey: "key",
            model: "configured-model"
        )
        let request = ChatResponseRequest(
            prompt: "Hello",
            provider: provider,
            continuationID: "response-1",
            screenAttachment: nil
        )

        let body = OpenAIClient.requestBody(for: request)

        #expect(body["model"] as? String == "configured-model")
        #expect(body["previous_response_id"] as? String == "response-1")
        #expect(body["tools"] != nil)
    }

    @Test
    func parsesLiteLLMStreamingDeltasCompletionAndErrors() throws {
        let parsedDelta = try LiteLLMClient.streamChunk(
            from: #"{"id":"chat-1","choices":[{"delta":{"content":"Hi"},"finish_reason":null}]}"#
        )
        let parsedCompletion = try LiteLLMClient.streamChunk(
            from: #"{"id":"chat-1","choices":[{"delta":{},"finish_reason":"stop"}]}"#
        )
        let parsedDone = try LiteLLMClient.streamChunk(from: "[DONE]")
        let delta = try #require(parsedDelta)
        let completed = try #require(parsedCompletion)
        let done = try #require(parsedDone)

        #expect(delta == LiteLLMClient.StreamChunk(
            responseID: "chat-1",
            delta: "Hi",
            completed: false
        ))
        #expect(completed.completed)
        #expect(done.completed)
        #expect(throws: ModelProviderClientError.self) {
            try LiteLLMClient.streamChunk(
                from: #"{"error":{"message":"Bad key"}}"#
            )
        }
    }

    @Test
    @MainActor
    func providerClientRoutesThroughTheSelectedAdapter() async throws {
        let openAI = RecordingResponseAdapter()
        let liteLLM = RecordingResponseAdapter()
        let client = ModelProviderClient(openAI: openAI, liteLLM: liteLLM)
        let request = ChatResponseRequest(
            prompt: "Hello",
            provider: ModelProviderConfiguration(
                kind: .liteLLM,
                apiKey: "key",
                model: "model"
            ),
            continuationID: nil,
            screenAttachment: nil
        )

        for try await _ in client.streamResponse(for: request) {}

        #expect(openAI.requests.isEmpty)
        #expect(liteLLM.requests.map(\.provider.kind) == [.liteLLM])
    }

    private func temporaryDefaults() throws -> UserDefaults {
        let suiteName = "LayerTests.ModelProvider.\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: suiteName))
    }

    private func clear(_ defaults: UserDefaults) {
        defaults.removeObject(forKey: ModelProviderPreferences.configurationsKey)
        defaults.removeObject(forKey: ModelProviderPreferences.selectedConfigurationIDKey)
    }
}

@MainActor
private final class RecordingResponseAdapter: ChatResponseStreaming {
    private(set) var requests: [ChatResponseRequest] = []

    func streamResponse(
        for request: ChatResponseRequest
    ) -> AsyncThrowingStream<ChatResponseEvent, Error> {
        requests.append(request)
        return AsyncThrowingStream { continuation in
            continuation.yield(.completed("done"))
            continuation.finish()
        }
    }
}
