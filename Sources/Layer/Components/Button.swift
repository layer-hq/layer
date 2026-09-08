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
            .padding(.horizontal, isIconOnly ? 0 : 15)
            .frame(
                width: isIconOnly ? 32 : nil,
                height: 32,
                alignment: .center
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(foregroundTint)
        .background { buttonBackground }
        .focused($isFocused)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
        .arrowCursor()
        .opacity(isEnabled ? 1 : 0.5)
        .animation(.easeOut(duration: 0.1), value: isHovering)
        .animation(.easeOut(duration: 0.1), value: isFocused)
    }

    private var isIconOnly: Bool {
        icon != nil && label == nil && shortcut == nil
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
            return Color.accentColor.opacity(isHovering ? 0.34 : 0.26)
        }
        return buttonTint.opacity(isHovering ? 0.28 : 0.16)
    }

    @ViewBuilder
    private var buttonBackground: some View {
        if appearance == .filled {
            Capsule()
                .fill(backgroundTint)
                .overlay { focusRing }
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule().fill(backgroundTint)
                }
                .overlay { focusRing }
        }
    }

    private var focusRing: some View {
        Capsule()
            .strokeBorder(Color.accentColor, lineWidth: 2)
            .opacity(isFocused ? 1 : 0)
    }
}
