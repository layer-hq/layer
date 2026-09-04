import AppKit
import ApplicationServices

private typealias PasteboardContents = [[(NSPasteboard.PasteboardType, Data)]]

private func snapshot(_ pasteboard: NSPasteboard) -> PasteboardContents {
    pasteboard.pasteboardItems?.map { item in
        item.types.compactMap { type in
            item.data(forType: type).map { (type, $0) }
        }
    } ?? []
}

private func restorePasteboard(
    _ contents: PasteboardContents,
    to pasteboard: NSPasteboard
) {
    pasteboard.clearContents()
    let items = contents.map { contents in
        let item = NSPasteboardItem()
        for (type, data) in contents {
            item.setData(data, forType: type)
        }
        return item
    }
    if !items.isEmpty {
        pasteboard.writeObjects(items)
    }
}

private func postCommand(_ keyCode: CGKeyCode, to processID: pid_t) {
    let source = CGEventSource(stateID: .combinedSessionState)
    for keyDown in [true, false] {
        let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: keyDown
        )
        event?.flags = .maskCommand
        event?.postToPid(processID)
    }
}

@MainActor
struct TextInsertionContext {
    let element: AXUIElement?
    let selectedText: String?
    let selectedRange: CFRange?

    static func capture() -> TextInsertionContext {
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(),
            "AXFocusedUIElement" as CFString,
            &focusedValue
        ) == .success,
        let focusedValue,
        CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return TextInsertionContext(
                element: nil,
                selectedText: nil,
                selectedRange: nil
            )
        }

        let element = focusedValue as! AXUIElement

        var textValue: CFTypeRef?
        AXUIElementCopyAttributeValue(
            element,
            "AXSelectedText" as CFString,
            &textValue
        )
        let selectedText = (textValue as? String).flatMap {
            $0.isEmpty ? nil : $0
        }

        var rangeValue: CFTypeRef?
        var selectedRange: CFRange?
        if AXUIElementCopyAttributeValue(
            element,
            "AXSelectedTextRange" as CFString,
            &rangeValue
        ) == .success,
        let rangeValue,
        CFGetTypeID(rangeValue) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) {
                selectedRange = range
            }
        }

        return TextInsertionContext(
            element: element,
            selectedText: selectedText,
            selectedRange: selectedRange
        )
    }

    func usingCopiedSelection(_ text: String?) -> TextInsertionContext {
        guard let text, !text.isEmpty else { return self }
        return TextInsertionContext(
            element: nil,
            selectedText: text,
            selectedRange: nil
        )
    }

    static func copiedSelection(
        from application: NSRunningApplication
    ) async -> String? {
        let pasteboard = NSPasteboard.general
        let savedContents = snapshot(pasteboard)
        let initialChangeCount = pasteboard.changeCount

        // ponytail: editors that copy an unselected line are indistinguishable here.
        postCommand(0x08, to: application.processIdentifier)
        for _ in 0..<20 {
            try? await Task<Never, Never>.sleep(for: .milliseconds(10))
            guard pasteboard.changeCount != initialChangeCount else { continue }

            let copiedChangeCount = pasteboard.changeCount
            let text = pasteboard.string(forType: .string)
            if pasteboard.changeCount == copiedChangeCount {
                restorePasteboard(savedContents, to: pasteboard)
            }
            return text?.isEmpty == false ? text : nil
        }
        return nil
    }

    func restore() {
        guard let element else { return }
        AXUIElementSetAttributeValue(
            element,
            "AXFocused" as CFString,
            kCFBooleanTrue
        )
        guard var selectedRange,
              let rangeValue = AXValueCreate(.cfRange, &selectedRange) else {
            return
        }
        AXUIElementSetAttributeValue(
            element,
            "AXSelectedTextRange" as CFString,
            rangeValue
        )
    }
}

@MainActor
struct TextInserter {
    func insert(
        _ text: String,
        into application: NSRunningApplication,
        restoring context: TextInsertionContext?
    ) async {
        let pasteboard = NSPasteboard.general
        let savedContents = snapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let insertedChangeCount = pasteboard.changeCount

        application.activate(options: [.activateAllWindows])
        for _ in 0..<20 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier
                == application.processIdentifier {
                break
            }
            try? await Task<Never, Never>.sleep(for: .milliseconds(25))
        }
        context?.restore()
        try? await Task<Never, Never>.sleep(for: .milliseconds(50))

        postCommand(0x09, to: application.processIdentifier)

        try? await Task<Never, Never>.sleep(for: .milliseconds(150))
        guard pasteboard.changeCount == insertedChangeCount else { return }

        restorePasteboard(savedContents, to: pasteboard)
    }
}
