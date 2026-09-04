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
