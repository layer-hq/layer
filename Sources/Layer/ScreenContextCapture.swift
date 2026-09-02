import AppKit
import CoreGraphics
import Foundation

struct ScreenAttachment: Equatable, Sendable {
    let imageData: Data

    var dataURL: String {
        "data:image/jpeg;base64,\(imageData.base64EncodedString())"
    }
}

struct ScreenContextOutcome: Equatable, Sendable {
    let attachment: ScreenAttachment?
    let notice: Notice?

    static let notRequested = ScreenContextOutcome(attachment: nil, notice: nil)
}

extension Notice {
    init(screenContextFailure error: Error) {
        var recovery: NoticeRecovery?
        if case ScreenContextCaptureError.permissionDenied = error {
            recovery = .screenRecordingSettings
        }
        self.init(message: error.localizedDescription, recovery: recovery)
    }
}

enum ScreenContextCaptureError: LocalizedError {
    case permissionDenied
    case displayUnavailable
    case captureFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen context was not attached. Enable Layer in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen Layer."
        case .displayUnavailable:
            return "Layer could not identify the active display."
        case .captureFailed:
            return "Layer could not capture the active display."
        case .encodingFailed:
            return "Layer could not prepare the screen context image."
        }
    }
}

@MainActor
protocol ScreenContextCapturing {
    func captureActiveDisplay() throws -> ScreenAttachment
}

@MainActor
final class ScreenContextAcquisition {
    typealias Wait = @MainActor (Duration) async -> Void

    private let capture: any ScreenContextCapturing
    private let wait: Wait

    init(
        capture: any ScreenContextCapturing = SystemScreenContextCapture(),
        wait: @escaping Wait = { duration in
            try? await Task<Never, Never>.sleep(for: duration)
        }
    ) {
        self.capture = capture
        self.wait = wait
    }

    func acquire(requested: Bool) async -> ScreenContextOutcome {
        guard requested else { return .notRequested }

        await wait(.milliseconds(200))

        do {
            return ScreenContextOutcome(
                attachment: try capture.captureActiveDisplay(),
                notice: nil
            )
        } catch {
            return ScreenContextOutcome(
                attachment: nil,
                notice: Notice(screenContextFailure: error)
            )
        }
    }
}

@MainActor
struct SystemScreenContextCapture: ScreenContextCapturing {
    private static let maximumDimension = 2_560
    private static var didRequestAccessThisLaunch = false

    func captureActiveDisplay() throws -> ScreenAttachment {
        try ensureAccess()
        let screen = try screenUnderPointer()
        return try Self.makeAttachment(from: try image(of: screen))
    }

    func prepareSelection() throws -> [ScreenSelectionSource] {
        try ensureAccess()
        let sources = try NSScreen.screens.map { screen in
            ScreenSelectionSource(screen: screen, image: try image(of: screen))
        }
        guard !sources.isEmpty else {
            throw ScreenContextCaptureError.displayUnavailable
        }
        return sources
    }

    private func ensureAccess() throws {
        if CGPreflightScreenCaptureAccess() { return }

        if !Self.didRequestAccessThisLaunch {
            Self.didRequestAccessThisLaunch = true

            NSApplication.shared.unhide(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)

            _ = CGRequestScreenCaptureAccess()
        }

        guard CGPreflightScreenCaptureAccess() else {
            throw ScreenContextCaptureError.permissionDenied
        }
    }

    private func screenUnderPointer() throws -> NSScreen {
        guard let screen = NSScreen.screens.first(where: {
            $0.frame.contains(NSEvent.mouseLocation)
        }) ?? NSScreen.main ?? NSScreen.screens.first else {
            throw ScreenContextCaptureError.displayUnavailable
        }
        return screen
    }

    private func image(of screen: NSScreen) throws -> CGImage {
        guard let displayNumber = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber else {
            throw ScreenContextCaptureError.displayUnavailable
        }

        let displayID = CGDirectDisplayID(displayNumber.uint32Value)
        guard let capturedImage = CGDisplayCreateImage(displayID) else {
            throw ScreenContextCaptureError.captureFailed
        }

        return capturedImage
    }

    fileprivate static func makeAttachment(from capturedImage: CGImage) throws -> ScreenAttachment {
        let preparedImage = Self.resizeIfNeeded(capturedImage)
        let bitmap = NSBitmapImageRep(cgImage: preparedImage)
        guard let data = bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.82]
        ) else {
            throw ScreenContextCaptureError.encodingFailed
        }

        return ScreenAttachment(imageData: data)
    }

    private static func resizeIfNeeded(_ image: CGImage) -> CGImage {
        let sourceMaximum = max(image.width, image.height)
        guard sourceMaximum > maximumDimension else { return image }

        let scale = CGFloat(maximumDimension) / CGFloat(sourceMaximum)
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}

@MainActor
struct ScreenSelectionSource {
    let screen: NSScreen
    fileprivate let image: CGImage

    init(screen: NSScreen, image: CGImage) {
        self.screen = screen
        self.image = image
    }

    func attachment(for selection: CGRect) throws -> ScreenAttachment {
        let cropRect = ScreenSelectionGeometry.cropRect(
            selection: selection,
            screenSize: screen.frame.size,
            imageSize: CGSize(width: image.width, height: image.height)
        )
        guard cropRect.width > 0,
              cropRect.height > 0,
              let croppedImage = image.cropping(to: cropRect) else {
            throw ScreenContextCaptureError.captureFailed
        }

        return try SystemScreenContextCapture.makeAttachment(from: croppedImage)
    }
}

enum ScreenSelectionGeometry {
    static func cropRect(
        selection: CGRect,
        screenSize: CGSize,
        imageSize: CGSize
    ) -> CGRect {
        guard screenSize.width > 0, screenSize.height > 0 else { return .zero }

        let clipped = selection.standardized.intersection(
            CGRect(origin: .zero, size: screenSize)
        )
        guard !clipped.isNull else { return .zero }

        let scaleX = imageSize.width / screenSize.width
        let scaleY = imageSize.height / screenSize.height
        return CGRect(
            x: clipped.minX * scaleX,
            y: (screenSize.height - clipped.maxY) * scaleY,
            width: clipped.width * scaleX,
            height: clipped.height * scaleY
        ).integral.intersection(CGRect(origin: .zero, size: imageSize))
    }
}
