import Foundation
import Testing
@testable import Layer

@Suite
@MainActor
struct VoiceModeControllerTests {
    @Test
    func startWithoutAPIKeySetsSettingsNoticeAndStaysIdle() {
        let controller = VoiceModeController(providers: ModelProviderStub(value: nil))

        controller.start()

        #expect(controller.state == .idle)
        #expect(controller.isActive == false)
        #expect(controller.notice?.recovery == .settings)
        #expect(controller.notice?.message.isEmpty == false)
    }

    @Test
    func toggleFromIdleWithoutKeyRoutesToStart() {
        let controller = VoiceModeController(providers: ModelProviderStub(value: nil))

        controller.toggle()

        #expect(controller.state == .idle)
        #expect(controller.isActive == false)
        #expect(controller.notice?.recovery == .settings)
    }

    @Test
    func stopFromIdleIsNoOp() {
        let controller = VoiceModeController(providers: ModelProviderStub(value: nil))

        controller.stop()

        #expect(controller.state == .idle)
        #expect(controller.isActive == false)
        #expect(controller.notice == nil)
    }

    @Test
    func dismissNoticeClearsNotice() {
        let controller = VoiceModeController(providers: ModelProviderStub(value: nil))
        controller.start()
        #expect(controller.notice != nil)

        controller.dismissNotice()

        #expect(controller.notice == nil)
    }

    @Test
    func startIsIdempotentUntilKeyIsProvided() {
        let controller = VoiceModeController(providers: ModelProviderStub(value: nil))

        controller.start()
        controller.start()

        #expect(controller.state == .idle)
        #expect(controller.notice?.recovery == .settings)
    }

    @Test
    func liteLLMConnectionExplainsThatVoiceRequiresOpenAI() {
        let provider = ModelProviderConfiguration(
            kind: .liteLLM,
            apiKey: "key",
            model: "model"
        )
        let controller = VoiceModeController(
            providers: ModelProviderStub(value: provider)
        )

        controller.start()

        #expect(controller.state == .idle)
        #expect(controller.notice?.message.contains("requires an OpenAI") == true)
        #expect(controller.notice?.recovery == .settings)
    }

    @Test
    func queuedRealtimeItemIncludesTextAndImageWithoutGreeting() throws {
        let attachment = ScreenAttachment(imageData: Data([1, 2, 3]))
        let events = VoiceRealtimeOpening.contextEvents(
            from: InvocationModelContext(
                selectedContent: "Selected note",
                screen: ScreenContextOutcome(attachment: attachment, notice: nil)
            )
        )

        #expect(events.count == 1)
        #expect(events.first?["type"] as? String == "conversation.item.create")
        #expect(events.first?["event_id"] as? String == VoiceRealtimeOpening.contextItemID)
        #expect(!events.contains { $0["type"] as? String == "response.create" })

        let item = try #require(events.first?["item"] as? [String: Any])
        #expect(item["id"] as? String == VoiceRealtimeOpening.contextItemID)
        let content = try #require(item["content"] as? [[String: Any]])
        #expect(content.contains { $0["type"] as? String == "input_text" })
        #expect(content.contains { $0["type"] as? String == "input_image" })
        #expect(content.contains { $0["image_url"] as? String == attachment.dataURL })
    }

    @Test
    func contextEventsDoNotCreateAResponse() {
        let events = VoiceRealtimeOpening.contextEvents(
            from: InvocationModelContext(
                selectedContent: "Selected note",
                screen: .notRequested
            )
        )

        #expect(events.count == 1)
        #expect(events.first?["type"] as? String == "conversation.item.create")
        #expect(!events.contains { $0["type"] as? String == "response.create" })
    }

    @Test
    func ignoresActiveResponseInProgressError() {
        #expect(
            VoiceRealtimeOpening.shouldIgnoreError(
                "Conversation already has an active response in progress: resp_EL1EdopVEQ4h6hy4pK2G9. Wait until the response is finished before creating a new one."
            )
        )
        #expect(!VoiceRealtimeOpening.shouldIgnoreError("OpenAI Realtime failed."))
    }
}

@MainActor
private struct ModelProviderStub: ModelProviderProviding {
    let value: ModelProviderConfiguration?

    func loadActiveProvider() -> ModelProviderConfiguration? {
        value
    }
}
