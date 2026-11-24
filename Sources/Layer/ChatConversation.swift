import Foundation

enum ChatRole: Equatable, Sendable {
    case user
    case assistant
}

struct ChatMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let role: ChatRole
    var content: String
    let screenAttachments: [ScreenAttachment]
    let attachments: [ChatAttachment]

    var screenAttachment: ScreenAttachment? { screenAttachments.first }

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        screenAttachment: ScreenAttachment? = nil,
        attachments: [ChatAttachment] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        screenAttachments = screenAttachment.map { [$0] } ?? []
        self.attachments = attachments
    }

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        screenAttachments: [ScreenAttachment],
        attachments: [ChatAttachment] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.screenAttachments = screenAttachments
        self.attachments = attachments
    }
}

enum NoticeRecovery: Equatable, Sendable {
    case settings
    case screenRecordingSettings
    case microphoneSettings
    case accessibilitySettings
}

struct Notice: Equatable, Sendable {
    let message: String
    let recovery: NoticeRecovery?
}

struct ChatResponseRequest: Sendable {
    let prompt: String
    let provider: ModelProviderConfiguration
    var history: [ModelConversationMessage] = []
    var instructions: String? = nil
    var structuredOutput = false
    let continuationID: String?
    let screenAttachments: [ScreenAttachment]
    var attachments: [ChatAttachment] = []
    var selectedContent: String? = nil

    var screenAttachment: ScreenAttachment? { screenAttachments.first }

    init(
        prompt: String,
        provider: ModelProviderConfiguration,
        history: [ModelConversationMessage] = [],
        instructions: String? = nil,
        structuredOutput: Bool = false,
        continuationID: String?,
        screenAttachment: ScreenAttachment?,
        attachments: [ChatAttachment] = [],
        selectedContent: String? = nil
    ) {
        self.prompt = prompt
        self.provider = provider
        self.history = history
        self.instructions = instructions
        self.structuredOutput = structuredOutput
        self.continuationID = continuationID
        screenAttachments = screenAttachment.map { [$0] } ?? []
        self.attachments = attachments
        self.selectedContent = selectedContent
    }

    init(
        prompt: String,
        provider: ModelProviderConfiguration,
        history: [ModelConversationMessage] = [],
        instructions: String? = nil,
        structuredOutput: Bool = false,
        continuationID: String?,
        screenAttachments: [ScreenAttachment],
        attachments: [ChatAttachment] = [],
        selectedContent: String? = nil
    ) {
        self.prompt = prompt
        self.provider = provider
        self.history = history
        self.instructions = instructions
        self.structuredOutput = structuredOutput
        self.continuationID = continuationID
        self.screenAttachments = screenAttachments
        self.attachments = attachments
        self.selectedContent = selectedContent
    }
}

struct ModelConversationMessage: Equatable, Sendable {
    let role: ChatRole
    let content: String
    let screenAttachments: [ScreenAttachment]
    let attachments: [ChatAttachment]

    var screenAttachment: ScreenAttachment? { screenAttachments.first }

    init(
        role: ChatRole,
        content: String,
        screenAttachment: ScreenAttachment? = nil,
        attachments: [ChatAttachment] = []
    ) {
        self.role = role
        self.content = content
        screenAttachments = screenAttachment.map { [$0] } ?? []
        self.attachments = attachments
    }

    init(
        role: ChatRole,
        content: String,
        screenAttachments: [ScreenAttachment],
        attachments: [ChatAttachment] = []
    ) {
        self.role = role
        self.content = content
        self.screenAttachments = screenAttachments
        self.attachments = attachments
    }
}

enum ChatResponseEvent: Sendable {
    case textDelta(String)
    case completed(String)
}

@MainActor
protocol ChatResponseStreaming {
    func streamResponse(
        for request: ChatResponseRequest
    ) -> AsyncThrowingStream<ChatResponseEvent, Error>
}

@MainActor
final class ChatConversation: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published var draft = ""
    @Published private(set) var isResponding = false
    @Published private(set) var notice: Notice?

    private let providers: any ModelProviderProviding
    private let responses: any ChatResponseStreaming
    private var continuationID: String?
    private var provider: ModelProviderConfiguration?
    private var history: [ModelConversationMessage] = []
    private var responseTask: Task<Void, Never>?

    init(
        initialMessages: [ChatMessage] = [],
        providers: any ModelProviderProviding = StoredModelProviderAdapter(),
        responses: any ChatResponseStreaming = ModelProviderClient()
    ) {
        messages = initialMessages
        self.providers = providers
        self.responses = responses
    }

    var canSubmitDraft: Bool {
        !isResponding
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func canSubmitDraft(with attachments: [ChatAttachment]) -> Bool {
        !isResponding
            && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !attachments.isEmpty)
    }

    func submitDraft(attachments: [ChatAttachment] = []) {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = trimmedDraft.isEmpty && !attachments.isEmpty
            ? "Please analyze the attached \(attachments.count == 1 ? "file" : "files")."
            : draft
        draft = ""
        submit(prompt, attachments: attachments)
    }

    func submit(
        _ rawPrompt: String,
        modelContext: InvocationModelContext = .empty,
        attachments: [ChatAttachment] = []
    ) {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isResponding else { return }

        guard let provider = provider ?? providers.loadActiveProvider() else {
            notice = Notice(
                message: "Add and select a model provider in Settings before sending a message.",
                recovery: .settings
            )
            return
        }
        self.provider = provider

        notice = modelContext.screen.notice
        isResponding = true
        let modelUserMessage = ModelConversationMessage(
            role: .user,
            content: ModelContextPayload.chatUserText(
                prompt: prompt,
                selectedContent: modelContext.selectedContent
            ),
            screenAttachments: modelContext.screen.attachments,
            attachments: attachments
        )
        let requestHistory = history
        history.append(modelUserMessage)
        messages.append(
            ChatMessage(
                role: .user,
                content: prompt,
                screenAttachments: modelContext.screen.attachments,
                attachments: attachments
            )
        )

        let request = ChatResponseRequest(
            prompt: prompt,
            provider: provider,
            history: requestHistory,
            continuationID: continuationID,
            screenAttachments: modelContext.screen.attachments,
            attachments: attachments,
            selectedContent: modelContext.selectedContent
        )

        let assistantMessageID = UUID()
        messages.append(
            ChatMessage(id: assistantMessageID, role: .assistant, content: "")
        )

        responseTask = Task { [weak self] in
            guard let self else { return }
            var responseText = ""

            do {
                for try await event in responses.streamResponse(for: request) {
                    guard !Task.isCancelled else { return }
                    switch event {
                    case .textDelta(let delta):
                        responseText += delta
                        append(delta, to: assistantMessageID)
                    case .completed(let continuationID):
                        self.continuationID = continuationID
                        history.append(
                            ModelConversationMessage(
                                role: .assistant,
                                content: responseText
                            )
                        )
                    }
                }
            } catch is CancellationError {
                guard !Task.isCancelled else { return }
                removeMessageIfEmpty(assistantMessageID)
            } catch {
                guard !Task.isCancelled else { return }
                removeMessageIfEmpty(assistantMessageID)
                notice = Notice(
                    message: error.localizedDescription,
                    recovery: .settings
                )
            }

            guard !Task.isCancelled else { return }
            isResponding = false
            responseTask = nil
        }
    }

    func startNewConversation() {
        responseTask?.cancel()
        responseTask = nil
        continuationID = nil
        provider = nil
        history = []
        messages = []
        draft = ""
        notice = nil
        isResponding = false
    }

    func dismissNotice() {
        notice = nil
    }

    private func append(_ delta: String, to messageID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }
        messages[index].content += delta
    }

    private func removeMessageIfEmpty(_ messageID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              messages[index].content.isEmpty else {
            return
        }
        messages.remove(at: index)
    }
}
