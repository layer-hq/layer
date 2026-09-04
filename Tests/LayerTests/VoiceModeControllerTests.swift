import Foundation
import Testing
@testable import Layer

@Suite
@MainActor
struct VoiceModeControllerTests {
    @Test
    func startWithoutAPIKeySetsSettingsNoticeAndStaysIdle() {
        let controller = VoiceModeController(credentials: ChatCredentialStub(value: nil))

        controller.start()

        #expect(controller.state == .idle)
        #expect(controller.isActive == false)
        #expect(controller.notice?.recovery == .settings)
        #expect(controller.notice?.message.isEmpty == false)
    }

    @Test
    func toggleFromIdleWithoutKeyRoutesToStart() {
        let controller = VoiceModeController(credentials: ChatCredentialStub(value: nil))

        controller.toggle()

        #expect(controller.state == .idle)
        #expect(controller.isActive == false)
        #expect(controller.notice?.recovery == .settings)
    }

    @Test
    func stopFromIdleIsNoOp() {
        let controller = VoiceModeController(credentials: ChatCredentialStub(value: nil))

        controller.stop()

        #expect(controller.state == .idle)
        #expect(controller.isActive == false)
        #expect(controller.notice == nil)
    }

    @Test
    func dismissNoticeClearsNotice() {
        let controller = VoiceModeController(credentials: ChatCredentialStub(value: nil))
        controller.start()
        #expect(controller.notice != nil)

        controller.dismissNotice()

        #expect(controller.notice == nil)
    }

    @Test
    func startIsIdempotentUntilKeyIsProvided() {
        let controller = VoiceModeController(credentials: ChatCredentialStub(value: nil))

        controller.start()
        controller.start()

        #expect(controller.state == .idle)
        #expect(controller.notice?.recovery == .settings)
    }
}

@MainActor
private struct ChatCredentialStub: ChatCredentialProviding {
    let value: String?

    func loadCredential() -> String? {
        value
    }
}
