import SwiftUI

enum ButtonAppearance {
    case subtle
    case filled
}

struct Button: View {
    var icon: Image? = nil
    var label: String? = nil
    var shortcut: String?
    var showsProgress = false
    var appearance: ButtonAppearance = .subtle
    var isSelected = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool
    @State private var isHovering = false

    var body: some View {
        SwiftUI.Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                let frameSize: CGFloat = icon != nil ? 12 : 0
                Group {
                    if showsProgress {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        icon?
                            .font(.system(size: frameSize))
                    }
                }
                .frame(width: frameSize, height: frameSize)

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
        .foregroundStyle(foregroundTint)
        .background {
            Capsule()
                .fill(backgroundTint)
                .overlay {
                    Capsule()
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .opacity(isFocused ? 1 : 0)
                }
        }
        .focused($isFocused)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
        .opacity(isEnabled ? 1 : 0.5)
        .animation(.easeOut(duration: 0.1), value: isHovering)
        .animation(.easeOut(duration: 0.1), value: isFocused)
    }

    private var buttonTint: Color {
        colorScheme == .dark ? .white : .black
    }

    private var invertedTint: Color {
        colorScheme == .dark ? .black : .white
    }

    private var foregroundTint: Color {
        if appearance == .filled, isEnabled {
            return invertedTint
        }
        if isSelected {
            return .accentColor
        }
        return buttonTint
    }

    private var backgroundTint: Color {
        if appearance == .filled {
            guard isEnabled else { return buttonTint.opacity(0.05) }
            return buttonTint.opacity(isHovering ? 0.78 : 0.92)
        }
        if isSelected {
            return Color.accentColor.opacity(isHovering ? 0.26 : 0.18)
        }
        return buttonTint.opacity(isHovering ? 0.2 : 0.1)
    }
}
