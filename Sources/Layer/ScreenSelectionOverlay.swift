import AppKit
import Combine
import SwiftUI

@MainActor
final class ScreenSelectionOverlayController: NSWindowController {
    private var escapeKeyMonitor: EscapeKeyMonitor?
    private let panels: [OverlayPanel]
    private let onSubmit: (String, ScreenAttachment) -> Void
    private let onCancel: () -> Void
    private let onFailure: (Error) -> Void
    private let activateApplication: () -> Void

    init(
        sources: [ScreenSelectionSource],
        onSubmit: @escaping (String, ScreenAttachment) -> Void,
        onCancel: @escaping () -> Void,
        onFailure: @escaping (Error) -> Void,
        activateApplication: @escaping () -> Void = {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    ) {
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        self.onFailure = onFailure
        self.activateApplication = activateApplication

        let pointer = NSEvent.mouseLocation
        let built = sources.map { source -> (ScreenSelectionSource, OverlayPanel) in
            (source, Self.makePanel(covering: source.screen.frame))
        }
        self.panels = built.map(\.1)
        let preferred = built.first { $0.0.screen.frame.contains(pointer) }?.1
            ?? built.first?.1
        super.init(window: preferred)

        for (source, panel) in built {
            panel.contentView = ScreenSelectionView(
                onActivate: { [weak self, weak panel] in
                    self?.makeActive(panel)
                },
                onSubmit: { [weak self] prompt, selection in
                    self?.submit(prompt: prompt, selection: selection, source: source)
                }
            )
        }

        escapeKeyMonitor = EscapeKeyMonitor { [weak self] window in
            guard let self, let window,
                  panels.contains(where: { $0 === window }) else {
                return false
            }
            closeOverlay()
            onCancel()
            return true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        activateApplication()
        for panel in panels {
            panel.orderFrontRegardless()
        }
        window?.makeKey()
        NSCursor.crosshair.set()
    }

    private func makeActive(_ panel: OverlayPanel?) {
        guard let panel else { return }
        for other in panels where other !== panel {
            (other.contentView as? ScreenSelectionView)?.resetSelection()
        }
        window = panel
        panel.makeKey()
    }

    private func closeOverlay() {
        escapeKeyMonitor = nil
        panels.forEach { $0.orderOut(nil) }
    }

    private func submit(
        prompt: String,
        selection: CGRect,
        source: ScreenSelectionSource
    ) {
        do {
            let attachment = try source.attachment(for: selection)
            closeOverlay()
            onSubmit(prompt, attachment)
        } catch {
            closeOverlay()
            onFailure(error)
        }
    }

    private static func makePanel(covering frame: CGRect) -> OverlayPanel {
        let panel = OverlayPanel(contentRect: frame, level: .screenSaver)
        panel.hasShadow = false
        panel.setFrame(frame, display: true)
        return panel
    }
}

private struct SelectionPromptView: View {
    @State private var prompt = ""
    let focusRequests: AnyPublisher<Void, Never>
    let onSubmit: (String) -> Void

    var body: some View {
        PromptField(
            text: $prompt,
            placeholder: "Ask about this selection",
            shouldFocus: true,
            focusRequests: focusRequests,
            onSubmit: onSubmit
        )
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }
}

@MainActor
private final class ScreenSelectionView: NSView {
    private enum DragAction {
        case create
        case move
        case resize(Handle)
    }

    private enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    private let minimumSelectionSize: CGFloat = 32
    private let onActivate: () -> Void
    private let onSubmit: (String, CGRect) -> Void
    private var selection: CGRect?
    private var dragAction: DragAction = .create
    private var dragStart = CGPoint.zero
    private var originalSelection = CGRect.zero
    private let promptFocusRequests = PassthroughSubject<Void, Never>()
    private var promptHost: NSHostingView<SelectionPromptView>?

    init(
        onActivate: @escaping () -> Void,
        onSubmit: @escaping (String, CGRect) -> Void
    ) {
        self.onActivate = onActivate
        self.onSubmit = onSubmit
        super.init(frame: .zero)
    }

    func resetSelection() {
        selection = nil
        promptHost?.isHidden = true
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let shade = NSBezierPath(rect: bounds)
        if let selection {
            shade.append(
                NSBezierPath(
                    roundedRect: selection,
                    xRadius: 16,
                    yRadius: 16
                )
            )
            shade.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.38).setFill()
        shade.fill()

        guard let selection else { return }
        let highlight = NSColor(
            calibratedRed: 0.91,
            green: 1,
            blue: 0.28,
            alpha: 1
        )
        highlight.setStroke()
        let border = NSBezierPath(
            roundedRect: selection.insetBy(dx: 1, dy: 1),
            xRadius: 16,
            yRadius: 16
        )
        border.lineWidth = 1.5
        border.setLineDash([3, 3], count: 2, phase: 0)
        border.stroke()

        for rect in handleRects(for: selection).values {
            highlight.setFill()
            NSBezierPath(rect: rect).fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        onActivate()
        dragStart = convert(event.locationInWindow, from: nil)
        promptHost?.isHidden = true

        if let selection {
            originalSelection = selection
            if let handle = handle(at: dragStart, selection: selection) {
                dragAction = .resize(handle)
            } else if selection.contains(dragStart) {
                dragAction = .move
                NSCursor.closedHand.set()
            } else {
                dragAction = .create
                self.selection = CGRect(origin: dragStart, size: .zero)
            }
        } else {
            dragAction = .create
            selection = CGRect(origin: dragStart, size: .zero)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        switch dragAction {
        case .create:
            selection = rect(from: dragStart, to: point)
        case .move:
            var moved = originalSelection.offsetBy(
                dx: point.x - dragStart.x,
                dy: point.y - dragStart.y
            )
            moved.origin.x = min(max(bounds.minX, moved.origin.x), bounds.maxX - moved.width)
            moved.origin.y = min(max(bounds.minY, moved.origin.y), bounds.maxY - moved.height)
            selection = moved
        case .resize(let handle):
            selection = resized(originalSelection, with: handle, to: point)
        }

        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard var selection else { return }

        if selection.width < minimumSelectionSize {
            selection.size.width = minimumSelectionSize
        }
        if selection.height < minimumSelectionSize {
            selection.size.height = minimumSelectionSize
        }
        selection = selection.intersection(bounds)
        self.selection = selection
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        showPrompt(for: selection)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
        guard let selection else { return }

        addCursorRect(selection, cursor: .openHand)
        for (handle, rect) in handleRects(for: selection) {
            addCursorRect(
                rect.insetBy(dx: -4, dy: -4),
                cursor: cursor(for: handle)
            )
        }
    }

    private func showPrompt(for selection: CGRect) {
        if promptHost == nil {
            let host = NSHostingView(
                rootView: SelectionPromptView(
                    focusRequests: promptFocusRequests.eraseToAnyPublisher(),
                    onSubmit: { [weak self] prompt in
                        guard let self,
                              let selection = self.selection else { return }
                        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        self.onSubmit(trimmed, selection)
                    }
                )
            )
            promptHost = host
            addSubview(host)
        }

        promptHost?.frame = promptFrame(for: selection)
        promptHost?.isHidden = false
        window?.makeKey()
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeKey()
            self?.promptFocusRequests.send()
        }
    }

    private func promptFrame(for selection: CGRect) -> CGRect {
        let margin: CGFloat = 12
        let gap: CGFloat = 8
        let height: CGFloat = 76
        let width = min(520, max(280, selection.width))
        let x = min(
            max(margin, selection.midX - width / 2),
            bounds.maxX - width - margin
        )

        if selection.maxY + gap + height <= bounds.maxY - margin {
            return CGRect(x: x, y: selection.maxY + gap, width: width, height: height)
        }
        if selection.minY - gap - height >= bounds.minY + margin {
            return CGRect(x: x, y: selection.minY - gap - height, width: width, height: height)
        }

        return CGRect(
            x: x,
            y: min(
                max(bounds.minY + margin, selection.maxY - height - margin),
                bounds.maxY - height - margin
            ),
            width: width,
            height: height
        )
    }

    private func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        ).intersection(bounds)
    }

    private func resized(_ rect: CGRect, with handle: Handle, to point: CGPoint) -> CGRect {
        var left = rect.minX
        var right = rect.maxX
        var bottom = rect.minY
        var top = rect.maxY

        if [.topLeft, .left, .bottomLeft].contains(handle) {
            left = min(max(bounds.minX, point.x), right - minimumSelectionSize)
        }
        if [.topRight, .right, .bottomRight].contains(handle) {
            right = max(min(bounds.maxX, point.x), left + minimumSelectionSize)
        }
        if [.bottomLeft, .bottom, .bottomRight].contains(handle) {
            bottom = min(max(bounds.minY, point.y), top - minimumSelectionSize)
        }
        if [.topLeft, .top, .topRight].contains(handle) {
            top = max(min(bounds.maxY, point.y), bottom + minimumSelectionSize)
        }

        return CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
    }

    private func handle(at point: CGPoint, selection: CGRect) -> Handle? {
        handleRects(for: selection).first {
            $0.value.insetBy(dx: -5, dy: -5).contains(point)
        }?.key
    }

    private func handleRects(for selection: CGRect) -> [Handle: CGRect] {
        let size: CGFloat = 12
        func rect(_ point: CGPoint) -> CGRect {
            CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        }

        return [
            .topLeft: rect(CGPoint(x: selection.minX, y: selection.maxY)),
            .top: rect(CGPoint(x: selection.midX, y: selection.maxY)),
            .topRight: rect(CGPoint(x: selection.maxX, y: selection.maxY)),
            .right: rect(CGPoint(x: selection.maxX, y: selection.midY)),
            .bottomRight: rect(CGPoint(x: selection.maxX, y: selection.minY)),
            .bottom: rect(CGPoint(x: selection.midX, y: selection.minY)),
            .bottomLeft: rect(CGPoint(x: selection.minX, y: selection.minY)),
            .left: rect(CGPoint(x: selection.minX, y: selection.midY))
        ]
    }

    private func cursor(for handle: Handle) -> NSCursor {
        switch handle {
        case .top, .bottom:
            return .resizeUpDown
        case .left, .right:
            return .resizeLeftRight
        case .topLeft, .topRight, .bottomRight, .bottomLeft:
            return .crosshair
        }
    }
}
