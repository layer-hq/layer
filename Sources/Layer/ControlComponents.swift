import AppKit
import SwiftUI

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

            SwiftUI.Button {
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
