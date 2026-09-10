import ApplicationServices
import Foundation
import Testing
@testable import Layer

@Test
@MainActor
func usesCopiedTextWhenAccessibilityCannotReadSelection() {
    let context = TextInsertionContext(
        element: nil,
        selectedText: nil,
        selectedRange: nil
    ).usingCopiedSelection("Browser editor selection")

    #expect(context.selectedText == "Browser editor selection")
}

@Test
@MainActor
func usingCopiedSelectionPreservesRestoreMetadata() {
    let range = CFRange(location: 3, length: 4)
    let context = TextInsertionContext(
        element: AXUIElementCreateSystemWide(),
        selectedText: nil,
        selectedRange: range
    ).usingCopiedSelection("copied")

    #expect(context.selectedText == "copied")
    #expect(context.element != nil)
    #expect(context.selectedRange?.location == 3)
    #expect(context.selectedRange?.length == 4)
}

@Test
func buildsInsertionPromptOnlyWhenTextIsSelected() {
    #expect(
        insertionPrompt(instruction: "Continue writing", selectedText: nil)
            == "Continue writing"
    )

    let prompt = insertionPrompt(
        instruction: "Improve this",
        selectedText: "Original sentence."
    )
    #expect(prompt.contains("User instruction:\nImprove this"))
    #expect(prompt.contains("Original selected text:"))
    #expect(prompt.contains("Original sentence."))
    #expect(
        prompt.hasSuffix("Return the complete updated version of the selected text.")
    )
}

@Test
func insertRequestIncludesScreenOnlyWhenPresentAndKeepsSelectionAsEditBoundary() {
    let attachment = ScreenAttachment(imageData: Data([3, 2, 1]))
    let withScreen = insertChatRequest(
        instruction: "Tighten this",
        inputs: InvocationInputs(
            modelContext: InvocationModelContext(
                selectedContent: "Original sentence.",
                screen: ScreenContextOutcome(attachment: attachment, notice: nil)
            ),
            interactionTarget: InvocationInteractionTarget()
        ),
        provider: ModelProviderConfiguration(
            kind: .openAI,
            apiKey: "secret",
            model: "test-model"
        )
    )
    let withoutScreen = insertChatRequest(
        instruction: "Tighten this",
        inputs: InvocationInputs(
            modelContext: InvocationModelContext(
                selectedContent: "Original sentence.",
                screen: .notRequested
            ),
            interactionTarget: InvocationInteractionTarget()
        ),
        provider: ModelProviderConfiguration(
            kind: .openAI,
            apiKey: "secret",
            model: "test-model"
        )
    )

    #expect(withScreen.prompt.contains("Original sentence."))
    #expect(withScreen.prompt.contains("User instruction:\nTighten this"))
    #expect(withScreen.screenAttachment?.imageData == attachment.imageData)
    #expect(withScreen.selectedContent == nil)
    #expect(withoutScreen.screenAttachment == nil)
    #expect(withoutScreen.prompt == withScreen.prompt)
}

@Test
func buildsPlainTextInsertContent() throws {
    let result = try InsertResult(
        responseText: #"{"kind":"text","text":"Revised sentence.","rows":[["ignored"]]}"#
    )

    #expect(result.kind == .text)
    #expect(result.string == "Revised sentence.")
    #expect(result.html == nil)
}

@Test
func buildsTableInsertContent() throws {
    let result = try InsertResult(
        responseText: """
            {
              "kind": "table",
              "text": "ignored",
              "rows": [
                ["Name", "DOB"],
                ["A & B\\nCo", "<date>\\t"]
              ]
            }
            """
    )

    #expect(result.string == "Name\tDOB\nA & B Co\t<date> ")
    #expect(
        result.html
            == "<table><tbody><tr><td>Name</td><td>DOB</td></tr>"
                + "<tr><td>A &amp; B Co</td><td>&lt;date&gt; </td></tr>"
                + "</tbody></table>"
    )
}

@Test
func rejectsMalformedTableInsertContent() {
    #expect(throws: ModelProviderClientError.self) {
        try InsertResult(
            responseText: #"{"kind":"table","text":"","rows":[["A"],["B","C"]]}"#
        )
    }
}
