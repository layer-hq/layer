import Foundation
import Testing
@testable import Layer

@Suite
@MainActor
struct ChatConversationTests {
    @Test
    func testTurnStreamsThroughConversationInterfaceAndContinues() async {
        let responses = ChatResponseAdapterStub(
            batches: [
                .events([.textDelta("Hello"), .textDelta(" there"), .completed("first")]),
                .events([.textDelta("Again"), .completed("second")])
            ]
        )
        let conversation = ChatConversation(
            credentials: ChatCredentialStub(value: "secret"),
            responses: responses
        )
        let attachment = ScreenAttachment(imageData: Data([9, 8, 7]))

        conversation.submit(
            " First turn ",
            screenContext: ScreenContextOutcome(attachment: attachment, notice: nil)
        )
        await waitUntilSettled(conversation)

        #expect(conversation.messages.map(\.content) == ["First turn", "Hello there"])
        #expect(responses.requests.first?.prompt == "First turn")
        #expect(responses.requests.first?.credential == "secret")
        #expect(responses.requests.first?.continuationID == nil)
        #expect(
            responses.requests.first?.screenAttachment?.imageData
                == attachment.imageData
        )

        conversation.draft = "Second turn"
        conversation.submitDraft()
        await waitUntilSettled(conversation)

        #expect(responses.requests.last?.prompt == "Second turn")
        #expect(responses.requests.last?.continuationID == "first")
        #expect(responses.requests.last?.screenAttachment == nil)
        #expect(conversation.messages.last?.content == "Again")
    }

    @Test
    func testNewConversationDropsPriorHistoryFromTheNextRequest() async {
        let responses = ChatResponseAdapterStub(
            batches: [
                .events([.textDelta("First answer"), .completed("first")]),
                .events([.textDelta("Fresh answer"), .completed("fresh")])
            ]
        )
        let conversation = ChatConversation(
            credentials: ChatCredentialStub(value: "secret"),
            responses: responses
        )

        conversation.submit("First turn")
        await waitUntilSettled(conversation)
        conversation.startNewConversation()
        conversation.submit("Unrelated turn")
        await waitUntilSettled(conversation)

        #expect(responses.requests.last?.prompt == "Unrelated turn")
        #expect(responses.requests.last?.continuationID == nil)
    }

    @Test
    func testMissingCredentialRejectsTurnWithSettingsRecovery() {
        let responses = ChatResponseAdapterStub(batches: [])
        let conversation = ChatConversation(
            credentials: ChatCredentialStub(value: nil),
            responses: responses
        )

        conversation.submit("Hello")

        #expect(conversation.messages.isEmpty)
        #expect(!conversation.isResponding)
        #expect(conversation.notice?.recovery == .settings)
        #expect(responses.requests.isEmpty)
    }

    @Test
    func testScreenContextNoticeDoesNotBlockTurn() async {
        let responses = ChatResponseAdapterStub(
            batches: [.events([.textDelta("Answer"), .completed("done")])]
        )
        let conversation = ChatConversation(
            credentials: ChatCredentialStub(value: "secret"),
            responses: responses
        )
        let outcome = ScreenContextOutcome(
            attachment: nil,
            notice: Notice(
                message: "Capture unavailable",
                recovery: .screenRecordingSettings
            )
        )

        conversation.submit("Continue anyway", screenContext: outcome)
        await waitUntilSettled(conversation)

        #expect(conversation.messages.last?.content == "Answer")
        #expect(conversation.notice?.message == "Capture unavailable")
        #expect(conversation.notice?.recovery == .screenRecordingSettings)
    }

    @Test
    func testTransportFailureRemovesEmptyAssistantAndSurfacesNotice() async {
        let responses = ChatResponseAdapterStub(
            batches: [.failure(ChatResponseAdapterStub.Failure.failed)]
        )
        let conversation = ChatConversation(
            credentials: ChatCredentialStub(value: "secret"),
            responses: responses
        )

        conversation.submit("Hello")
        await waitUntilSettled(conversation)

        #expect(conversation.messages.map(\.role) == [.user])
        #expect(conversation.notice?.message == "Response failed")
        #expect(conversation.notice?.recovery == .settings)
    }

    @Test
    func testStartingNewConversationCancelsAndClearsCurrentTurn() {
        let responses = ChatResponseAdapterStub(batches: [.pending])
        let conversation = ChatConversation(
            credentials: ChatCredentialStub(value: "secret"),
            responses: responses
        )
        conversation.submit("Hello")

        conversation.startNewConversation()

        #expect(conversation.messages.isEmpty)
        #expect(!conversation.isResponding)
        #expect(conversation.notice == nil)
        #expect(conversation.draft == "")
    }

    @Test
    func testCancelledTurnCannotFinishANewerTurn() async {
        let responses = ChatResponseAdapterStub(batches: [.pending, .pending])
        let conversation = ChatConversation(
            credentials: ChatCredentialStub(value: "secret"),
            responses: responses
        )

        conversation.submit("First")
        await waitForRequestCount(1, in: responses)
        conversation.startNewConversation()
        conversation.submit("Second")
        await waitForRequestCount(2, in: responses)

        responses.finishPending(at: 0, with: [.completed("stale")])
        await Task.yield()

        #expect(conversation.isResponding)
        #expect(conversation.messages.first?.content == "Second")

        responses.finishPending(
            at: 1,
            with: [.textDelta("Current"), .completed("current")]
        )
        await waitUntilSettled(conversation)

        #expect(conversation.messages.last?.content == "Current")
    }

    private func waitUntilSettled(_ conversation: ChatConversation) async {
        for _ in 0..<1_000 where conversation.isResponding {
            await Task.yield()
        }
        #expect(!conversation.isResponding, "Conversation did not settle")
    }

    private func waitForRequestCount(
        _ count: Int,
        in responses: ChatResponseAdapterStub
    ) async {
        for _ in 0..<1_000 where responses.requests.count < count {
            await Task.yield()
        }
        #expect(responses.requests.count == count, "Response adapter was not called")
    }
}

@MainActor
private struct ChatCredentialStub: ChatCredentialProviding {
    let value: String?

    func loadCredential() -> String? {
        value
    }
}

@MainActor
private final class ChatResponseAdapterStub: ChatResponseStreaming {
    enum Failure: LocalizedError {
        case failed

        var errorDescription: String? { "Response failed" }
    }

    enum Batch {
        case events([ChatResponseEvent])
        case failure(Error)
        case pending
    }

    private var batches: [Batch]
    private(set) var requests: [ChatResponseRequest] = []
    private var pendingContinuations: [
        AsyncThrowingStream<ChatResponseEvent, Error>.Continuation
    ] = []

    init(batches: [Batch]) {
        self.batches = batches
    }

    func streamResponse(
        for request: ChatResponseRequest
    ) -> AsyncThrowingStream<ChatResponseEvent, Error> {
        requests.append(request)
        let batch = batches.removeFirst()

        return AsyncThrowingStream { continuation in
            switch batch {
            case .events(let events):
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            case .failure(let error):
                continuation.finish(throwing: error)
            case .pending:
                pendingContinuations.append(continuation)
            }
        }
    }

    func finishPending(at index: Int, with events: [ChatResponseEvent]) {
        let continuation = pendingContinuations[index]
        for event in events {
            continuation.yield(event)
        }
        continuation.finish()
    }
}
