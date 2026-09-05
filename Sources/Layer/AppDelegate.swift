import AppKit
import ApplicationServices
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchPanel: NotchPanel?
    private var selectionController: ScreenSelectionOverlayController?
    private var chatWindowControllers: [ChatWindowController] = []
    private var previousExternalApplication: NSRunningApplication?
    private var insertionContext: TextInsertionContext?
    private let screenContextAcquisition = ScreenContextAcquisition()
    private var invocationShortcutRecognizer = DoubleModifierPressRecognizer()
    private var selectionShortcut: GlobalSelectionShortcut?
    private var voiceShortcut: GlobalSelectionShortcut?
    private var localShortcutMonitor: Any?
    private var globalShortcutMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        InvocationShortcutPreferences.registerDefaults()
        SelectionShortcutPreferences.registerDefaults()
        VoiceShortcutPreferences.registerDefaults()
        let accessibilityOptions = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(accessibilityOptions)
        startInvocationShortcutMonitoring()
        selectionShortcut = GlobalSelectionShortcut(id: 1) { [weak self] in
            self?.beginSelection()
        }
        voiceShortcut = GlobalSelectionShortcut(id: 2) { [weak self] in
            self?.toggleVoice()
        }
        updateRegisteredShortcuts()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateRegisteredShortcuts),
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
        notchPanel?.stopVoice()
        NotificationCenter.default.removeObserver(self)
        selectionShortcut?.invalidate()
        voiceShortcut?.invalidate()
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
            let application = frontmostExternalApplication()
            let context = TextInsertionContext.capture()
            let panel = notchPanel ?? makeNotchPanel()

            guard context.selectedText == nil, let application else {
                insertionContext = context
                panel.invoke()
                return
            }

            Task { [weak self, weak application, weak panel] in
                guard let self, let application, let panel else { return }
                let copiedText = await TextInsertionContext.copiedSelection(
                    from: application
                )
                insertionContext = context.usingCopiedSelection(copiedText)
                panel.invoke()
            }
        }
    }

    @objc private func updateRegisteredShortcuts() {
        selectionShortcut?.register(
            keyCode: SelectionShortcutPreferences.keyCode,
            modifiers: SelectionShortcutPreferences.modifiers,
            enabled: SelectionShortcutPreferences.isEnabled
        )
        voiceShortcut?.register(
            keyCode: VoiceShortcutPreferences.keyCode,
            modifiers: VoiceShortcutPreferences.modifiers,
            enabled: VoiceShortcutPreferences.isEnabled
        )
    }

    private func toggleVoice() {
        let panel = notchPanel ?? makeNotchPanel()
        panel.toggleVoice()
    }

    private func makeNotchPanel() -> NotchPanel {
        let panel = NotchPanel(
            onSelect: { [weak self] in
                self?.beginSelection()
            },
            onSubmitPrompt: { [weak self] prompt, takeScreenContext, insertMode in
                if insertMode {
                    self?.insertAtCursor(with: prompt)
                } else {
                    self?.showChat(
                        with: prompt,
                        takeScreenContext: takeScreenContext
                    )
                }
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

    private func insertAtCursor(with prompt: String) {
        guard AXIsProcessTrusted() else {
            notchPanel?.invoke(
                notice: Notice(
                    message: "Grant Accessibility access to insert text.",
                    recovery: .accessibilitySettings
                )
            )
            return
        }

        guard let credential = StoredChatCredentialAdapter().loadCredential(),
              !credential.isEmpty else {
            notchPanel?.invoke(
                notice: Notice(
                    message: "Add an OpenAI API key in Settings before sending a message.",
                    recovery: .settings
                )
            )
            return
        }

        guard let applicationToRestore = frontmostExternalApplication() else {
            notchPanel?.invoke(
                notice: Notice(
                    message: "Open a text field in another app before using insert.",
                    recovery: nil
                )
            )
            return
        }
        notchPanel?.resignKey()
        NSApp.deactivate()
        applicationToRestore.activate(options: [.activateAllWindows])

        let context = insertionContext
        let request = ChatResponseRequest(
            prompt: insertionPrompt(
                instruction: prompt,
                selectedText: context?.selectedText
            ),
            credential: credential,
            instructions: """
                Edit the user's selected text according to their instruction. \
                Preserve all unaffected content and integrate additions in the \
                appropriate place. Use kind "table" when the result naturally \
                has rows and columns, including requests to add a row or \
                column; put the complete table matrix in rows and leave text \
                empty. Otherwise use kind "text", put the complete revised \
                text in text, and leave rows empty. Do not add introductions, \
                explanations, follow-up offers, quotation wrappers, Markdown \
                tables, or code fences.
                """,
            structuredOutput: true,
            continuationID: nil,
            screenAttachment: nil
        )

        Task { [weak self, applicationToRestore, context] in
            guard let self else { return }

            do {
                var responseText = ""
                for try await event in OpenAIClient().streamResponse(for: request) {
                    if case .textDelta(let delta) = event {
                        responseText += delta
                    }
                }
                let result = try InsertResult(responseText: responseText)
                await TextInserter().insert(
                    result,
                    into: applicationToRestore,
                    restoring: context
                )
                notchPanel?.finishGenerating()
            } catch {
                notchPanel?.invoke(
                    notice: Notice(
                        message: error.localizedDescription,
                        recovery: .settings
                    )
                )
            }
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

func insertionPrompt(instruction: String, selectedText: String?) -> String {
    guard let selectedText, !selectedText.isEmpty else { return instruction }
    return """
        User instruction:
        \(instruction)

        Original selected text:
        --- BEGIN SELECTED TEXT ---
        \(selectedText)
        --- END SELECTED TEXT ---

        Return the complete updated version of the selected text.
        """
}
