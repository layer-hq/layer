import AppKit
import Testing
@testable import Layer

@Suite
@MainActor
struct ScreenSelectionOverlayFocusTests {
    @Test(.enabled(if: NSScreen.main != nil, "Requires a graphical session"))
    func selectionActivatesAppAndRefocusesPromptAfterAdjustment() async throws {
        let screen = try #require(NSScreen.main)
        let image = try #require(
            CGContext(
                data: nil,
                width: 2,
                height: 2,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage()
        )
        var activationCount = 0
        let controller = ScreenSelectionOverlayController(
            sources: [ScreenSelectionSource(screen: screen, image: image)],
            onSubmit: { _, _ in },
            onCancel: {},
            onFailure: { _ in },
            activateApplication: {
                activationCount += 1
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        )
        controller.show()
        defer { controller.window?.orderOut(nil) }

        let window = try #require(controller.window)
        let view = try #require(window.contentView)
        #expect(window.canBecomeKey)
        #expect(window.isKeyWindow)
        drag(in: view, window: window, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 400, y: 300))

        #expect(activationCount == 1)
        #expect(await promptIsFocused(in: window))

        window.makeFirstResponder(view)
        drag(in: view, window: window, from: CGPoint(x: 200, y: 200), to: CGPoint(x: 240, y: 220))

        #expect(activationCount == 1)
        #expect(await promptIsFocused(in: window))
    }

    private func drag(
        in view: NSView,
        window: NSWindow,
        from start: CGPoint,
        to end: CGPoint
    ) {
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: start, window: window))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: end, window: window))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: end, window: window))
    }

    private func mouseEvent(
        _ type: NSEvent.EventType,
        at location: CGPoint,
        window: NSWindow
    ) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: type == .leftMouseUp ? 0 : 1
        )!
    }

    private func promptIsFocused(in window: NSWindow) async -> Bool {
        for _ in 0..<20 {
            if window.firstResponder is NSTextView {
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }
}
