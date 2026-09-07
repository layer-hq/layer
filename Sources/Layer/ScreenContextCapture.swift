import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

struct ScreenAttachment: Equatable, Sendable {
    let imageData: Data

    var dataURL: String {
        "data:image/jpeg;base64,\(imageData.base64EncodedString())"
    }

    /// Voice WebRTC messages are capped near 64KB; 40KB JPEG leaves room for base64 + JSON.
    /// Keep 1280px and drop quality first — shrinking to 512px made sheets unreadable.
    func constrainedForRealtime(maxEncodedBytes: Int = 40_000) -> ScreenAttachment {
        guard let source = NSBitmapImageRep(data: imageData)?.cgImage else { return self }
        var best = imageData
        var quality: CGFloat = 0.7
        for dimension in [1_280, 1_024, 768, 512] {
            let resized = scaledImage(source, maximumDimension: dimension)
            let bitmap = NSBitmapImageRep(cgImage: resized)
            while quality >= 0.15 {
                guard let encoded = bitmap.representation(
                    using: .jpeg,
                    properties: [.compressionFactor: quality]
                ) else {
                    return ScreenAttachment(imageData: best)
                }
                best = encoded
                if encoded.count <= maxEncodedBytes {
                    return ScreenAttachment(imageData: encoded)
                }
                quality -= 0.1
            }
            quality = 0.45
        }
        return ScreenAttachment(imageData: best)
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
    func captureDisplay(id: CGDirectDisplayID?) async throws -> ScreenAttachment
}

@MainActor
final class ScreenContextAcquisition {
    private let capture: any ScreenContextCapturing

    init(capture: any ScreenContextCapturing = SystemScreenContextCapture()) {
        self.capture = capture
    }

    func acquire(
        requested: Bool,
        displayID: CGDirectDisplayID? = nil
    ) async -> ScreenContextOutcome {
        guard requested else { return .notRequested }

        do {
            return ScreenContextOutcome(
                attachment: try await capture.captureDisplay(
                    id: displayID ?? NSScreen.directDisplayIDUnderPointer
                ),
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

enum ScreenCaptureTarget {
    static func resolveDisplayID(
        preferred: CGDirectDisplayID?,
        available: [CGDirectDisplayID]
    ) -> CGDirectDisplayID? {
        if let preferred, available.contains(preferred) { return preferred }
        return available.first
    }
}

@MainActor
struct SystemScreenContextCapture: ScreenContextCapturing {
    private static let maximumDimension = 2_560
    private static var didRequestAccessThisLaunch = false

    func captureDisplay(id: CGDirectDisplayID?) async throws -> ScreenAttachment {
        try ensureAccess()
        do {
            return try await captureExcludingLayer(displayID: id)
        } catch {
            try? await Task<Never, Never>.sleep(for: .milliseconds(200))
            return try captureWithCoreGraphics(displayID: id)
        }
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

    private func captureExcludingLayer(
        displayID: CGDirectDisplayID?
    ) async throws -> ScreenAttachment {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        let availableIDs = content.displays.map(\.displayID)
        guard let resolvedID = ScreenCaptureTarget.resolveDisplayID(
            preferred: displayID,
            available: availableIDs
        ),
        let display = content.displays.first(where: { $0.displayID == resolvedID }) else {
            throw ScreenContextCaptureError.displayUnavailable
        }

        let layerProcessID = ProcessInfo.processInfo.processIdentifier
        let excluded = content.applications.filter { application in
            application.processID == layerProcessID
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: excluded,
            exceptingWindows: []
        )
        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.showsCursor = false

        let capturedImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        return try Self.makeAttachment(from: capturedImage)
    }

    private func captureWithCoreGraphics(displayID: CGDirectDisplayID?) throws -> ScreenAttachment {
        guard let resolvedID = displayID ?? NSScreen.directDisplayIDUnderPointer else {
            throw ScreenContextCaptureError.displayUnavailable
        }
        guard let capturedImage = CGDisplayCreateImage(resolvedID) else {
            throw ScreenContextCaptureError.captureFailed
        }
        return try Self.makeAttachment(from: capturedImage)
    }

    private func image(of screen: NSScreen) throws -> CGImage {
        guard let displayID = screen.directDisplayID else {
            throw ScreenContextCaptureError.displayUnavailable
        }
        guard let capturedImage = CGDisplayCreateImage(displayID) else {
            throw ScreenContextCaptureError.captureFailed
        }
        return capturedImage
    }

    fileprivate static func makeAttachment(from capturedImage: CGImage) throws -> ScreenAttachment {
        let preparedImage = scaledImage(capturedImage, maximumDimension: maximumDimension)
        let bitmap = NSBitmapImageRep(cgImage: preparedImage)
        guard let data = bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.82]
        ) else {
            throw ScreenContextCaptureError.encodingFailed
        }

        return ScreenAttachment(imageData: data)
    }
}

private func scaledImage(_ image: CGImage, maximumDimension: Int) -> CGImage {
    let sourceMaximum = max(image.width, image.height)
    guard sourceMaximum > maximumDimension else { return image }

    let scale = CGFloat(maximumDimension) / CGFloat(sourceMaximum)
    let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
    let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return image
    }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage() ?? image
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
        try SystemScreenContextCapture.makeAttachment(from: croppedImage(for: selection))
    }

    func copyImage(
        for selection: CGRect,
        to pasteboard: NSPasteboard = .general
    ) throws {
        let bitmap = NSBitmapImageRep(cgImage: try croppedImage(for: selection))
        guard let png = bitmap.representation(using: .png, properties: [:]),
              let tiff = bitmap.representation(using: .tiff, properties: [:]) else {
            throw ScreenContextCaptureError.encodingFailed
        }

        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setData(tiff, forType: .tiff)
        guard pasteboard.writeObjects([item]) else {
            throw ScreenContextCaptureError.encodingFailed
        }
    }

    private func croppedImage(for selection: CGRect) throws -> CGImage {
        let cropRect = ScreenSelectionGeometry.cropRect(
            selection: selection,
            screenSize: screen.frame.size,
            imageSize: CGSize(width: image.width, height: image.height)
        )
        guard cropRect.width > 0,
              cropRect.height > 0,
              let cropped = image.cropping(to: cropRect) else {
            throw ScreenContextCaptureError.captureFailed
        }
        return cropped
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

extension NSScreen {
    var directDisplayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }

    static var directDisplayIDUnderPointer: CGDirectDisplayID? {
        let location = NSEvent.mouseLocation
        let screen = screens.first { $0.frame.contains(location) }
            ?? main
            ?? screens.first
        return screen?.directDisplayID
    }
}
