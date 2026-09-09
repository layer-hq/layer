import Foundation

struct ModelProviderClient: ChatResponseStreaming {
    private let openAI: any ChatResponseStreaming
    private let liteLLM: any ChatResponseStreaming

    init(
        openAI: any ChatResponseStreaming = OpenAIClient(),
        liteLLM: any ChatResponseStreaming = LiteLLMClient()
    ) {
        self.openAI = openAI
        self.liteLLM = liteLLM
    }

    func streamResponse(
        for request: ChatResponseRequest
    ) -> AsyncThrowingStream<ChatResponseEvent, Error> {
        switch request.provider.kind {
        case .openAI:
            openAI.streamResponse(for: request)
        case .liteLLM:
            liteLLM.streamResponse(for: request)
        }
    }
}
