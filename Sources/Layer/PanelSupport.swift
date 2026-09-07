import AppKit

@MainActor
class OverlayPanel: NSPanel {
    init(contentRect: NSRect, level: NSWindow.Level) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        self.level = level
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class EscapeKeyMonitor {
    static let keyCode: UInt16 = 53

    nonisolated(unsafe) private var monitor: Any?

    init(onEscape: @escaping @MainActor (NSWindow?) -> Bool) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == Self.keyCode,
                  onEscape(event.window) else {
                return event
            }
            return nil
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
