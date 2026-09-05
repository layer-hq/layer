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
    #expect(throws: OpenAIClientError.self) {
        try InsertResult(
            responseText: #"{"kind":"table","text":"","rows":[["A"],["B","C"]]}"#
        )
    }
}
