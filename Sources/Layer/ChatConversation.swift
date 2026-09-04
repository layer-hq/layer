import Foundation

enum ChatRole: Equatable, Sendable {
    case user
    case assistant
}

struct ChatMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let role: ChatRole
    var content: String
    let screenAttachment: ScreenAttachment?

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        screenAttachment: ScreenAttachment? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.screenAttachment = screenAttachment
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
    let credential: String
    var instructions: String? = nil
    let continuationID: String?
    let screenAttachment: ScreenAttachment?
}

enum ChatResponseEvent: Sendable {
    case textDelta(String)
    case completed(String)
}

@MainActor
protocol ChatCredentialProviding {
    func loadCredential() -> String?
}

@MainActor
protocol ChatResponseStreaming {
    func streamResponse(
        for request: ChatResponseRequest
    ) -> AsyncThrowingStream<ChatResponseEvent, Error>
}

@MainActor
struct StoredChatCredentialAdapter: ChatCredentialProviding {
    func loadCredential() -> String? {
        UserDefaults.standard.string(forKey: "openAIAPIKey")
    }
}

@MainActor
final class ChatConversation: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published var draft = ""
    @Published private(set) var isResponding = false
    @Published private(set) var notice: Notice?

    private let credentials: any ChatCredentialProviding
    private let responses: any ChatResponseStreaming
    private var continuationID: String?
    private var responseTask: Task<Void, Never>?

    init(
        credentials: any ChatCredentialProviding = StoredChatCredentialAdapter(),
        responses: any ChatResponseStreaming = OpenAIClient()
    ) {
        self.credentials = credentials
        self.responses = responses
    }

    var canSubmitDraft: Bool {
        !isResponding
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func submitDraft() {
        let prompt = draft
        draft = ""
        submit(prompt)
    }

    func submit(
        _ rawPrompt: String,
        screenContext: ScreenContextOutcome = .notRequested
    ) {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isResponding else { return }

        guard let credential = credentials.loadCredential(),
              !credential.isEmpty else {
            notice = Notice(
                message: "Add an OpenAI API key in Settings before sending a message.",
                recovery: .settings
            )
            return
        }

        notice = screenContext.notice
        isResponding = true
        messages.append(
            ChatMessage(
                role: .user,
                content: prompt,
                screenAttachment: screenContext.attachment
            )
        )

        let request = ChatResponseRequest(
            prompt: prompt,
            credential: credential,
            continuationID: continuationID,
            screenAttachment: screenContext.attachment
        )

        let assistantMessageID = UUID()
        messages.append(
            ChatMessage(id: assistantMessageID, role: .assistant, content: "")
        )

        responseTask = Task { [weak self] in
            guard let self else { return }

            do {
                for try await event in responses.streamResponse(for: request) {
                    guard !Task.isCancelled else { return }
                    switch event {
                    case .textDelta(let delta):
                        append(delta, to: assistantMessageID)
                    case .completed(let continuationID):
                        self.continuationID = continuationID
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
