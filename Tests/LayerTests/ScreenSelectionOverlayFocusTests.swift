import AppKit
import Combine
import SwiftUI
import Testing
@testable import Layer

@Suite(.serialized)
@MainActor
struct ScreenSelectionOverlayFocusTests {
    @Test(.enabled(if: NSScreen.main != nil, "Requires a graphical session"))
    func overflowingConversationShowsScrollToBottomControl() async throws {
        let longResponse = String(
            repeating: "This is a response line that extends the conversation.\n\n",
            count: 80
        )
        let conversation = ChatConversation(
            initialMessages: [
                ChatMessage(role: .user, content: "Long answer, please."),
                ChatMessage(role: .assistant, content: longResponse)
            ]
        )
        var scrollButtonIsVisible = false
        let view = ChatView(
            conversation: conversation,
            composerFocusRequests: Empty<Void, Never>().eraseToAnyPublisher(),
            onOpenScreenRecordingSettings: {},
            onClose: {},
            onScrollButtonVisibilityChange: { isVisible in
                scrollButtonIsVisible = isVisible
            }
        )
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 600, height: 520))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }

        #expect(await becomesTrue { scrollButtonIsVisible })
    }

    @Test(.enabled(if: NSScreen.main != nil, "Requires a graphical session"))
    func arrowCursorOverlayLetsButtonClicksThrough() async throws {
        var clicks = 0
        let view = Button(label: "Send") { clicks += 1 }
            .frame(width: 200, height: 60)

        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 200, height: 60))
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }

        let contentView = try #require(window.contentView)
        let center = CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        click(at: center, in: window)

        #expect(await becomesTrue { clicks == 1 })
    }

    @Test(.enabled(if: NSScreen.main != nil, "Requires a graphical session"))
    func chatComposerRetainsFocusAfterSendingAMessage() async throws {
        let conversation = ChatConversation(
            credentials: ChatCredentialFake(),
            responses: ChatResponseFake()
        )
        let view = ChatView(
            conversation: conversation,
            composerFocusRequests: Empty<Void, Never>().eraseToAnyPublisher(),
            onOpenScreenRecordingSettings: {},
            onClose: {}
        )
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 600, height: 520))
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }

        #expect(await promptIsFocused(in: window))

        conversation.draft = "Question"
        conversation.submitDraft()
        #expect(await becomesTrue { !conversation.isResponding })

        #expect(await promptIsFocused(in: window))
    }

    @Test(.enabled(if: NSScreen.main != nil, "Requires a graphical session"))
    func promptFocusesOnAppearAndOnLaterFocusRequest() async throws {
        var text = ""
        let focusRequests = PassthroughSubject<Void, Never>()
        let prompt = PromptField(
            text: Binding(
                get: { text },
                set: { text = $0 }
            ),
            shouldFocus: true,
            focusRequests: focusRequests.eraseToAnyPublisher(),
            onSubmit: { _ in }
        )
        .frame(width: 320, height: 80)

        let controller = NSHostingController(rootView: prompt)
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 320, height: 80))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }

        #expect(await promptIsFocused(in: window))

        let contentView = try #require(window.contentView)
        window.makeFirstResponder(contentView)
        #expect(!(window.firstResponder is NSTextView))
        focusRequests.send()

        #expect(await promptIsFocused(in: window))
    }

    @Test(.enabled(if: NSScreen.main != nil, "Requires a graphical session"))
    func clickingEmptyPromptCardSpaceFocusesTheTextEditor() async throws {
        var text = ""
        let prompt = PromptField(
            text: Binding(
                get: { text },
                set: { text = $0 }
            ),
            shouldFocus: false,
            showsChrome: false,
            minTextHeight: 56,
            onSubmit: { _ in }
        ) {
            Color.clear.frame(height: 40)
        }
        .frame(width: 320, height: 120)

        let controller = NSHostingController(rootView: prompt)
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 320, height: 120))
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }

        let contentView = try #require(window.contentView)
        window.makeFirstResponder(contentView)
        #expect(!(window.firstResponder is NSTextView))

        click(at: CGPoint(x: 24, y: 20), in: window)

        #expect(await promptIsFocused(in: window))
    }

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

    private func click(at location: CGPoint, in window: NSWindow) {
        guard let contentView = window.contentView else { return }
        contentView.mouseDown(
            with: mouseEvent(.leftMouseDown, at: location, window: window)
        )
        contentView.mouseUp(
            with: mouseEvent(.leftMouseUp, at: location, window: window)
        )
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

    private func becomesTrue(_ value: () -> Bool) async -> Bool {
        for _ in 0..<20 {
            if value() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return false
    }
}

@MainActor
private struct ChatCredentialFake: ChatCredentialProviding {
    func loadCredential() -> String? { "secret" }
}

@MainActor
private final class ChatResponseFake: ChatResponseStreaming {
    func streamResponse(
        for request: ChatResponseRequest
    ) -> AsyncThrowingStream<ChatResponseEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.textDelta("Answer"))
            continuation.yield(.completed("turn"))
            continuation.finish()
        }
    }
}
