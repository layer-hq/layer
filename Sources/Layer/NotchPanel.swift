import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class NotchSession: ObservableObject {
    @Published var notice: Notice?
    @Published var isExpanded = false
    @Published var isGenerating = false
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
    private var expandGeneration = 0
    private let collector: InvocationInputsCollector
    private let screenContextAcquisition: ScreenContextAcquisition
    private let frontmostExternalApplication: () -> NSRunningApplication?
    private let promptFocusRequests = PassthroughSubject<Void, Never>()
    private let session = NotchSession()
    private let voiceMode = VoiceModeController()
    private let onSelect: () -> Void
    private let onSubmitPrompt: (String, Bool) -> Void
    private let onCancelGeneration: () -> Void
    private var generatingEscapeMonitor: Any?

    init(
        collector: InvocationInputsCollector,
        screenContextAcquisition: ScreenContextAcquisition,
        frontmostExternalApplication: @escaping () -> NSRunningApplication?,
        onSelect: @escaping () -> Void,
        onSubmitPrompt: @escaping (String, Bool) -> Void,
        onCancelGeneration: @escaping () -> Void
    ) {
        self.collector = collector
        self.screenContextAcquisition = screenContextAcquisition
        self.frontmostExternalApplication = frontmostExternalApplication
        self.onSelect = onSelect
        self.onSubmitPrompt = onSubmitPrompt
        self.onCancelGeneration = onCancelGeneration

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 40),
            level: .statusBar
        )

        hasShadow = true
        escapeKeyMonitor = EscapeKeyMonitor { [weak self] window in
            guard let self else { return false }
            if session.isGenerating {
                cancelGeneration()
                return true
            }
            guard window === self else { return false }
            if voiceMode.isActive {
                voiceMode.stop()
            }
            collector.clear()
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
        let voiceActive = voiceMode.isActive
        session.isExpanded = voiceActive
        contentViewController = NSHostingController(
            rootView: NotchView(
                session: session,
                voiceMode: voiceMode,
                topInset: layout.obscuredHeight,
                expandedWidth: layout.expandedSize.width,
                promptFocusRequests: promptFocusRequests.eraseToAnyPublisher(),
                onHoverChange: { [weak self] hovering in
                    self?.handleHoverChange(hovering)
                },
                onSelect: { [weak self] in
                    self?.startSelection()
                },
                onSubmitPrompt: { [weak self] prompt, insertMode in
                    self?.submitPrompt(prompt, insertMode: insertMode)
                },
                onToggleVoice: { [weak self] in
                    self?.toggleVoice()
                },
                onContentHeightChange: { [weak self] height in
                    self?.handleContentHeightChange(height)
                }
            )
        )
        setFrame(
            frame(
                for: voiceActive ? layout.expandedSize : layout.collapsedSize,
                on: screen
            ),
            display: true
        )
    }

    func stopVoice() {
        voiceMode.stop()
    }

    func toggleVoice() {
        if voiceMode.isActive {
            voiceMode.stop()
            return
        }
        Task { [weak self] in
            guard let self else { return }
            await prepareForFocusSteal()
            presentExpanded()
            guard StoredChatCredentialAdapter().loadCredential()?.isEmpty == false else {
                voiceMode.start()
                return
            }
            let inputs = await collector.takeCurrent(
                capturingScreen: UserDefaults.standard.bool(forKey: "takeScreenContext"),
                using: screenContextAcquisition
            )
            if let notice = inputs.modelContext.screen.notice {
                session.notice = notice
            }
            voiceMode.start(inputs: inputs)
        }
    }

    func invoke(notice: Notice? = nil) {
        setGenerating(false)
        session.notice = notice
        Task { [weak self] in
            guard let self else { return }
            await prepareForFocusSteal()
            presentExpanded()
            promptFocusRequests.send()
        }
    }

    func showNotice(_ notice: Notice) {
        session.notice = notice
    }

    func finishGenerating() {
        isPinnedUntilHover = false
        setExpanded(false)
        setGenerating(false)
    }

    func abortGenerating() {
        setGenerating(false)
        NSApplication.shared.activate(ignoringOtherApps: true)
        presentExpanded()
        promptFocusRequests.send()
    }

    private func cancelGeneration() {
        onCancelGeneration()
        abortGenerating()
    }

    private func setGenerating(_ generating: Bool) {
        session.isGenerating = generating
        if generating {
            guard generatingEscapeMonitor == nil else { return }
            generatingEscapeMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: .keyDown
            ) { [weak self] event in
                guard event.keyCode == EscapeKeyMonitor.keyCode else { return }
                Task { @MainActor in
                    self?.cancelGeneration()
                }
            }
        } else if let generatingEscapeMonitor {
            NSEvent.removeMonitor(generatingEscapeMonitor)
            self.generatingEscapeMonitor = nil
        }
    }

    private func presentExpanded() {
        if currentLayout == nil {
            positionOnActiveScreen()
        }

        isPinnedUntilHover = true
        pendingCollapse?.cancel()
        pendingCollapse = nil
        orderFrontRegardless()
        setExpanded(true)
        makeKey()
    }

    private func handleHoverChange(_ hovering: Bool) {
        if hovering {
            pendingCollapse?.cancel()
            pendingCollapse = nil
            isPinnedUntilHover = false
            expandGeneration += 1
            let generation = expandGeneration
            Task { [weak self] in
                guard let self else { return }
                await prepareForFocusSteal()
                guard generation == expandGeneration else { return }
                setExpanded(true)
            }
        } else if !isPinnedUntilHover, !session.isGenerating {
            expandGeneration += 1
            scheduleCollapseCheck()
        }
    }

    private func submitPrompt(_ prompt: String, insertMode: Bool) {
        if insertMode {
            session.notice = nil
            setGenerating(true)
            isPinnedUntilHover = true
            pendingCollapse?.cancel()
            pendingCollapse = nil
        } else {
            setExpanded(false)
        }
        onSubmitPrompt(prompt, insertMode)
    }

    private func startSelection() {
        session.notice = nil
        setExpanded(false)
        onSelect()
    }

    private func scheduleCollapseCheck() {
        pendingCollapse?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isExpanded, !self.session.isGenerating else { return }

            let hoverBounds = self.frame.insetBy(dx: -6, dy: -6)
            if hoverBounds.contains(NSEvent.mouseLocation) {
                self.scheduleCollapseCheck()
            } else {
                self.collector.clear()
                self.setExpanded(false)
            }
        }

        pendingCollapse = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: workItem)
    }

    private func prepareForFocusSteal() async {
        await collector.prepareForFocusSteal(
            application: frontmostExternalApplication(),
            displayID: NSScreen.directDisplayIDUnderPointer,
            includeSelectedContent: UserDefaults.standard.bool(
                forKey: "includeSelectedContent"
            )
        )
    }

    private func setExpanded(_ expanded: Bool) {
        if !expanded && voiceMode.isActive {
            return
        }
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
