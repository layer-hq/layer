import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class NotchSession: ObservableObject {
    @Published var notice: Notice?
    @Published var isExpanded = false
}

@MainActor
final class NotchPanel: OverlayPanel {
    private struct Layout {
        let screen: NSScreen
        let obscuredHeight: CGFloat
        let collapsedSize: NSSize
        var expandedSize: NSSize
    }

    private var currentLayout: Layout?
    private var pendingCollapse: DispatchWorkItem?
    private var isPinnedUntilHover = false
    private var escapeKeyMonitor: EscapeKeyMonitor?
    private let promptFocusRequests = PassthroughSubject<Void, Never>()
    private let session = NotchSession()
    private let onSelect: () -> Void
    private let onSubmitPrompt: (String, Bool) -> Void

    init(
        onSelect: @escaping () -> Void,
        onSubmitPrompt: @escaping (String, Bool) -> Void
    ) {
        self.onSelect = onSelect
        self.onSubmitPrompt = onSubmitPrompt

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 40),
            level: .statusBar
        )

        hasShadow = true
        escapeKeyMonitor = EscapeKeyMonitor { [weak self] window in
            guard let self, window === self else { return false }
            setExpanded(false)
            return true
        }
    }

    private var isExpanded: Bool { session.isExpanded }

    func positionOnActiveScreen() {
        pendingCollapse?.cancel()

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let layout = makeLayout(for: screen)
        currentLayout = layout
        session.isExpanded = false
        contentViewController = NSHostingController(
            rootView: NotchView(
                session: session,
                topInset: layout.obscuredHeight,
                expandedWidth: layout.expandedSize.width,
                promptFocusRequests: promptFocusRequests.eraseToAnyPublisher(),
                onHoverChange: { [weak self] hovering in
                    self?.handleHoverChange(hovering)
                },
                onSelect: { [weak self] in
                    self?.startSelection()
                },
                onSubmitPrompt: { [weak self] prompt, takeScreenContext in
                    self?.submitPrompt(
                        prompt,
                        takeScreenContext: takeScreenContext
                    )
                },
                onContentHeightChange: { [weak self] height in
                    self?.handleContentHeightChange(height)
                }
            )
        )
        setFrame(frame(for: layout.collapsedSize, on: screen), display: true)
    }

    func invoke(notice: Notice? = nil) {
        if currentLayout == nil {
            positionOnActiveScreen()
        }

        session.notice = notice
        isPinnedUntilHover = true
        pendingCollapse?.cancel()
        pendingCollapse = nil
        orderFrontRegardless()
        setExpanded(true)
        makeKey()
        promptFocusRequests.send()
    }

    private func handleHoverChange(_ hovering: Bool) {
        if hovering {
            pendingCollapse?.cancel()
            pendingCollapse = nil
            isPinnedUntilHover = false
            setExpanded(true)
        } else if !isPinnedUntilHover {
            scheduleCollapseCheck()
        }
    }

    private func submitPrompt(_ prompt: String, takeScreenContext: Bool) {
        setExpanded(false)
        onSubmitPrompt(prompt, takeScreenContext)
    }

    private func startSelection() {
        session.notice = nil
        setExpanded(false)
        onSelect()
    }

    private func scheduleCollapseCheck() {
        pendingCollapse?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isExpanded else { return }

            let hoverBounds = self.frame.insetBy(dx: -6, dy: -6)
            if hoverBounds.contains(NSEvent.mouseLocation) {
                self.scheduleCollapseCheck()
            } else {
                self.setExpanded(false)
            }
        }

        pendingCollapse = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: workItem)
    }

    private func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded, let layout = currentLayout else { return }
        session.isExpanded = expanded

        if !expanded {
            pendingCollapse?.cancel()
            pendingCollapse = nil
        }

        let size = expanded ? layout.expandedSize : layout.collapsedSize
        if expanded {
            makeKey()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = expanded ? 0.22 : 0.16
            context.timingFunction = CAMediaTimingFunction(
                name: expanded ? .easeOut : .easeIn
            )
            animator().setFrame(frame(for: size, on: layout.screen), display: true)
        }
    }

    private func handleContentHeightChange(_ contentHeight: CGFloat) {
        guard var layout = currentLayout else { return }

        let availableHeight = layout.obscuredHeight + layout.screen.visibleFrame.height
        let expandedHeight = min(
            availableHeight,
            layout.obscuredHeight + ceil(contentHeight)
        )
        guard abs(layout.expandedSize.height - expandedHeight) > 0.5 else {
            return
        }

        layout.expandedSize.height = expandedHeight
        currentLayout = layout

        guard isExpanded else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(
                frame(for: layout.expandedSize, on: layout.screen),
                display: true
            )
        }
    }

    private func makeLayout(for screen: NSScreen) -> Layout {
        let obscuredHeight = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        let notchWidth: CGFloat

        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            notchWidth = max(120, right.minX - left.maxX)
        } else {
            notchWidth = 148
        }

        return Layout(
            screen: screen,
            obscuredHeight: obscuredHeight,
            collapsedSize: NSSize(width: notchWidth, height: obscuredHeight + 2),
            expandedSize: NSSize(
                width: min(720, screen.visibleFrame.width - 32),
                height: obscuredHeight + 190
            )
        )
    }

    private func frame(for size: NSSize, on screen: NSScreen) -> NSRect {
        NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
