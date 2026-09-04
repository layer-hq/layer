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

struct WarningBanner<Actions: View>: View {
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.subheadline.weight(.medium))

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
        }
    }
}
