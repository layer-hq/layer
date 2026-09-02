import Foundation
import Testing
@testable import Layer

@Suite
@MainActor
struct ScreenContextAcquisitionTests {
    @Test
    func testSelectionMapsFromScreenPointsToImagePixels() {
        let crop = ScreenSelectionGeometry.cropRect(
            selection: CGRect(x: 100, y: 50, width: 300, height: 200),
            screenSize: CGSize(width: 1_000, height: 800),
            imageSize: CGSize(width: 2_000, height: 1_600)
        )

        #expect(crop == CGRect(x: 200, y: 1_100, width: 600, height: 400))
    }

    @Test
    func testNotRequestedSkipsPreparationAndCapture() async {
        let capture = ScreenContextCaptureStub(
            result: .success(ScreenAttachment(imageData: Data([1])))
        )
        var waitCount = 0
        let acquisition = ScreenContextAcquisition(
            capture: capture,
            wait: { _ in waitCount += 1 }
        )

        let outcome = await acquisition.acquire(requested: false)

        #expect(outcome.attachment == nil)
        #expect(outcome.notice == nil)
        #expect(waitCount == 0)
        #expect(capture.callCount == 0)
    }

    @Test
    func testRequestedContextWaitsForNotchThenCaptures() async {
        let attachment = ScreenAttachment(imageData: Data([1, 2, 3]))
        let capture = ScreenContextCaptureStub(result: .success(attachment))
        var waitCount = 0
        let acquisition = ScreenContextAcquisition(
            capture: capture,
            wait: { _ in waitCount += 1 }
        )

        let outcome = await acquisition.acquire(requested: true)

        #expect(outcome.attachment?.imageData == attachment.imageData)
        #expect(outcome.notice == nil)
        #expect(waitCount == 1)
        #expect(capture.callCount == 1)
    }

    @Test
    func testCaptureFailureBecomesRecoverableOutcome() async {
        let capture = ScreenContextCaptureStub(
            result: .failure(ScreenContextCaptureError.permissionDenied)
        )
        let acquisition = ScreenContextAcquisition(
            capture: capture,
            wait: { _ in }
        )

        let outcome = await acquisition.acquire(requested: true)

        #expect(outcome.attachment == nil)
        #expect(
            outcome.notice?.message
                == ScreenContextCaptureError.permissionDenied.localizedDescription
        )
        #expect(outcome.notice?.recovery == .screenRecordingSettings)
    }
}

@MainActor
private final class ScreenContextCaptureStub: ScreenContextCapturing {
    private let result: Result<ScreenAttachment, Error>
    private(set) var callCount = 0

    init(result: Result<ScreenAttachment, Error>) {
        self.result = result
    }

    func captureActiveDisplay() throws -> ScreenAttachment {
        callCount += 1
        return try result.get()
    }
}
