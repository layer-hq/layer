import AppKit
import Combine
import SwiftUI

struct PromptField: View {
    @Binding var text: String

    var placeholder = "Ask anything"
    var shouldFocus = false
    var focusRequests: AnyPublisher<Void, Never>?
    var onCommandReturn: (() -> Void)?
    let onSubmit: (String) -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .controlSize(.large)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        isFocused ? Color.accentColor : Color(nsColor: .separatorColor),
                        lineWidth: isFocused ? 2 : 1
                    )
            }
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
            .onSubmit {
                onSubmit(text)
            }
            .onKeyPress(.return, phases: .down) { keyPress in
                guard keyPress.modifiers.contains(.command),
                      let onCommandReturn else {
                    return .ignored
                }
                onCommandReturn()
                return .handled
            }
            .accessibilityLabel(placeholder)
    }

    private func updateFocus(_ shouldFocus: Bool) {
        DispatchQueue.main.async {
            isFocused = shouldFocus
        }
    }
}

struct PromptActionButton: View {
    let title: String
    var shortcut: String?
    let help: String
    let fill: Color
    let shade: Double
    var showsProgress = false
    var minWidth: CGFloat = 104
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if showsProgress {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(.white)
                }
                Text(title)
                    .font(.callout.weight(.semibold))
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.28))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(.white.opacity(0.32), lineWidth: 0.5)
                        }
                }
            }
            .padding(.horizontal, 14)
            .frame(minWidth: minWidth)
            .frame(maxHeight: .infinity)
            .foregroundStyle(.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(fill)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.black.opacity(shade))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 0.5)
        }
        .help(help)
        .accessibilityHint(help)
    }
}

struct WarningBanner<Actions: View>: View {
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.subheadline.weight(.medium))
                .textSelection(.enabled)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Copy")

            Spacer()

            actions
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}
