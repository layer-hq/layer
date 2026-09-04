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
    @ObservedObject var voiceMode: VoiceModeController
    let topInset: CGFloat
    let expandedWidth: CGFloat
    let promptFocusRequests: AnyPublisher<Void, Never>
    let onHoverChange: (Bool) -> Void
    let onSelect: () -> Void
    let onSubmitPrompt: (String, Bool, Bool) -> Void
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
            .animation(.easeOut(duration: 0.15), value: voiceMode.state)
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

                if let label = voiceMode.state.label {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    voiceMode.toggle()
                } label: {
                    if voiceMode.state == .connecting {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 18, height: 18)
                            .padding(7)
                    } else {
                        Image(systemName: voiceMode.isActive ? "mic.fill" : "mic")
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 18, height: 18)
                            .padding(7)
                    }
                }
                .buttonStyle(.automatic)
                .help(voiceMode.isActive ? "Stop voice mode" : "Start voice mode")
                .accessibilityLabel(
                    voiceMode.isActive ? "Stop voice mode" : "Start voice mode"
                )

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
                noticeBanner(notice) { session.notice = nil }
            }

            if let notice = voiceMode.notice {
                noticeBanner(notice) { voiceMode.dismissNotice() }
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
                shouldFocus: isExpanded && !voiceMode.isActive,
                focusRequests: promptFocusRequests,
                onSubmit: { submittedPrompt, insertMode in
                    let trimmedPrompt = submittedPrompt.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    guard !trimmedPrompt.isEmpty else { return }
                    prompt = ""
                    onSubmitPrompt(trimmedPrompt, takeScreenContext, insertMode)
                }
            )
            .disabled(voiceMode.isActive)

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

    @ViewBuilder
    private func noticeBanner(
        _ notice: Notice,
        dismiss: @escaping () -> Void
    ) -> some View {
        WarningBanner(message: notice.message) {
            switch notice.recovery {
            case .screenRecordingSettings:
                Button("System Settings", action: openScreenRecordingSettings)
                    .controlSize(.small)
            case .microphoneSettings:
                Button("System Settings", action: openMicrophoneSettings)
                    .controlSize(.small)
            case .accessibilitySettings:
                Button("System Settings", action: openAccessibilitySettings)
                    .controlSize(.small)
            case .settings:
                Button("Open Settings", action: showSettings)
                    .controlSize(.small)
            case nil:
                EmptyView()
            }

            Button("Dismiss", action: dismiss)
                .controlSize(.small)
        }
    }
}
