import AppKit
import Foundation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct ChatAttachment: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case image
        case document
    }

    let id: UUID
    let name: String
    let mediaType: String
    let data: Data
    let kind: Kind
    let sourceURL: URL?
    let extractedText: String?
    let textWasTruncated: Bool

    init(
        id: UUID = UUID(),
        name: String,
        mediaType: String,
        data: Data,
        kind: Kind,
        sourceURL: URL? = nil,
        extractedText: String? = nil,
        textWasTruncated: Bool = false
    ) {
        self.id = id
        self.name = name
        self.mediaType = mediaType
        self.data = data
        self.kind = kind
        self.sourceURL = sourceURL
        self.extractedText = extractedText
        self.textWasTruncated = textWasTruncated
    }

    var dataURL: String {
        "data:\(mediaType);base64,\(data.base64EncodedString())"
    }

    var byteCountLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }
}

enum ChatAttachmentLimits {
    static let maximumCount = 5
    static let maximumFileBytes = 10 * 1_024 * 1_024
    static let maximumTotalBytes = 25 * 1_024 * 1_024
    static let maximumExtractedCharacters = 250_000
    static let longTextPasteCharacters = 10_000
}

enum ChatAttachmentError: LocalizedError {
    case tooManyFiles
    case fileTooLarge(String)
    case totalTooLarge
    case unreadable(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .tooManyFiles:
            return "You can attach up to \(ChatAttachmentLimits.maximumCount) files."
        case .fileTooLarge(let name):
            return "\(name) is larger than the 10 MB per-file limit."
        case .totalTooLarge:
            return "Attachments can use up to 25 MB total."
        case .unreadable(let name):
            return "Layer could not read \(name)."
        case .unsupported(let name):
            return "\(name) is not supported. Attach an image, PDF, or text-based file."
        }
    }
}

enum ChatAttachmentLoader {
    static func load(from url: URL) throws -> ChatAttachment {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        let name = url.lastPathComponent.isEmpty ? "Attachment" : url.lastPathComponent
        guard values?.isRegularFile != false else {
            throw ChatAttachmentError.unsupported(name)
        }
        if let size = values?.fileSize, size > ChatAttachmentLimits.maximumFileBytes {
            throw ChatAttachmentError.fileTooLarge(name)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw ChatAttachmentError.unreadable(name)
        }
        let type = UTType(filenameExtension: url.pathExtension)
        return try load(data: data, name: name, contentType: type, sourceURL: url)
    }

    static func load(
        data: Data,
        name: String,
        contentType: UTType?,
        sourceURL: URL? = nil
    ) throws -> ChatAttachment {
        guard data.count <= ChatAttachmentLimits.maximumFileBytes else {
            throw ChatAttachmentError.fileTooLarge(name)
        }

        if contentType?.conforms(to: .pdf) == true
            || name.lowercased().hasSuffix(".pdf") {
            guard let document = PDFDocument(data: data) else {
                throw ChatAttachmentError.unreadable(name)
            }
            let text = document.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            let extracted = text.flatMap { text in
                text.isEmpty ? nil : truncate(text)
            }
            return ChatAttachment(
                name: name,
                mediaType: "application/pdf",
                data: data,
                kind: .document,
                sourceURL: sourceURL,
                extractedText: extracted?.text,
                textWasTruncated: extracted?.wasTruncated ?? false
            )
        }

        if contentType?.conforms(to: .image) == true
            || (contentType == nil && NSImage(data: data) != nil) {
            return try imageAttachment(
                data: data,
                name: name,
                contentType: contentType,
                sourceURL: sourceURL
            )
        }

        guard contentType?.conforms(to: .text) == true || looksLikeText(data),
              let text = decodeText(data) else {
            throw ChatAttachmentError.unsupported(name)
        }
        let extracted = truncate(text)
        return ChatAttachment(
            name: name,
            mediaType: contentType?.preferredMIMEType ?? "text/plain",
            data: data,
            kind: .document,
            sourceURL: sourceURL,
            extractedText: extracted.text,
            textWasTruncated: extracted.wasTruncated
        )
    }

    private static func imageAttachment(
        data: Data,
        name: String,
        contentType: UTType?,
        sourceURL: URL?
    ) throws -> ChatAttachment {
        let originalMediaType = contentType?.preferredMIMEType
        let supportedMediaTypes = ["image/jpeg", "image/png", "image/gif", "image/webp"]
        if let originalMediaType, supportedMediaTypes.contains(originalMediaType) {
            return ChatAttachment(
                name: name,
                mediaType: originalMediaType,
                data: data,
                kind: .image,
                sourceURL: sourceURL
            )
        }

        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(
                using: .jpeg,
                properties: [.compressionFactor: 0.85]
              ) else {
            throw ChatAttachmentError.unreadable(name)
        }
        guard jpeg.count <= ChatAttachmentLimits.maximumFileBytes else {
            throw ChatAttachmentError.fileTooLarge(name)
        }
        return ChatAttachment(
            name: replacingExtension(of: name, with: "jpg"),
            mediaType: "image/jpeg",
            data: jpeg,
            kind: .image,
            sourceURL: sourceURL
        )
    }

    private static func decodeText(_ data: Data) -> String? {
        for encoding in [String.Encoding.utf8, .utf16, .utf16LittleEndian,
                         .utf16BigEndian, .isoLatin1, .ascii] {
            if let string = String(data: data, encoding: encoding),
               !string.unicodeScalars.contains(where: { $0.value == 0 }) {
                return string
            }
        }
        return nil
    }

    private static func looksLikeText(_ data: Data) -> Bool {
        guard !data.isEmpty else { return true }
        let sample = data.prefix(8_192)
        let disallowed = sample.filter { byte in
            byte == 0 || (byte < 0x09) || (byte > 0x0D && byte < 0x20)
        }
        return Double(disallowed.count) / Double(sample.count) < 0.02
    }

    private static func truncate(_ text: String) -> (text: String, wasTruncated: Bool) {
        guard text.count > ChatAttachmentLimits.maximumExtractedCharacters else {
            return (text, false)
        }
        return (
            String(text.prefix(ChatAttachmentLimits.maximumExtractedCharacters)),
            true
        )
    }

    private static func replacingExtension(of name: String, with newExtension: String) -> String {
        let base = (name as NSString).deletingPathExtension
        return (base.isEmpty ? "Image" : base) + "." + newExtension
    }
}

enum PasteboardAttachmentReader {
    private static let webArchiveTypes = [
        NSPasteboard.PasteboardType("com.apple.webarchive"),
        NSPasteboard.PasteboardType("Apple Web Archive pasteboard type")
    ]

    static func itemProviders(from pasteboard: NSPasteboard) -> [NSItemProvider] {
        let directProviders = (pasteboard.pasteboardItems ?? []).map(itemProvider)
        if directProviders.contains(where: supportsDirectAttachment) {
            return directProviders
        }

        if let image = embeddedWebArchiveImage(from: pasteboard)
            ?? embeddedHTMLImage(from: pasteboard)
            ?? renderedImage(from: pasteboard) {
            return [imageProvider(data: image.data, typeIdentifier: image.typeIdentifier)]
        }

        return []
    }

    private static func supportsDirectAttachment(_ provider: NSItemProvider) -> Bool {
        provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
            || provider.registeredTypeIdentifiers.contains { identifier in
                UTType(identifier)?.conforms(to: .image) == true
            }
    }

    private static func embeddedWebArchiveImage(
        from pasteboard: NSPasteboard
    ) -> (data: Data, typeIdentifier: String)? {
        for type in webArchiveTypes {
            guard let archiveData = pasteboard.data(forType: type),
                  archiveData.count <= ChatAttachmentLimits.maximumTotalBytes,
                  let archive = try? PropertyListSerialization.propertyList(
                      from: archiveData,
                      options: [],
                      format: nil
                  ) as? [String: Any] else {
                continue
            }

            let mainResource = archive["WebMainResource"] as? [String: Any]
            let subresources = archive["WebSubresources"] as? [[String: Any]] ?? []
            for resource in [mainResource].compactMap({ $0 }) + subresources {
                guard let data = resource["WebResourceData"] as? Data,
                      let mimeType = resource["WebResourceMIMEType"] as? String,
                      let type = UTType(mimeType: mimeType),
                      type.conforms(to: .image) else {
                    continue
                }
                return (data, type.identifier)
            }
        }
        return nil
    }

    private static func embeddedHTMLImage(
        from pasteboard: NSPasteboard
    ) -> (data: Data, typeIdentifier: String)? {
        guard let html = pasteboard.string(forType: .html),
              html.utf8.count <= ChatAttachmentLimits.maximumTotalBytes else {
            return nil
        }
        let pattern = #"data:(image/[a-z0-9.+-]+);base64,([^\"'<>\s]+)"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = expression.firstMatch(in: html, range: range),
              let mimeRange = Range(match.range(at: 1), in: html),
              let dataRange = Range(match.range(at: 2), in: html),
              let type = UTType(mimeType: String(html[mimeRange])),
              type.conforms(to: .image),
              let data = Data(
                  base64Encoded: String(html[dataRange]),
                  options: .ignoreUnknownCharacters
              ) else {
            return nil
        }
        return (data, type.identifier)
    }

    private static func renderedImage(
        from pasteboard: NSPasteboard
    ) -> (data: Data, typeIdentifier: String)? {
        guard let image = NSImage(pasteboard: pasteboard),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return (png, UTType.png.identifier)
    }

    private static func itemProvider(from pasteboardItem: NSPasteboardItem) -> NSItemProvider {
        let provider = NSItemProvider()
        for type in pasteboardItem.types {
            guard let data = pasteboardItem.data(forType: type) else { continue }
            provider.registerDataRepresentation(
                forTypeIdentifier: type.rawValue,
                visibility: .all
            ) { completion in
                completion(data, nil)
                return nil
            }
        }
        return provider
    }

    private static func imageProvider(
        data: Data,
        typeIdentifier: String
    ) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: typeIdentifier,
            visibility: .all
        ) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }
}

@MainActor
final class DraftAttachments: ObservableObject {
    @Published private(set) var attachments: [ChatAttachment] = []
    @Published private(set) var isLoading = false
    @Published var notice: Notice?

    func add(urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        for url in urls {
            do {
                let attachment = try await load(url: url)
                try append(attachment)
            } catch {
                notice = Notice(message: error.localizedDescription, recovery: nil)
            }
        }
    }

    func addDroppedImage(data: Data, typeIdentifier: String?, suggestedName: String?) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let type = typeIdentifier.flatMap(UTType.init)
            let attachment = try await Task.detached(priority: .userInitiated) {
                try ChatAttachmentLoader.load(
                    data: data,
                    name: suggestedName ?? "Dropped image",
                    contentType: type
                )
            }.value
            try append(attachment)
        } catch {
            notice = Notice(message: error.localizedDescription, recovery: nil)
        }
    }

    func addPastedImage(data: Data, typeIdentifier: String) async {
        await addDroppedImage(
            data: data,
            typeIdentifier: typeIdentifier,
            suggestedName: Self.pastedImageName(typeIdentifier: typeIdentifier)
        )
    }

    func acceptPastedText(_ text: String) -> Bool {
        guard text.count >= ChatAttachmentLimits.longTextPasteCharacters else {
            return false
        }
        Task { @MainActor [weak self] in
            await self?.addPastedText(text)
        }
        return true
    }

    func acceptPastedItems(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(
                    forTypeIdentifier: UTType.fileURL.identifier,
                    options: nil
                ) { [weak self] item, _ in
                    guard let url = Self.fileURL(from: item) else { return }
                    Task { @MainActor [weak self] in
                        await self?.add(urls: [url])
                    }
                }
                continue
            }

            guard let identifier = Self.preferredImageIdentifier(from: provider) else {
                continue
            }
            provider.loadDataRepresentation(forTypeIdentifier: identifier) { [weak self] data, _ in
                guard let data else { return }
                Task { @MainActor [weak self] in
                    await self?.addPastedImage(data: data, typeIdentifier: identifier)
                }
            }
        }
    }

    func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        let supported = providers.filter { provider in
            provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                || provider.registeredTypeIdentifiers.contains(where: { identifier in
                    UTType(identifier)?.conforms(to: .image) == true
                })
        }
        guard !supported.isEmpty else { return false }

        for provider in supported {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(
                    forTypeIdentifier: UTType.fileURL.identifier,
                    options: nil
                ) { [weak self] item, _ in
                    guard let url = Self.fileURL(from: item) else { return }
                    Task { @MainActor [weak self] in
                        await self?.add(urls: [url])
                    }
                }
                continue
            }

            guard let identifier = Self.preferredImageIdentifier(from: provider) else { continue }
            let suggestedName = provider.suggestedName
            provider.loadDataRepresentation(forTypeIdentifier: identifier) { [weak self] data, _ in
                guard let data else { return }
                Task { @MainActor [weak self] in
                    await self?.addDroppedImage(
                        data: data,
                        typeIdentifier: identifier,
                        suggestedName: suggestedName
                    )
                }
            }
        }
        return true
    }

    func remove(_ attachment: ChatAttachment) {
        attachments.removeAll { $0.id == attachment.id }
    }

    func removeAll() {
        attachments = []
        notice = nil
    }

    func takeAll() -> [ChatAttachment] {
        let result = attachments
        attachments = []
        notice = nil
        return result
    }

    private func load(url: URL) async throws -> ChatAttachment {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        return try await Task.detached(priority: .userInitiated) {
            try ChatAttachmentLoader.load(from: url)
        }.value
    }

    private func addPastedText(_ text: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let data = Data(text.utf8)
            let attachment = try await Task.detached(priority: .userInitiated) {
                try ChatAttachmentLoader.load(
                    data: data,
                    name: Self.pastedTextName(),
                    contentType: .plainText
                )
            }.value
            try append(attachment)
        } catch {
            notice = Notice(message: error.localizedDescription, recovery: nil)
        }
    }

    private func append(_ attachment: ChatAttachment) throws {
        guard attachments.count < ChatAttachmentLimits.maximumCount else {
            throw ChatAttachmentError.tooManyFiles
        }
        let total = attachments.reduce(attachment.data.count) { $0 + $1.data.count }
        guard total <= ChatAttachmentLimits.maximumTotalBytes else {
            throw ChatAttachmentError.totalTooLarge
        }
        attachments.append(attachment)
    }

    private nonisolated static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        if let string = item as? String { return URL(string: string) }
        return nil
    }

    private nonisolated static func preferredImageIdentifier(
        from provider: NSItemProvider
    ) -> String? {
        let identifiers = provider.registeredTypeIdentifiers.filter {
            UTType($0)?.conforms(to: .image) == true
        }
        return identifiers.first(where: { UTType($0) == .png }) ?? identifiers.first
    }

    private nonisolated static func pastedImageName(
        typeIdentifier: String,
        date: Date = Date()
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let fileExtension = UTType(typeIdentifier)?.preferredFilenameExtension ?? "png"
        return "Pasted Image \(formatter.string(from: date)).\(fileExtension)"
    }

    private nonisolated static func pastedTextName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Pasted Text \(formatter.string(from: date)).txt"
    }
}

struct AttachmentStrip: View {
    let attachments: [ChatAttachment]
    let onRemove: (ChatAttachment) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 6) {
                        attachmentName(attachment)

                        SwiftUI.Button {
                            onRemove(attachment)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove \(attachment.name)")
                        .accessibilityLabel("Remove \(attachment.name)")
                    }
                    .padding(.trailing, 7)
                    .background(.thinMaterial, in: Capsule())
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func attachmentName(_ attachment: ChatAttachment) -> some View {
        if let sourceURL = attachment.sourceURL,
           FileManager.default.fileExists(atPath: sourceURL.path) {
            SwiftUI.Button {
                NSWorkspace.shared.activateFileViewerSelecting([sourceURL])
            } label: {
                filename(attachment.name)
            }
            .buttonStyle(.plain)
            .help("Show \(attachment.name) in Finder")
            .accessibilityLabel("Show \(attachment.name) in Finder")
        } else {
            filename(attachment.name)
        }
    }

    private func filename(_ name: String) -> some View {
        Text(name)
            .font(.caption)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: 180, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, 5)
            .padding(.leading, 10)
    }
}
