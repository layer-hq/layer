import AppKit
import Combine
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import Layer

@Suite(.serialized)
@MainActor
struct ScreenSelectionOverlayFocusTests {
    @Test
    func screenContextChipLayoutStaysCompactAndLeavesRoomForFocus() {
        #expect(ScreenContextChipLayout.focusHaloClearance >= 4)
        #expect(ScreenContextChipLayout.maximumLabelWidth <= 140)
        #expect(ScreenContextChipLayout.hoverIconName(isAttached: false) == "plus")
        #expect(ScreenContextChipLayout.hoverIconName(isAttached: true) == "xmark")
    }

    @Test(.enabled(if: NSScreen.main != nil, "Requires a graphical session"))
    func commandVPastesClipboardImageAsAnAttachment() async throws {
        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboard(pasteboard)
        defer { restorePasteboard(snapshot, to: pasteboard) }

        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor.systemOrange.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 16, height: 16)).fill()
        image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(png, forType: .png)
        pasteboard.clearContents()
        try #require(pasteboard.writeObjects([pasteboardItem]))

        var text = ""
        let drafts = DraftAttachments()
        let prompt = PromptField(
            text: Binding(get: { text }, set: { text = $0 }),
            shouldFocus: true,
            topAccessory: nil,
            onPasteAttachments: { drafts.acceptPastedItems($0) },
            onPasteText: nil,
            onSubmit: { _ in }
        ) {
            EmptyView()
        }
        .frame(width: 320, height: 80)

        let controller = NSHostingController(rootView: prompt)
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 320, height: 80))
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try #require(await promptIsFocused(in: window))

        window.sendEvent(commandVEvent(for: window))

        #expect(await becomesTrue { drafts.attachments.count == 1 })
        let attachment = try #require(drafts.attachments.first)
        #expect(attachment.kind == .image)
        #expect(attachment.mediaType == "image/png")
        #expect(attachment.name.hasPrefix("Pasted Image "))
        #expect(text.isEmpty)
    }

    @Test(.enabled(if: NSScreen.main != nil, "Requires a graphical session"))
    func commandVPastesJPEGClipboardImageAsAnAttachment() async throws {
        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboard(pasteboard)
        defer { restorePasteboard(snapshot, to: pasteboard) }

        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 16, height: 16)).fill()
        image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let jpeg = try #require(bitmap.representation(using: .jpeg, properties: [:]))
        let jpegType = NSPasteboard.PasteboardType(UTType.jpeg.identifier)
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(jpeg, forType: jpegType)
        pasteboard.clearContents()
        try #require(pasteboard.writeObjects([pasteboardItem]))

        var text = ""
        let drafts = DraftAttachments()
        let prompt = PromptField(
            text: Binding(get: { text }, set: { text = $0 }),
            shouldFocus: true,
            topAccessory: nil,
            onPasteAttachments: { drafts.acceptPastedItems($0) },
            onPasteText: nil,
            onSubmit: { _ in }
        ) {
            EmptyView()
        }
        .frame(width: 320, height: 80)

        let controller = NSHostingController(rootView: prompt)
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 320, height: 80))
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try #require(await promptIsFocused(in: window))

        window.sendEvent(commandVEvent(for: window))

        #expect(await becomesTrue { drafts.attachments.count == 1 })
        let attachment = try #require(drafts.attachments.first)
        #expect(attachment.kind == .image)
        #expect(attachment.mediaType == "image/jpeg")
        #expect(attachment.name.hasSuffix(".jpg") || attachment.name.hasSuffix(".jpeg"))
        #expect(text.isEmpty)
    }

    @Test(.enabled(if: NSScreen.main != nil, "Requires a graphical session"))
    func commandVPastesChromeImageInTheActualNotchPanel() async throws {
        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboard(pasteboard)
        defer { restorePasteboard(snapshot, to: pasteboard) }

        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor.systemGreen.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 16, height: 16)).fill()
        image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(png, forType: .png)
        pasteboardItem.setString(
            #"<meta charset="utf-8"><img src="https://example.test/image.webp">"#,
            forType: .html
        )
        pasteboardItem.setString(
            "https://example.test/",
            forType: NSPasteboard.PasteboardType("org.chromium.source-url")
        )
        pasteboard.clearContents()
        try #require(pasteboard.writeObjects([pasteboardItem]))

        let session = NotchSession()
        session.isExpanded = true
        var attachmentAddedCount = 0
        let view = NotchView(
            session: session,
            voiceMode: VoiceModeController(),
            dictation: DictationController(),
            expandedWidth: 720,
            promptFocusRequests: Empty<Void, Never>().eraseToAnyPublisher(),
            onHoverChange: { _ in },
            onHoverScreenContextTarget: { _ in },
            onAttachmentAdded: { attachmentAddedCount += 1 },
            onSelect: {},
            onSubmitPrompt: { _, _, _, _ in },
            onToggleDictation: {},
            onContentHeightChange: { _ in }
        )
        .frame(width: 720, height: 400)

        let controller = NSHostingController(rootView: view)
        let window = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 400),
            level: .normal
        )
        window.contentViewController = controller
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try #require(await promptIsFocused(in: window))

        window.sendEvent(commandVEvent(for: window))

        #expect(await becomesTrue { attachmentAddedCount > 0 })
    }

    @Test(.enabled(if: NSScreen.main != nil, "Requires a graphical session"))
    func commandVPastesImageEmbeddedInABrowserWebArchive() async throws {
        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboard(pasteboard)
        defer { restorePasteboard(snapshot, to: pasteboard) }

        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor.systemPink.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 16, height: 16)).fill()
        image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let archive: [String: Any] = [
            "WebMainResource": [
                "WebResourceData": Data("<html><body></body></html>".utf8),
                "WebResourceMIMEType": "text/html",
                "WebResourceURL": "https://example.test/"
            ],
            "WebSubresources": [[
                "WebResourceData": png,
                "WebResourceMIMEType": "image/png",
                "WebResourceURL": "https://example.test/browser-image.png"
            ]]
        ]
        let archiveData = try PropertyListSerialization.data(
            fromPropertyList: archive,
            format: .binary,
            options: 0
        )
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(
            archiveData,
            forType: NSPasteboard.PasteboardType("com.apple.webarchive")
        )
        pasteboard.clearContents()
        try #require(pasteboard.writeObjects([pasteboardItem]))

        var text = ""
        let drafts = DraftAttachments()
        let prompt = PromptField(
            text: Binding(get: { text }, set: { text = $0 }),
            shouldFocus: true,
            topAccessory: nil,
            onPasteAttachments: { drafts.acceptPastedItems($0) },
            onPasteText: nil,
            onSubmit: { _ in }
        ) {
            EmptyView()
        }
        .frame(width: 320, height: 80)

        let controller = NSHostingController(rootView: prompt)
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 320, height: 80))
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try #require(await promptIsFocused(in: window))

        window.sendEvent(commandVEvent(for: window))

        #expect(await becomesTrue { drafts.attachments.count == 1 })
        let attachment = try #require(drafts.attachments.first)
        #expect(attachment.kind == .image)
        #expect(attachment.mediaType == "image/png")
        #expect(text.isEmpty)
    }

    @Test(.enabled(if: NSScreen.main != nil, "Requires a graphical session"))
    func collapsedNotchExposesAFileDropTarget() async throws {
        let session = NotchSession()
        session.isExpanded = false
        let view = NotchView(
            session: session,
            voiceMode: VoiceModeController(),
            dictation: DictationController(),
            expandedWidth: 720,
            promptFocusRequests: Empty<Void, Never>().eraseToAnyPublisher(),
            onHoverChange: { _ in },
            onHoverScreenContextTarget: { _ in },
            onAttachmentAdded: {},
            onSelect: {},
            onSubmitPrompt: { _, _, _, _ in },
            onToggleDictation: {},
            onContentHeightChange: { _ in }
        )
        .frame(width: 148, height: 40)

        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 148, height: 40))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }

        try? await Task.sleep(for: .milliseconds(100))
        let contentView = try #require(window.contentView)
        let point = CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)

        #expect(hasFileDropTarget(at: point, in: contentView))
    }

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
            dictation: DictationController(),
            dictationID: UUID(),
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
            providers: ModelProviderFake(),
            responses: ChatResponseFake()
        )
        let view = ChatView(
            conversation: conversation,
            dictation: DictationController(),
            dictationID: UUID(),
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

    private func commandVEvent(for window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "v",
            charactersIgnoringModifiers: "v",
            isARepeat: false,
            keyCode: 9
        )!
    }

    private func snapshotPasteboard(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        pasteboard.pasteboardItems?.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        } ?? []
    }

    private func restorePasteboard(
        _ snapshot: [[NSPasteboard.PasteboardType: Data]],
        to pasteboard: NSPasteboard
    ) {
        let items = snapshot.map { representations in
            let item = NSPasteboardItem()
            for (type, data) in representations {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
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

    private func hasFileDropTarget(at point: CGPoint, in root: NSView) -> Bool {
        var pending = [root]
        while let candidate = pending.popLast() {
            let localPoint = candidate.convert(point, from: root)
            if !candidate.registeredDraggedTypes.isEmpty,
               candidate.bounds.contains(localPoint) {
                return true
            }
            pending.append(contentsOf: candidate.subviews)
        }
        return false
    }
}

@MainActor
private struct ModelProviderFake: ModelProviderProviding {
    func loadActiveProvider() -> ModelProviderConfiguration? {
        ModelProviderConfiguration(
            kind: .openAI,
            apiKey: "secret",
            model: "test-model"
        )
    }
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
