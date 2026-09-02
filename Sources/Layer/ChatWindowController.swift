import AppKit
import Combine
import SwiftUI

@MainActor
final class ChatWindowController: NSWindowController, NSWindowDelegate {
    private let conversation = ChatConversation()
    private let composerFocusRequests = PassthroughSubject<Void, Never>()
    private var escapeKeyMonitor: EscapeKeyMonitor?
    var onClose: (() -> Void)?

    init(
        onOpenScreenRecordingSettings: @escaping () -> Void
    ) {
        let conversation = self.conversation
        let composerFocusRequests = self.composerFocusRequests
        let hostingController = NSHostingController(
            rootView: ChatView(
                conversation: conversation,
                composerFocusRequests: composerFocusRequests.eraseToAnyPublisher(),
                onOpenScreenRecordingSettings: onOpenScreenRecordingSettings
            )
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Layer"
        window.styleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable
        ]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 680, height: 700))
        window.minSize = NSSize(width: 560, height: 520)
        window.center()

        super.init(window: window)
        window.delegate = self
        escapeKeyMonitor = EscapeKeyMonitor { [weak window] keyWindow in
            guard let window, keyWindow === window else { return false }
            window.performClose(nil)
            return true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(
        with prompt: String,
        screenContext: ScreenContextOutcome
    ) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        conversation.submit(prompt, screenContext: screenContext)
    }

    func windowWillClose(_ notification: Notification) {
        conversation.startNewConversation()
        escapeKeyMonitor = nil
        onClose?()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        composerFocusRequests.send()
    }
}
