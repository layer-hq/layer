import AppKit
import MarkdownUI
import Splash
import SwiftUI

struct AssistantMarkdownView: View {
    let content: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Markdown(content)
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                allowsMarkdownOpenURL(url) ? .systemAction : .discarded
            })
            .markdownCodeSyntaxHighlighter(SplashCodeSyntaxHighlighter(theme: splashTheme))
            .markdownImageProvider(DisabledMarkdownImageProvider())
            .markdownInlineImageProvider(DisabledInlineMarkdownImageProvider())
            .markdownBlockStyle(\.codeBlock) { configuration in
                codeBlock(configuration)
            }
    }

    private func codeBlock(_ configuration: CodeBlockConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(configuration.language.map { $0.isEmpty ? "plain text" : $0 } ?? "plain text")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(configuration.content, forType: .string)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Copy code")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            ScrollView(.horizontal) {
                configuration.label
                    .relativeLineSpacing(.em(0.2))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.85))
                    }
                    .padding(10)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .markdownMargin(top: .em(0.4), bottom: .em(0.6))
    }

    private var splashTheme: Splash.Theme {
        let font = Splash.Font(size: 13)
        switch colorScheme {
        case .dark:
            return .wwdc17(withFont: font)
        default:
            return .sunset(withFont: font)
        }
    }
}

func allowsMarkdownOpenURL(_ url: URL) -> Bool {
    switch url.scheme?.lowercased() {
    case "http", "https":
        return true
    default:
        return false
    }
}

private struct DisabledMarkdownImageProvider: ImageProvider {
    func makeImage(url: URL?) -> some View {
        EmptyView()
    }
}

private struct DisabledInlineMarkdownImageProvider: InlineImageProvider {
    func image(with url: URL, label: String) async throws -> Image {
        throw CancellationError()
    }
}

// The SplashCodeSyntaxHighlighter, TextOutputFormat, and Builder types below are
// adapted from swift-markdown-ui's documentation on custom code syntax
// highlighters (https://github.com/gonzalezreal/swift-markdown-ui),
// Copyright (c) 2020 Guillermo Gonzalez, MIT licensed. See THIRD-PARTY-NOTICES.md.
private struct SplashCodeSyntaxHighlighter: CodeSyntaxHighlighter {
    private let syntaxHighlighter: SyntaxHighlighter<TextOutputFormat>

    init(theme: Splash.Theme) {
        syntaxHighlighter = SyntaxHighlighter(format: TextOutputFormat(theme: theme))
    }

    func highlightCode(_ content: String, language: String?) -> Text {
        guard let language, !language.isEmpty else {
            return Text(content)
        }
        return syntaxHighlighter.highlight(content)
    }
}

private struct TextOutputFormat: OutputFormat {
    private let theme: Splash.Theme

    init(theme: Splash.Theme) {
        self.theme = theme
    }

    func makeBuilder() -> Builder {
        Builder(theme: theme)
    }

    struct Builder: OutputBuilder {
        private let theme: Splash.Theme
        private var accumulatedText: [Text] = []

        init(theme: Splash.Theme) {
            self.theme = theme
        }

        mutating func addToken(_ token: String, ofType type: TokenType) {
            let color = theme.tokenColors[type] ?? theme.plainTextColor
            accumulatedText.append(Text(token).foregroundColor(Color(nsColor: color)))
        }

        mutating func addPlainText(_ text: String) {
            accumulatedText.append(
                Text(text).foregroundColor(Color(nsColor: theme.plainTextColor))
            )
        }

        mutating func addWhitespace(_ whitespace: String) {
            accumulatedText.append(Text(whitespace))
        }

        func build() -> Text {
            accumulatedText.reduce(Text(""), +)
        }
    }
}
