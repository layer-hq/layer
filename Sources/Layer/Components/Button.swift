import SwiftUI

struct Button: View {
    let icon: Image
    var label: String? = nil
    var shortcut: String?
    var showsProgress = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool
    @State private var isHovering = false

    var body: some View {
        SwiftUI.Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                Group {
                    if showsProgress {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        icon
                            .font(.system(size: 12))
                    }
                }
                .frame(width: 12, height: 12)

                if let label {
                    Text(label)
                }

                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 12))
                        .opacity(0.5)
                }
            }
            .padding(.horizontal, 15)
            .frame(height: 32, alignment: .center)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(buttonTint)
        .background {
            Capsule()
                .fill(buttonTint.opacity(isHovering ? 0.2 : 0.1))
        }
        .focused($isFocused)
        .onHover { isHovering = $0 }
        .opacity(isEnabled ? 1 : 0.5)
        .animation(.easeOut(duration: 0.1), value: isHovering)
    }

    private var buttonTint: Color {
        colorScheme == .dark ? .white : .black
    }
}