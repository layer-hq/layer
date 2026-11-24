import AppKit
import Foundation
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import Layer

@Suite
struct FileAttachmentTests {
    @Test @MainActor
    func longPastedTextBecomesATextAttachmentWhileShortTextStaysInline() async throws {
        let drafts = DraftAttachments()
        let shortText = String(
            repeating: "s",
            count: ChatAttachmentLimits.longTextPasteCharacters - 1
        )
        let longText = String(
            repeating: "L",
            count: ChatAttachmentLimits.longTextPasteCharacters
        )

        #expect(!drafts.acceptPastedText(shortText))
        #expect(drafts.attachments.isEmpty)
        #expect(drafts.acceptPastedText(longText))
        for _ in 0..<100 where drafts.attachments.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }

        let attachment = try #require(drafts.attachments.first)
        #expect(attachment.kind == .document)
        #expect(attachment.mediaType == "text/plain")
        #expect(attachment.name.hasPrefix("Pasted Text "))
        #expect(attachment.name.hasSuffix(".txt"))
        #expect(attachment.data == Data(longText.utf8))
        #expect(attachment.sourceURL == nil)
    }

    @Test @MainActor
    func pastedFileURLBecomesAnOriginalFileAttachment() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Pasted notes \(UUID().uuidString).txt")
        let contents = Data("clipboard file context".utf8)
        try contents.write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let provider = NSItemProvider(
            item: sourceURL as NSURL,
            typeIdentifier: UTType.fileURL.identifier
        )
        let drafts = DraftAttachments()

        drafts.acceptPastedItems([provider])
        for _ in 0..<100 where drafts.attachments.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }

        let attachment = try #require(drafts.attachments.first)
        #expect(attachment.name == sourceURL.lastPathComponent)
        #expect(attachment.data == contents)
        #expect(attachment.kind == .document)
        #expect(attachment.sourceURL == sourceURL)
    }

    @Test @MainActor
    func pastedImageBecomesANamedAttachment() async throws {
        let image = NSImage(size: NSSize(width: 20, height: 20))
        image.lockFocus()
        NSColor.systemPurple.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 20, height: 20)).fill()
        image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let drafts = DraftAttachments()

        await drafts.addPastedImage(data: png, typeIdentifier: UTType.png.identifier)

        let attachment = try #require(drafts.attachments.first)
        #expect(attachment.kind == .image)
        #expect(attachment.mediaType == "image/png")
        #expect(attachment.name.hasPrefix("Pasted Image "))
        #expect(attachment.name.hasSuffix(".png"))
        #expect(attachment.sourceURL == nil)
    }

    @Test
    func preservesSourceURLForFinderAccess() throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("layer-attachment-\(UUID().uuidString).txt")
        try Data("context".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let attachment = try ChatAttachmentLoader.load(from: sourceURL)

        #expect(attachment.sourceURL == sourceURL)
    }

    @Test
    func loadsPDFAsOriginalDocumentInsteadOfRasterizedPreview() throws {
        let image = NSImage(size: NSSize(width: 40, height: 40))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 40, height: 40)).fill()
        image.unlockFocus()
        let page = try #require(PDFPage(image: image))
        let pdf = PDFDocument()
        pdf.insert(page, at: 0)
        let pdfData = try #require(pdf.dataRepresentation())

        let attachment = try ChatAttachmentLoader.load(
            data: pdfData,
            name: "original.pdf",
            contentType: .pdf
        )

        #expect(attachment.kind == .document)
        #expect(attachment.mediaType == "application/pdf")
        #expect(attachment.name == "original.pdf")
        #expect(attachment.data == pdfData)
        #expect(attachment.extractedText == nil)
    }

    @Test
    func loadsTextFileForPortableModelContext() throws {
        let attachment = try ChatAttachmentLoader.load(
            data: Data("alpha,beta\n1,2".utf8),
            name: "notes.csv",
            contentType: .commaSeparatedText
        )

        #expect(attachment.kind == .document)
        #expect(attachment.extractedText == "alpha,beta\n1,2")
        #expect(attachment.mediaType == "text/csv")
        #expect(!attachment.textWasTruncated)
    }

    @Test
    func rejectsUnsupportedBinaryData() {
        #expect(throws: ChatAttachmentError.self) {
            try ChatAttachmentLoader.load(
                data: Data([0, 1, 2, 3, 0, 4]),
                name: "archive.bin",
                contentType: .data
            )
        }
    }

    @Test
    func truncatesLargeTextBeforeAddingItToChatCompletionContext() throws {
        let text = String(
            repeating: "x",
            count: ChatAttachmentLimits.maximumExtractedCharacters + 1
        )
        let attachment = try ChatAttachmentLoader.load(
            data: Data(text.utf8),
            name: "large.txt",
            contentType: .plainText
        )

        #expect(attachment.extractedText?.count == ChatAttachmentLimits.maximumExtractedCharacters)
        #expect(attachment.textWasTruncated)
        #expect(ModelContextPayload.fileContext(from: [attachment])?.contains("truncated") == true)
    }
}
