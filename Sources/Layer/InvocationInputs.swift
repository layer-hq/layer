import AppKit
import ApplicationServices
import Foundation

struct InvocationModelContext: Sendable {
    var selectedContent: String?
    var screen: ScreenContextOutcome

    static let empty = InvocationModelContext(
        selectedContent: nil,
        screen: .notRequested
    )
}

struct InvocationInteractionTarget {
    var application: NSRunningApplication?
    var displayID: CGDirectDisplayID?
    var element: AXUIElement?
    var selectedRange: CFRange?
}

struct InvocationInputs {
    var modelContext: InvocationModelContext
    var interactionTarget: InvocationInteractionTarget
}

@MainActor
final class InvocationInputsCollector {
    private var application: NSRunningApplication?
    private var displayID: CGDirectDisplayID?
    private var selection: TextInsertionContext?
    private var cachedScreen: ScreenContextOutcome?
    private var prepared = false
    private var phase1Task: Task<Void, Never>?
    private var phase1Generation = 0

    private let captureSelection: () -> TextInsertionContext
    private let copySelection: (NSRunningApplication) async -> String?

    init(
        captureSelection: @escaping () -> TextInsertionContext = {
            TextInsertionContext.capture()
        },
        copySelection: @escaping (NSRunningApplication) async -> String? = {
            await TextInsertionContext.copiedSelection(from: $0)
        }
    ) {
        self.captureSelection = captureSelection
        self.copySelection = copySelection
    }

    var applicationToRestore: NSRunningApplication? { application }

    func prepareForFocusSteal(
        application: NSRunningApplication?,
        displayID: CGDirectDisplayID?,
        includeSelectedContent: Bool
    ) async {
        if let phase1Task {
            await phase1Task.value
            return
        }
        guard !prepared else { return }

        let generation = phase1Generation
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.capturePhase1(
                application: application,
                displayID: displayID,
                includeSelectedContent: includeSelectedContent,
                generation: generation
            )
        }
        phase1Task = task
        await task.value
        if phase1Generation == generation {
            phase1Task = nil
        }
    }

    private func capturePhase1(
        application: NSRunningApplication?,
        displayID: CGDirectDisplayID?,
        includeSelectedContent: Bool,
        generation: Int
    ) async {
        guard generation == phase1Generation else { return }

        var context: TextInsertionContext?
        if includeSelectedContent {
            context = captureSelection()
            if context?.selectedText == nil, let application {
                context = context?.usingCopiedSelection(await copySelection(application))
            }
        }

        guard generation == phase1Generation else { return }
        self.application = application
        self.displayID = displayID
        selection = context
        prepared = true
    }

    func takeCurrent(
        screenContext: ScreenContextOutcome = .notRequested
    ) -> InvocationInputs {
        let inputs = InvocationInputs(
            modelContext: InvocationModelContext(
                selectedContent: selection?.selectedText,
                screen: screenContext
            ),
            interactionTarget: InvocationInteractionTarget(
                application: application,
                displayID: displayID,
                element: selection?.element,
                selectedRange: selection?.selectedRange
            )
        )
        clear()
        return inputs
    }

    func takeCurrent(
        capturingScreen requested: Bool,
        using acquisition: ScreenContextAcquisition
    ) async -> InvocationInputs {
        if let phase1Task {
            await phase1Task.value
        }
        let displayID = self.displayID
        let cached = requested ? cachedScreen : nil
        var inputs = takeCurrent()
        if let cached {
            inputs.modelContext.screen = cached
        } else {
            inputs.modelContext.screen = await acquisition.acquire(
                requested: requested,
                displayID: displayID
            )
        }
        return inputs
    }

    func takeCurrent(
        capturing targets: [ScreenContextTarget],
        using acquisition: ScreenContextAcquisition
    ) async -> InvocationInputs {
        if let phase1Task {
            await phase1Task.value
        }
        let displayID = self.displayID
        let cached = targets.isEmpty ? nil : cachedScreen
        var inputs = takeCurrent()
        if let cached {
            inputs.modelContext.screen = cached
        } else {
            inputs.modelContext.screen = await acquisition.acquire(
                targets: targets,
                displayID: displayID
            )
        }
        return inputs
    }

    func restore(_ inputs: InvocationInputs) {
        application = inputs.interactionTarget.application
        displayID = inputs.interactionTarget.displayID
        selection = TextInsertionContext(
            element: inputs.interactionTarget.element,
            selectedText: inputs.modelContext.selectedContent,
            selectedRange: inputs.interactionTarget.selectedRange
        )
        cachedScreen = inputs.modelContext.screen
        prepared = true
    }

    func clear() {
        phase1Generation += 1
        phase1Task = nil
        application = nil
        displayID = nil
        selection = nil
        cachedScreen = nil
        prepared = false
    }
}

enum ModelContextPayload {
    nonisolated static func selectedTextFence(_ text: String) -> String {
        """
        --- BEGIN SELECTED TEXT ---
        \(text)
        --- END SELECTED TEXT ---
        """
    }

    nonisolated static func selectedContentBlock(_ text: String) -> String {
        """
        Context from the user's current selection:
        \(selectedTextFence(text))
        """
    }

    nonisolated static func chatUserText(
        prompt: String,
        selectedContent: String?
    ) -> String {
        guard let selectedContent, !selectedContent.isEmpty else { return prompt }
        return prompt + "\n\n" + selectedContentBlock(selectedContent)
    }

    nonisolated static func chatInput(
        prompt: String,
        selectedContent: String?,
        screenAttachment: ScreenAttachment?,
        attachments: [ChatAttachment] = []
    ) -> Any {
        chatInput(
            prompt: prompt,
            selectedContent: selectedContent,
            screenAttachments: screenAttachment.map { [$0] } ?? [],
            attachments: attachments
        )
    }

    nonisolated static func chatInput(
        prompt: String,
        selectedContent: String?,
        screenAttachments: [ScreenAttachment],
        attachments: [ChatAttachment] = []
    ) -> Any {
        let text = chatUserText(prompt: prompt, selectedContent: selectedContent)
        guard !screenAttachments.isEmpty || !attachments.isEmpty else { return text }

        var content: [[String: Any]] = [
            [
                "type": "input_text",
                "text": text
            ]
        ]
        content.append(contentsOf: screenAttachments.map { screenAttachment in
            [
                "type": "input_image",
                "image_url": screenAttachment.dataURL,
                "detail": "auto"
            ]
        })
        for attachment in attachments {
            switch attachment.kind {
            case .image:
                content.append([
                    "type": "input_image",
                    "image_url": attachment.dataURL,
                    "detail": "auto"
                ])
            case .document:
                content.append([
                    "type": "input_file",
                    "filename": attachment.name,
                    "file_data": attachment.dataURL
                ])
            }
        }

        return [
            [
                "role": "user",
                "content": content
            ]
        ]
    }

    nonisolated static func fileContext(
        from attachments: [ChatAttachment]
    ) -> String? {
        let blocks = attachments.compactMap { attachment -> String? in
            guard attachment.kind == .document,
                  let text = attachment.extractedText,
                  !text.isEmpty else { return nil }
            let safeName = attachment.name.replacingOccurrences(of: "\n", with: " ")
            let truncation = attachment.textWasTruncated
                ? "\n[Content truncated after \(ChatAttachmentLimits.maximumExtractedCharacters) characters.]"
                : ""
            return """
                --- BEGIN ATTACHED FILE: \(safeName) ---
                \(text)\(truncation)
                --- END ATTACHED FILE: \(safeName) ---
                """
        }
        guard !blocks.isEmpty else { return nil }
        return "Context from the user's attached files:\n" + blocks.joined(separator: "\n\n")
    }

    nonisolated static func voiceConversationItem(
        selectedContent: String?,
        screenAttachment: ScreenAttachment?
    ) -> [String: Any]? {
        voiceConversationItem(
            selectedContent: selectedContent,
            screenAttachments: screenAttachment.map { [$0] } ?? []
        )
    }

    nonisolated static func voiceConversationItem(
        selectedContent: String?,
        screenAttachments: [ScreenAttachment]
    ) -> [String: Any]? {
        var content: [[String: Any]] = []
        if let selectedContent, !selectedContent.isEmpty {
            content.append([
                "type": "input_text",
                "text": selectedContentBlock(selectedContent)
            ])
        }
        if !screenAttachments.isEmpty {
            if content.isEmpty {
                content.append([
                    "type": "input_text",
                    "text": "The attached images are the user's selected Screen context."
                ])
            }
            content.append(contentsOf: screenAttachments.map { screenAttachment in
                [
                    "type": "input_image",
                    "image_url": screenAttachment.dataURL,
                    "detail": "high"
                ]
            })
        }
        guard !content.isEmpty else { return nil }

        return [
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": content
            ]
        ]
    }
}
