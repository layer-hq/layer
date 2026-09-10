import AppKit
import ApplicationServices
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchPanel: NotchPanel?
    private var selectionController: ScreenSelectionOverlayController?
    private var chatWindowControllers: [ChatWindowController] = []
    private var previousExternalApplication: NSRunningApplication?
    private let inputsCollector = InvocationInputsCollector()
    private let screenContextAcquisition = ScreenContextAcquisition()
    private var invocationShortcutRecognizer = DoubleModifierPressRecognizer()
    private var selectionShortcut: GlobalSelectionShortcut?
    private var dictationShortcut: GlobalSelectionShortcut?
    private var localShortcutMonitor: Any?
    private var globalShortcutMonitor: Any?
    private var insertionTask: Task<Void, Never>?
    private var insertionGeneration = 0
    private var insertionInputs: InvocationInputs?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        InvocationShortcutPreferences.registerDefaults()
        SelectionShortcutPreferences.registerDefaults()
        DictationShortcutPreferences.registerDefaults()
        let accessibilityOptions = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(accessibilityOptions)
        startInvocationShortcutMonitoring()
        selectionShortcut = GlobalSelectionShortcut(id: 1) { [weak self] in
            self?.beginSelection()
        }
        dictationShortcut = GlobalSelectionShortcut(
            id: 2,
            action: { [weak self] in self?.beginDictation() },
            releaseAction: { [weak self] in self?.endDictation() }
        )
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
        cancelInsertion()
        notchPanel?.cancelDictation()
        notchPanel?.stopVoice()
        NotificationCenter.default.removeObserver(self)
        selectionShortcut?.invalidate()
        dictationShortcut?.invalidate()
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

    @objc private func updateRegisteredShortcuts() {
        selectionShortcut?.register(
            keyCode: SelectionShortcutPreferences.keyCode,
            modifiers: SelectionShortcutPreferences.modifiers,
            enabled: SelectionShortcutPreferences.isEnabled
        )
        dictationShortcut?.register(
            keyCode: DictationShortcutPreferences.keyCode,
            modifiers: DictationShortcutPreferences.modifiers,
            enabled: DictationShortcutPreferences.isEnabled
        )
    }

    private func beginDictation() {
        let panel = notchPanel ?? makeNotchPanel()
        panel.beginDictation()
    }

    private func endDictation() {
        notchPanel?.endDictation()
    }

    private func makeNotchPanel() -> NotchPanel {
        let panel = NotchPanel(
            collector: inputsCollector,
            screenContextAcquisition: screenContextAcquisition,
            frontmostExternalApplication: { [weak self] in
                self?.frontmostExternalApplication()
            },
            onSelect: { [weak self] in
                self?.beginSelection()
            },
            onSubmitPrompt: { [weak self] prompt, insertMode in
                if insertMode {
                    self?.insertAtCursor(with: prompt)
                } else {
                    self?.showChat(with: prompt)
                }
            },
            onCancelGeneration: { [weak self] in
                self?.cancelInsertion()
            }
        )
        notchPanel = panel
        return panel
    }

    private func beginSelection() {
        let applicationToRestore = inputsCollector.applicationToRestore
            ?? frontmostExternalApplication()
        inputsCollector.clear()

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
                            inputs: InvocationInputs(
                                modelContext: InvocationModelContext(
                                    selectedContent: nil,
                                    screen: ScreenContextOutcome(
                                        attachment: attachment,
                                        notice: nil
                                    )
                                ),
                                interactionTarget: InvocationInteractionTarget(
                                    application: applicationToRestore
                                )
                            )
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

    private func showChat(with prompt: String) {
        guard StoredModelProviderAdapter().loadActiveProvider() != nil else {
            notchPanel?.invoke(
                notice: Notice(
                    message: "Add and select a model provider in Settings before sending a message.",
                    recovery: .settings
                )
            )
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let inputs = await snapshotInputs()
            presentChat(with: prompt, inputs: inputs)
        }
    }

    private func snapshotInputs() async -> InvocationInputs {
        await inputsCollector.takeCurrent(
            capturingScreen: UserDefaults.standard.bool(forKey: "takeScreenContext"),
            using: screenContextAcquisition
        )
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

        guard let provider = StoredModelProviderAdapter().loadActiveProvider() else {
            notchPanel?.invoke(
                notice: Notice(
                    message: "Add and select a model provider in Settings before sending a message.",
                    recovery: .settings
                )
            )
            return
        }

        guard let applicationToRestore = inputsCollector.applicationToRestore
            ?? frontmostExternalApplication() else {
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

        insertionGeneration += 1
        let generation = insertionGeneration
        insertionTask?.cancel()
        insertionTask = Task { [weak self, applicationToRestore] in
            guard let self else { return }
            defer {
                if insertionGeneration == generation {
                    insertionTask = nil
                }
            }
            let inputs = await snapshotInputs()
            insertionInputs = inputs
            if Task.isCancelled {
                revertInsertion(inputs, generation: generation)
                return
            }
            if let notice = inputs.modelContext.screen.notice {
                notchPanel?.showNotice(notice)
            }
            let context = TextInsertionContext(
                element: inputs.interactionTarget.element,
                selectedText: inputs.modelContext.selectedContent,
                selectedRange: inputs.interactionTarget.selectedRange
            )
            let request = insertChatRequest(
                instruction: prompt,
                inputs: inputs,
                provider: provider
            )

            do {
                var responseText = ""
                for try await event in ModelProviderClient().streamResponse(for: request) {
                    if case .textDelta(let delta) = event {
                        responseText += delta
                    }
                }
                try Task.checkCancellation()
                let result = try InsertResult(responseText: responseText)
                await TextInserter().insert(
                    result,
                    into: applicationToRestore,
                    restoring: context
                )
                guard insertionGeneration == generation else { return }
                insertionInputs = nil
                notchPanel?.finishGenerating()
            } catch is CancellationError {
                revertInsertion(inputs, generation: generation)
            } catch {
                guard !Task.isCancelled else {
                    revertInsertion(inputs, generation: generation)
                    return
                }
                notchPanel?.invoke(
                    notice: Notice(
                        message: error.localizedDescription,
                        recovery: .settings
                    )
                )
            }
        }
    }

    private func cancelInsertion() {
        insertionTask?.cancel()
        if let insertionInputs {
            inputsCollector.restore(insertionInputs)
        }
        insertionGeneration += 1
    }

    private func revertInsertion(_ inputs: InvocationInputs, generation: Int) {
        guard insertionGeneration == generation else { return }
        inputsCollector.restore(inputs)
    }

    private func presentChat(
        with prompt: String,
        inputs: InvocationInputs
    ) {
        let applicationToRestore = inputs.interactionTarget.application

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
            modelContext: inputs.modelContext
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
        \(ModelContextPayload.selectedTextFence(selectedText))

        Return the complete updated version of the selected text.
        """
}

func insertChatRequest(
    instruction: String,
    inputs: InvocationInputs,
    provider: ModelProviderConfiguration
) -> ChatResponseRequest {
    ChatResponseRequest(
        prompt: insertionPrompt(
            instruction: instruction,
            selectedText: inputs.modelContext.selectedContent
        ),
        provider: provider,
        instructions: """
            Edit the user's selected text according to their instruction. \
            Preserve all unaffected content and integrate additions in the \
            appropriate place. If an image is attached, use it only as \
            contextual evidence; do not transcribe it and do not change \
            text that is not part of the selection. Use kind "table" when \
            the result naturally has rows and columns, including requests \
            to add a row or column; put the complete table matrix in rows \
            and leave text empty. Otherwise use kind "text", put the \
            complete revised text in text, and leave rows empty. Do not \
            add introductions, explanations, follow-up offers, quotation \
            wrappers, Markdown tables, or code fences.
            """,
        structuredOutput: true,
        continuationID: nil,
        screenAttachment: inputs.modelContext.screen.attachment
    )
}
