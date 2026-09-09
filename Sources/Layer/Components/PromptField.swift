import AppKit
import Combine
import SwiftUI

struct PromptField<Accessory: View>: View {
    @Binding var text: String

    var placeholder = "Ask anything…"
    var shouldFocus = false
    var focusRequests: AnyPublisher<Void, Never>?
    var onCommandReturn: (() -> Void)?
    var showsChrome = true
    var lineLimit: ClosedRange<Int> = 1...5
    var textInsets = EdgeInsets(top: 16, leading: 12, bottom: 16, trailing: 12)
    var minTextHeight: CGFloat = 0
    var isDisabled = false
    var onFocusChange: ((Bool) -> Void)?
    let onSubmit: (String) -> Void
    @ViewBuilder var accessory: Accessory

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .controlSize(.large)
                .lineLimit(lineLimit)
                .disabled(isDisabled)
                .padding(textInsets)
                .frame(maxWidth: .infinity, minHeight: minTextHeight, alignment: .topLeading)
                .focused($isFocused)
                .onAppear {
                    updateFocus(shouldFocus)
                }
                .onChange(of: shouldFocus) {
                    updateFocus(shouldFocus)
                }
                .onReceive(focusRequests ?? Empty().eraseToAnyPublisher()) { _ in
                    updateFocus(true)
                }
                .onChange(of: isFocused) {
                    onFocusChange?(isFocused)
                }
                .onKeyPress(.return, phases: .down) { keyPress in
                    handleReturn(keyPress)
                }
                .accessibilityLabel(placeholder)

            accessory
        }
        .background {
            if showsChrome {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            }
        }
        .overlay {
            if showsChrome {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        isFocused ? Color.accentColor : Color(nsColor: .separatorColor),
                        lineWidth: isFocused ? 2 : 1
                    )
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                updateFocus(true)
            }
        )
    }

    private func handleReturn(_ keyPress: KeyPress) -> KeyPress.Result {
        if keyPress.modifiers.contains(.command) {
            guard let onCommandReturn else { return .ignored }
            onCommandReturn()
            return .handled
        }

        guard !keyPress.modifiers.contains(.shift) else {
            return insertNewline()
        }

        onSubmit(text)
        return .handled
    }

    private func insertNewline() -> KeyPress.Result {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else {
            return .ignored
        }

        editor.insertText("\n", replacementRange: editor.selectedRange())
        return .handled
    }

    private func updateFocus(_ shouldFocus: Bool) {
        DispatchQueue.main.async {
            isFocused = shouldFocus
        }
    }
}

extension PromptField where Accessory == EmptyView {
    init(
        text: Binding<String>,
        placeholder: String = "Ask anything…",
        shouldFocus: Bool = false,
        focusRequests: AnyPublisher<Void, Never>? = nil,
        onCommandReturn: (() -> Void)? = nil,
        showsChrome: Bool = true,
        lineLimit: ClosedRange<Int> = 1...5,
        textInsets: EdgeInsets = EdgeInsets(top: 16, leading: 12, bottom: 16, trailing: 12),
        minTextHeight: CGFloat = 0,
        isDisabled: Bool = false,
        onFocusChange: ((Bool) -> Void)? = nil,
        onSubmit: @escaping (String) -> Void
    ) {
        self.init(
            text: text,
            placeholder: placeholder,
            shouldFocus: shouldFocus,
            focusRequests: focusRequests,
            onCommandReturn: onCommandReturn,
            showsChrome: showsChrome,
            lineLimit: lineLimit,
            textInsets: textInsets,
            minTextHeight: minTextHeight,
            isDisabled: isDisabled,
            onFocusChange: onFocusChange,
            onSubmit: onSubmit,
            accessory: { EmptyView() }
        )
    }
}
