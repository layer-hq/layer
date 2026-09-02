import AppKit
import Combine
import SwiftUI

private struct SidebarMaterialView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct ControlTrayHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct NotchView: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var session: NotchSession
    let topInset: CGFloat
    let expandedWidth: CGFloat
    let promptFocusRequests: AnyPublisher<Void, Never>
    let onHoverChange: (Bool) -> Void
    let onSelect: () -> Void
    let onSubmitPrompt: (String, Bool) -> Void
    let onContentHeightChange: (CGFloat) -> Void

    @State private var prompt = ""
    @AppStorage("openAIAPIKey") private var apiKey = ""
    @AppStorage("takeScreenContext") private var takeScreenContext = false

    var body: some View {
        GeometryReader { geometry in
            let isExpanded = session.isExpanded

            VStack(spacing: 0) {
                Color.clear.frame(height: topInset)

                controlTray(isExpanded: isExpanded)
                    .frame(width: expandedWidth)
                    .fixedSize(horizontal: false, vertical: true)
                    .background {
                        GeometryReader { trayGeometry in
                            Color.clear.preference(
                                key: ControlTrayHeightPreferenceKey.self,
                                value: trayGeometry.size.height
                            )
                        }
                    }
                    .opacity(isExpanded ? 1 : 0)
                    .offset(y: isExpanded ? 0 : -8)
                    .allowsHitTesting(isExpanded)
                    .accessibilityHidden(!isExpanded)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background {
                SidebarMaterialView()
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onHover { hovering in
                onHoverChange(hovering)
            }
            .onPreferenceChange(ControlTrayHeightPreferenceKey.self) { height in
                guard height > 0 else { return }
                onContentHeightChange(height)
            }
            .animation(.easeOut(duration: 0.15), value: isExpanded)
        }
    }

    private func controlTray(isExpanded: Bool) -> some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                PhosphorIcon.layerLogo
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .accessibilityLabel("Layer")

                Spacer()

                Button(action: showSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 18, height: 18)
                        .padding(7)
                }
                .buttonStyle(.automatic)
                .help("Settings")
                .accessibilityLabel("Open Settings")
            }

            if let notice = session.notice {
                WarningBanner(message: notice.message) {
                    if notice.recovery == .screenRecordingSettings {
                        Button("System Settings", action: openScreenRecordingSettings)
                            .controlSize(.small)
                    }

                    Button("Dismiss") {
                        session.notice = nil
                    }
                    .controlSize(.small)
                }
            }

            if apiKey.isEmpty {
                WarningBanner(message: "OpenAI API key is not present") {
                    Button(action: showSettings) {
                        Text("Open Settings")
                    }
                    .controlSize(.small)
                }
            }

            PromptField(
                text: $prompt,
                shouldFocus: isExpanded,
                focusRequests: promptFocusRequests,
                onSubmit: { submittedPrompt in
                    let trimmedPrompt = submittedPrompt.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    guard !trimmedPrompt.isEmpty else { return }
                    prompt = ""
                    onSubmitPrompt(trimmedPrompt, takeScreenContext)
                }
            )

            HStack(spacing: 12) {
                Toggle("Take screen context", isOn: $takeScreenContext)
                    .toggleStyle(.checkbox)
                    .accessibilityHint("Include information from the screen with the prompt")

                Button(action: onSelect) {
                    HStack(spacing: 6) {
                        PhosphorIcon.selection
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                        Text("Select")
                    }
                }
                .controlSize(.small)
                .accessibilityHint("Enter select mode")

                Spacer()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    private func showSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openSettings()
    }
}
