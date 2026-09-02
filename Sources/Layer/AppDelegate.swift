import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchPanel: NotchPanel?
    private var selectionController: ScreenSelectionOverlayController?
    private var chatWindowControllers: [ChatWindowController] = []
    private var previousExternalApplication: NSRunningApplication?
    private let screenContextAcquisition = ScreenContextAcquisition()
    private var invocationShortcutRecognizer = DoubleModifierPressRecognizer()
    private var selectionShortcut: GlobalSelectionShortcut?
    private var localShortcutMonitor: Any?
    private var globalShortcutMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        InvocationShortcutPreferences.registerDefaults()
        SelectionShortcutPreferences.registerDefaults()
        startInvocationShortcutMonitoring()
        selectionShortcut = GlobalSelectionShortcut { [weak self] in
            self?.beginSelection()
        }
        updateSelectionShortcut()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateSelectionShortcut),
            name: UserDefaults.didChangeNotification,
            object: nil
        )

        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.showNotch() }
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showNotch()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        selectionShortcut?.invalidate()
        if let localShortcutMonitor {
            NSEvent.removeMonitor(localShortcutMonitor)
        }
        if let globalShortcutMonitor {
            NSEvent.removeMonitor(globalShortcutMonitor)
        }
    }

    private func showNotch() {
        let panel = notchPanel ?? makeNotchPanel()
        panel.positionOnActiveScreen()
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.orderFrontRegardless()
    }

    private func startInvocationShortcutMonitoring() {
        _ = CGRequestListenEventAccess()

        localShortcutMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.flagsChanged, .keyDown]
        ) { [weak self] event in
            self?.handleInvocationShortcutEvent(event)
            return event
        }
        globalShortcutMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .flagsChanged
        ) { [weak self] event in
            self?.handleInvocationShortcutEvent(event)
        }
    }

    private func handleInvocationShortcutEvent(_ event: NSEvent) {
        guard InvocationShortcutPreferences.isEnabled else {
            invocationShortcutRecognizer.reset()
            return
        }

        guard event.type == .flagsChanged else {
            invocationShortcutRecognizer.cancelSequence()
            return
        }

        if invocationShortcutRecognizer.processModifierFlags(
            event.modifierFlags,
            at: event.timestamp,
            modifier: InvocationShortcutPreferences.modifier
        ) {
            let panel = notchPanel ?? makeNotchPanel()
            panel.invoke()
        }
    }

    @objc private func updateSelectionShortcut() {
        selectionShortcut?.register(
            keyCode: SelectionShortcutPreferences.keyCode,
            modifiers: SelectionShortcutPreferences.modifiers,
            enabled: SelectionShortcutPreferences.isEnabled
        )
    }

    private func makeNotchPanel() -> NotchPanel {
        let panel = NotchPanel(
            onSelect: { [weak self] in
                self?.beginSelection()
            },
            onSubmitPrompt: { [weak self] prompt, takeScreenContext in
                self?.showChat(
                    with: prompt,
                    takeScreenContext: takeScreenContext
                )
            }
        )
        notchPanel = panel
        return panel
    }

    private func beginSelection() {
        let applicationToRestore = frontmostExternalApplication()

        Task { [weak self, weak applicationToRestore] in
            guard let self else { return }

            try? await Task<Never, Never>.sleep(for: .milliseconds(200))

            do {
                let sources = try SystemScreenContextCapture().prepareSelection()
                let controller = ScreenSelectionOverlayController(
                    sources: sources,
                    onSubmit: { [weak self, weak applicationToRestore] prompt, attachment in
                        guard let self else { return }
                        self.selectionController = nil
                        self.presentChat(
                            with: prompt,
                            screenContext: ScreenContextOutcome(
                                attachment: attachment,
                                notice: nil
                            ),
                            applicationToRestore: applicationToRestore
                        )
                    },
                    onCancel: { [weak self, weak applicationToRestore] in
                        self?.selectionController = nil
                        applicationToRestore?.activate()
                    },
                    onFailure: { [weak self] error in
                        self?.showSelectionFailure(error)
                    }
                )
                selectionController = controller
                controller.show()
            } catch {
                showSelectionFailure(error)
            }
        }
    }

    private func showChat(with prompt: String, takeScreenContext: Bool) {
        let applicationToRestore = frontmostExternalApplication()

        Task { [weak self, weak applicationToRestore] in
            guard let self else { return }
            let screenContext = await screenContextAcquisition.acquire(
                requested: takeScreenContext
            )
            presentChat(
                with: prompt,
                screenContext: screenContext,
                applicationToRestore: applicationToRestore
            )
        }
    }

    private func presentChat(
        with prompt: String,
        screenContext: ScreenContextOutcome,
        applicationToRestore: NSRunningApplication?
    ) {

        let controller = ChatWindowController(
            onOpenScreenRecordingSettings: {
                openScreenRecordingSettings()
            }
        )

        controller.onClose = { [weak self, weak controller, weak applicationToRestore] in
            guard let self, let controller else { return }
            self.chatWindowControllers.removeAll { $0 === controller }

            guard self.chatWindowControllers.isEmpty else { return }

            DispatchQueue.main.async {
                guard NSApp.keyWindow == nil else { return }
                applicationToRestore?.activate()
            }
        }
        chatWindowControllers.append(controller)
        controller.show(
            with: prompt,
            screenContext: screenContext
        )
    }

    private func frontmostExternalApplication() -> NSRunningApplication? {
        if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
           frontmostApplication.processIdentifier
                != ProcessInfo.processInfo.processIdentifier {
            previousExternalApplication = frontmostApplication
        }

        return previousExternalApplication
    }

    private func showSelectionFailure(_ error: Error) {
        selectionController = nil
        notchPanel?.invoke(notice: Notice(screenContextFailure: error))
    }
}
