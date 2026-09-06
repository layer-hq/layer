import AppKit
import Foundation
import Testing
@testable import Layer

@Suite
@MainActor
struct InvocationInputsTests {
    @Test
    func skipsSelectionCaptureWhenOptedOut() async {
        var captured = 0
        var copied = 0
        let collector = InvocationInputsCollector(
            captureSelection: {
                captured += 1
                return TextInsertionContext(
                    element: nil,
                    selectedText: "secret",
                    selectedRange: nil
                )
            },
            copySelection: { _ in
                copied += 1
                return "copied"
            }
        )

        await collector.prepareForFocusSteal(
            application: NSRunningApplication.current,
            displayID: 7,
            includeSelectedContent: false
        )
        let inputs = collector.takeCurrent()

        #expect(inputs.modelContext.selectedContent == nil)
        #expect(inputs.interactionTarget.displayID == 7)
        #expect(captured == 0)
        #expect(copied == 0)
    }

    @Test
    func usesAccessibilityTextWithoutClipboardFallback() async {
        var copied = 0
        let collector = InvocationInputsCollector(
            captureSelection: {
                TextInsertionContext(
                    element: nil,
                    selectedText: "from accessibility",
                    selectedRange: nil
                )
            },
            copySelection: { _ in
                copied += 1
                return "from clipboard"
            }
        )

        await collector.prepareForFocusSteal(
            application: NSRunningApplication.current,
            displayID: 1,
            includeSelectedContent: true
        )

        #expect(
            collector.takeCurrent().modelContext.selectedContent == "from accessibility"
        )
        #expect(copied == 0)
    }

    @Test
    func copiesSelectionOnceWhenAccessibilityHasNoText() async {
        var copied = 0
        let collector = InvocationInputsCollector(
            captureSelection: {
                TextInsertionContext(
                    element: nil,
                    selectedText: nil,
                    selectedRange: nil
                )
            },
            copySelection: { _ in
                copied += 1
                return "from clipboard"
            }
        )

        await collector.prepareForFocusSteal(
            application: NSRunningApplication.current,
            displayID: 1,
            includeSelectedContent: true
        )
        await collector.prepareForFocusSteal(
            application: NSRunningApplication.current,
            displayID: 2,
            includeSelectedContent: true
        )

        #expect(copied == 1)
        #expect(collector.takeCurrent().modelContext.selectedContent == "from clipboard")
        #expect(copied == 1)
    }

    @Test
    func takeCurrentReturnsImmutableSnapshotAndClearsPending() async {
        let collector = InvocationInputsCollector(
            captureSelection: {
                TextInsertionContext(
                    element: nil,
                    selectedText: "pending",
                    selectedRange: nil
                )
            },
            copySelection: { _ in nil }
        )
        let attachment = ScreenAttachment(imageData: Data([9]))
        await collector.prepareForFocusSteal(
            application: NSRunningApplication.current,
            displayID: 3,
            includeSelectedContent: true
        )

        let first = collector.takeCurrent(
            screenContext: ScreenContextOutcome(attachment: attachment, notice: nil)
        )
        let second = collector.takeCurrent()

        #expect(first.modelContext.selectedContent == "pending")
        #expect(first.modelContext.screen.attachment?.imageData == attachment.imageData)
        #expect(first.interactionTarget.displayID == 3)
        #expect(second.modelContext.selectedContent == nil)
        #expect(second.modelContext.screen == .notRequested)
        #expect(second.interactionTarget.application == nil)
    }

    @Test
    func selectClearsPendingModelInputsAndKeepsCropOnlyContext() async {
        let collector = InvocationInputsCollector(
            captureSelection: {
                TextInsertionContext(
                    element: nil,
                    selectedText: "should not reach chat",
                    selectedRange: nil
                )
            },
            copySelection: { _ in nil }
        )
        await collector.prepareForFocusSteal(
            application: NSRunningApplication.current,
            displayID: 4,
            includeSelectedContent: true
        )
        let application = collector.applicationToRestore
        collector.clear()
        let crop = ScreenAttachment(imageData: Data([1, 2]))
        let inputs = InvocationInputs(
            modelContext: InvocationModelContext(
                selectedContent: nil,
                screen: ScreenContextOutcome(attachment: crop, notice: nil)
            ),
            interactionTarget: InvocationInteractionTarget(application: application)
        )

        #expect(collector.takeCurrent().modelContext.selectedContent == nil)
        #expect(inputs.modelContext.selectedContent == nil)
        #expect(inputs.modelContext.screen.attachment?.imageData == crop.imageData)
        #expect(inputs.interactionTarget.application != nil)
        #expect(inputs.interactionTarget.displayID == nil)
    }

    @Test
    func takeCurrentFreezesPendingBeforeScreenCapture() async {
        let collector = InvocationInputsCollector(
            captureSelection: {
                TextInsertionContext(
                    element: nil,
                    selectedText: "keep me",
                    selectedRange: nil
                )
            },
            copySelection: { _ in nil }
        )
        await collector.prepareForFocusSteal(
            application: NSRunningApplication.current,
            displayID: 8,
            includeSelectedContent: true
        )
        let capture = ScreenContextClearingStub(collector: collector)
        let acquisition = ScreenContextAcquisition(capture: capture)

        let inputs = await collector.takeCurrent(
            capturingScreen: true,
            using: acquisition
        )

        #expect(inputs.modelContext.selectedContent == "keep me")
        #expect(inputs.interactionTarget.displayID == 8)
        #expect(inputs.modelContext.screen.attachment?.imageData == Data([1]))
        #expect(capture.clearedDuringCapture)
    }

    @Test
    func takeCurrentAwaitsInFlightClipboardCapture() async {
        let collector = InvocationInputsCollector(
            captureSelection: {
                TextInsertionContext(
                    element: nil,
                    selectedText: nil,
                    selectedRange: nil
                )
            },
            copySelection: { _ in
                try? await Task.sleep(for: .milliseconds(80))
                return "from clipboard"
            }
        )
        async let prepared: Void = collector.prepareForFocusSteal(
            application: NSRunningApplication.current,
            displayID: 1,
            includeSelectedContent: true
        )
        try? await Task.sleep(for: .milliseconds(20))
        let capture = ScreenContextCaptureStub(
            result: .success(ScreenAttachment(imageData: Data([1])))
        )
        let inputs = await collector.takeCurrent(
            capturingScreen: false,
            using: ScreenContextAcquisition(capture: capture)
        )
        await prepared

        #expect(inputs.modelContext.selectedContent == "from clipboard")
    }

    @Test
    func clearDuringClipboardCaptureDoesNotWriteStaleTarget() async {
        let collector = InvocationInputsCollector(
            captureSelection: {
                TextInsertionContext(
                    element: nil,
                    selectedText: nil,
                    selectedRange: nil
                )
            },
            copySelection: { _ in
                try? await Task.sleep(for: .milliseconds(80))
                return "late copy"
            }
        )
        async let prepared: Void = collector.prepareForFocusSteal(
            application: NSRunningApplication.current,
            displayID: 99,
            includeSelectedContent: true
        )
        try? await Task.sleep(for: .milliseconds(20))
        collector.clear()
        await prepared

        let inputs = collector.takeCurrent()
        #expect(inputs.modelContext.selectedContent == nil)
        #expect(inputs.interactionTarget.displayID == nil)
        #expect(inputs.interactionTarget.application == nil)
    }
}

@MainActor
private final class ScreenContextCaptureStub: ScreenContextCapturing {
    private let result: Result<ScreenAttachment, Error>

    init(result: Result<ScreenAttachment, Error>) {
        self.result = result
    }

    func captureDisplay(id: CGDirectDisplayID?) async throws -> ScreenAttachment {
        try result.get()
    }
}

@MainActor
private final class ScreenContextClearingStub: ScreenContextCapturing {
    private let collector: InvocationInputsCollector
    private(set) var clearedDuringCapture = false

    init(collector: InvocationInputsCollector) {
        self.collector = collector
    }

    func captureDisplay(id: CGDirectDisplayID?) async throws -> ScreenAttachment {
        collector.clear()
        clearedDuringCapture = true
        return ScreenAttachment(imageData: Data([1]))
    }
}

@Suite
struct ModelContextEncodingTests {
    @Test
    func chatInputEncodesOnlyModelContext() throws {
        let attachment = ScreenAttachment(imageData: Data([1, 2, 3]))
        let input = ModelContextPayload.chatInput(
            prompt: "What is this?",
            selectedContent: "Selected line",
            screenAttachment: attachment
        )
        let json = String(
            data: try JSONSerialization.data(withJSONObject: ["input": input]),
            encoding: .utf8
        )

        #expect(json?.contains("What is this?") == true)
        #expect(json?.contains("Selected line") == true)
        #expect(json?.contains("input_image") == true)
        #expect(json?.contains("AQID") == true)
        #expect(json?.contains("interactionTarget") == false)
        #expect(json?.contains("displayID") == false)
        #expect(json?.contains("AXSelectedText") == false)
    }

    @Test
    func voiceOpeningSendsContextItemWithoutGreeting() throws {
        let attachment = ScreenAttachment(imageData: Data([7, 8]))
        let events = VoiceRealtimeOpening.contextEvents(
            from: InvocationModelContext(
                selectedContent: "Voice selection",
                screen: ScreenContextOutcome(attachment: attachment, notice: nil)
            )
        )

        #expect(events.count == 1)
        #expect(events[0]["type"] as? String == "conversation.item.create")
        #expect(events[0]["event_id"] as? String == VoiceRealtimeOpening.contextItemID)
        #expect(!events.contains { $0["type"] as? String == "response.create" })

        let item = try #require(events[0]["item"] as? [String: Any])
        #expect(item["id"] as? String == VoiceRealtimeOpening.contextItemID)
        let content = try #require(item["content"] as? [[String: Any]])
        #expect(content.contains { $0["type"] as? String == "input_text" })
        #expect(content.contains { $0["type"] as? String == "input_image" })
        #expect(
            content.contains {
                ($0["text"] as? String)?.contains("Voice selection") == true
            }
        )
        #expect(
            content.contains { $0["image_url"] as? String == attachment.dataURL }
        )
    }
}
