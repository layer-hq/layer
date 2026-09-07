import AppKit
import Combine
import SwiftUI

@MainActor
enum NotchMaterialFactory {
    // NSGlassEffectView.Style.regular. Keep this as an integer because the
    // class is only available dynamically with the project's current SDK.
    private static let regularGlassStyle = 0

    static func makeView(cornerRadius: CGFloat, contentView: NSView) -> NSView {
        if #available(macOS 26.0, *),
           let glassClass = NSClassFromString("NSGlassEffectView") as? NSObject.Type,
           let glassView = glassClass.init() as? NSView {
            glassView.setValue(cornerRadius, forKey: "cornerRadius")
            glassView.setValue(regularGlassStyle, forKey: "style")
            glassView.setValue(contentView, forKey: "contentView")
            return glassView
        }

        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: view.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        return view
    }
}

private struct NotchMaterialView<Content: View>: NSViewRepresentable {
    let cornerRadius: CGFloat
    let content: Content

    init(cornerRadius: CGFloat, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(content: content)
    }

    func makeNSView(context: Context) -> NSView {
        NotchMaterialFactory.makeView(
            cornerRadius: cornerRadius,
            contentView: context.coordinator.hostingView
        )
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.hostingView.rootView = content
    }

    @MainActor
    final class Coordinator {
        let hostingView: NSHostingView<Content>

        init(content: Content) {
            hostingView = NSHostingView(rootView: content)
        }
    }
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
    let onSubmitPrompt: (String, Bool) -> Void
    let onToggleVoice: () -> Void
    let onContentHeightChange: (CGFloat) -> Void

    @State private var prompt = ""
    @AppStorage("openAIAPIKey") private var apiKey = ""
    @AppStorage("takeScreenContext") private var takeScreenContext = false
    @AppStorage("includeSelectedContent") private var includeSelectedContent = false

    var body: some View {
        GeometryReader { geometry in
            let isExpanded = session.isExpanded
            let cornerRadius: CGFloat = 24
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

            NotchMaterialView(cornerRadius: cornerRadius) {
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
                .onHover { hovering in
                    onHoverChange(hovering)
                }
                .onPreferenceChange(ControlTrayHeightPreferenceKey.self) { height in
                    guard height > 0 else { return }
                    onContentHeightChange(height)
                }
                .animation(.easeOut(duration: 0.1), value: isExpanded)
                .animation(.easeOut(duration: 0.1), value: voiceMode.state)
                .onChange(of: session.isGenerating) {
                    if !session.isGenerating, !session.isExpanded {
                        prompt = ""
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(shape)
        }
    }

    private func controlTray(isExpanded: Bool) -> some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                PhosphorIcon.layerLogo
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)

                Spacer()

                if let label = voiceMode.state.label {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(
                    icon: Image(systemName: voiceMode.isActive ? "waveform.fill" : "waveform"),
                    label: "Voice mode",
                    showsProgress: voiceMode.state == .connecting,
                    action: onToggleVoice
                )

                Button(
                    icon: Image(systemName: "gearshape"),
                    label: "Settings…",
                    action: showSettings
                )
            }

            if let notice = session.notice {
                noticeBanner(notice) { session.notice = nil }
            }

            if let notice = voiceMode.notice {
                noticeBanner(notice) { voiceMode.dismissNotice() }
            }

            if apiKey.isEmpty {
                WarningBanner(message: "OpenAI API key is not present") {
                    SwiftUI.Button(action: showSettings) {
                        Text("Open Settings")
                    }
                    .controlSize(.small)
                }
            }

            HStack(spacing: 8) {
                PromptField(
                    text: $prompt,
                    shouldFocus: isExpanded && !voiceMode.isActive && !session.isGenerating,
                    focusRequests: promptFocusRequests,
                    onCommandReturn: { submit(insertMode: true) },
                    onSubmit: { _ in submit(insertMode: false) }
                )
                .disabled(voiceMode.isActive || session.isGenerating)

                Button(
                    icon: Image(systemName: "bubble.left"),
                    label: "Chat",
                    shortcut: "↵",
                ) {
                    submit(insertMode: false)
                }
                .disabled(!canSubmit)

                Button(
                    icon: Image(systemName: "arrow.down.to.line"),
                    label: session.isGenerating ? "Inserting" : "Insert",
                    shortcut: session.isGenerating ? nil : "⌘ ↵",
                    showsProgress: session.isGenerating
                ) {
                    submit(insertMode: true)
                }
                .disabled(!canSubmit && !session.isGenerating)
                .allowsHitTesting(!session.isGenerating)
                .accessibilityLabel(session.isGenerating ? "Generating" : "Insert")
            }

            HStack(spacing: 12) {
                Toggle("Take screen context", isOn: $takeScreenContext)
                    .toggleStyle(.checkbox)
                    .accessibilityHint("Include information from the screen with the prompt")

                Toggle("Include selected content", isOn: $includeSelectedContent)
                    .toggleStyle(.checkbox)
                    .help("May briefly use the clipboard when required.")
                    .accessibilityHint("May briefly use the clipboard when required.")

                SwiftUI.Button(action: onSelect) {
                    HStack(spacing: 6) {
                        PhosphorIcon.selection
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                        Text("Select")
                    }
                }
                .controlSize(.small)
                .disabled(session.isGenerating)
                .accessibilityHint("Enter select mode")

                Spacer()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    private var canSubmit: Bool {
        !session.isGenerating
            && !voiceMode.isActive
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit(insertMode: Bool) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty, canSubmit else { return }
        if !insertMode {
            prompt = ""
        }
        onSubmitPrompt(trimmedPrompt, insertMode)
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
                SwiftUI.Button("System Settings", action: openScreenRecordingSettings)
                    .controlSize(.small)
            case .microphoneSettings:
                SwiftUI.Button("System Settings", action: openMicrophoneSettings)
                    .controlSize(.small)
            case .accessibilitySettings:
                SwiftUI.Button("System Settings", action: openAccessibilitySettings)
                    .controlSize(.small)
            case .settings:
                SwiftUI.Button("Open Settings", action: showSettings)
                    .controlSize(.small)
            case nil:
                EmptyView()
            }

            SwiftUI.Button("Dismiss", action: dismiss)
                .controlSize(.small)
        }
    }
}
