import AppKit
import SwiftUI

struct ArrowCursorArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        CursorRectView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class CursorRectView: NSView {
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .arrow)
        }

        override func layout() {
            super.layout()
            window?.invalidateCursorRects(for: self)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

extension View {
    func arrowCursor() -> some View {
        overlay { ArrowCursorArea() }
    }
}
