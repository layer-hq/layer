import AppKit
import Combine
import SwiftUI

@MainActor
final class ChatWindowController: NSWindowController, NSWindowDelegate {
    private static let defaultContentSize = NSSize(width: 450, height: 720)
    private static let minimumContentSize = NSSize(width: 360, height: 480)

    private let conversation = ChatConversation()
    private let dictation: DictationController
    private let dictationID = UUID()
    private let composerFocusRequests = PassthroughSubject<Void, Never>()
    private var escapeKeyMonitor: EscapeKeyMonitor?
    var onClose: (() -> Void)?

    init(
        dictation: DictationController,
        onOpenScreenRecordingSettings: @escaping () -> Void
    ) {
        self.dictation = dictation
        let conversation = self.conversation
        let composerFocusRequests = self.composerFocusRequests
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
                .fullSizeContentView
            ],
            backing: .buffered,
            defer: false
        )
        let hostingController = NSHostingController(
            rootView: ChatView(
                conversation: conversation,
                dictation: dictation,
                dictationID: dictationID,
                composerFocusRequests: composerFocusRequests.eraseToAnyPublisher(),
                onOpenScreenRecordingSettings: onOpenScreenRecordingSettings,
                onClose: { [weak window] in window?.close() },
                onScrollButtonVisibilityChange: nil
            )
        )
        window.contentViewController = hostingController
        window.title = "Layer"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.setContentSize(Self.defaultContentSize)
        window.minSize = Self.minimumContentSize
        window.center()

        super.init(window: window)
        window.delegate = self
        escapeKeyMonitor = EscapeKeyMonitor { [weak self] keyWindow in
            guard let self, let window = self.window, keyWindow === window else {
                return false
            }
            if dictation.surface == .chat(dictationID), dictation.isActive {
                dictation.cancel()
                return true
            }
            window.close()
            return true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginDictation() {
        dictation.start(surface: .chat(dictationID))
    }

    func show(
        with prompt: String,
        modelContext: InvocationModelContext
    ) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        conversation.submit(prompt, modelContext: modelContext)
    }

    func windowWillClose(_ notification: Notification) {
        if dictation.surface == .chat(dictationID) {
            dictation.cancel()
        }
        conversation.startNewConversation()
        escapeKeyMonitor = nil
        onClose?()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.composerFocusRequests.send()
        }
    }
}
