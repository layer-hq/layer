import AppKit
import CoreGraphics
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
    func testNotRequestedSkipsCapture() async {
        let capture = ScreenContextCaptureStub(
            result: .success(ScreenAttachment(imageData: Data([1])))
        )
        let acquisition = ScreenContextAcquisition(capture: capture)

        let outcome = await acquisition.acquire(requested: false)

        #expect(outcome.attachment == nil)
        #expect(outcome.notice == nil)
        #expect(capture.callCount == 0)
    }

    @Test
    func testRequestedContextCapturesWithoutWaiting() async {
        let attachment = ScreenAttachment(imageData: Data([1, 2, 3]))
        let capture = ScreenContextCaptureStub(result: .success(attachment))
        let acquisition = ScreenContextAcquisition(capture: capture)

        let outcome = await acquisition.acquire(requested: true, displayID: 42)

        #expect(outcome.attachment?.imageData == attachment.imageData)
        #expect(outcome.notice == nil)
        #expect(capture.callCount == 1)
        #expect(capture.capturedDisplayID == 42)
    }

    @Test
    func testCaptureFailureBecomesRecoverableOutcome() async {
        let capture = ScreenContextCaptureStub(
            result: .failure(ScreenContextCaptureError.permissionDenied)
        )
        let acquisition = ScreenContextAcquisition(capture: capture)

        let outcome = await acquisition.acquire(requested: true)

        #expect(outcome.attachment == nil)
        #expect(
            outcome.notice?.message
                == ScreenContextCaptureError.permissionDenied.localizedDescription
        )
        #expect(outcome.notice?.recovery == .screenRecordingSettings)
    }

    @Test
    func testCaptureTargetHonorsPreferredDisplayAndLayerProcess() {
        #expect(
            ScreenCaptureTarget.resolveDisplayID(
                preferred: 11,
                available: [10, 11, 12]
            ) == 11
        )
        #expect(
            ScreenCaptureTarget.resolveDisplayID(
                preferred: 99,
                available: [10, 11]
            ) == 10
        )
    }

    @Test
    func realtimeConstraintKeeps1280WhenJPEGFits() {
        let attachment = ScreenAttachment(imageData: jpegFill(width: 2_000, height: 1_200, noise: false))
            .constrainedForRealtime()
        let result = NSBitmapImageRep(data: attachment.imageData)!

        #expect(max(result.pixelsWide, result.pixelsHigh) == 1_280)
        #expect(attachment.imageData.count <= 40_000)
    }

    @Test
    func realtimeConstraintFitsNoisyJPEGUnderDataChannelBudget() {
        let original = jpegFill(width: 2_000, height: 1_200, noise: true)
        let attachment = ScreenAttachment(imageData: original).constrainedForRealtime()
        let result = NSBitmapImageRep(data: attachment.imageData)!
        let longEdge = max(result.pixelsWide, result.pixelsHigh)

        #expect(original.count > 40_000)
        #expect(attachment.imageData.count <= 40_000)
        #expect(longEdge <= 1_280)
        #expect(longEdge >= 512)
    }
}

@MainActor
private final class ScreenContextCaptureStub: ScreenContextCapturing {
    private let result: Result<ScreenAttachment, Error>
    private(set) var callCount = 0
    private(set) var capturedDisplayID: CGDirectDisplayID?

    init(result: Result<ScreenAttachment, Error>) {
        self.result = result
    }

    func captureDisplay(id: CGDirectDisplayID?) async throws -> ScreenAttachment {
        callCount += 1
        capturedDisplayID = id
        return try result.get()
    }
}

private func jpegFill(width: Int, height: Int, noise: Bool) -> Data {
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    if noise {
        for y in stride(from: 0, to: height, by: 4) {
            for x in stride(from: 0, to: width, by: 4) {
                let v = CGFloat((x * 17 + y * 31) % 255) / 255
                context.setFillColor(
                    CGColor(red: v, green: 1 - v, blue: CGFloat((x + y) % 255) / 255, alpha: 1)
                )
                context.fill(CGRect(x: x, y: y, width: 4, height: 4))
            }
        }
    } else {
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    return bitmap.representation(
        using: .jpeg,
        properties: [.compressionFactor: 0.95]
    )!
}
