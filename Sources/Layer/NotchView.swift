import AppKit
import Combine
import SwiftUI

@MainActor
enum NotchMaterialFactory {
    static let cornerRadius: CGFloat = 24

    private static let regularGlassStyle = 0

    private static let adaptiveAppearanceOff = 1
    private static let adaptiveAppearanceSetter = Selector(("set_adaptiveAppearance:"))

    static func makeView(cornerRadius: CGFloat, contentView: NSView) -> NSView {
        if #available(macOS 26.0, *),
           let glassClass = NSClassFromString("NSGlassEffectView") as? NSObject.Type,
           let glassView = glassClass.init() as? NSView {
            glassView.setValue(cornerRadius, forKey: "cornerRadius")
            glassView.setValue(regularGlassStyle, forKey: "style")
            glassView.setValue(contentView, forKey: "contentView")
            if glassView.responds(to: adaptiveAppearanceSetter) {
                glassView.setValue(
                    NSNumber(value: adaptiveAppearanceOff),
                    forKey: "_adaptiveAppearance"
                )
            }
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

func appendingDictation(_ transcript: String, to prompt: String) -> String {
    let transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !transcript.isEmpty else { return prompt }
    guard !prompt.isEmpty else { return transcript }
    return prompt.last?.isWhitespace == true
        ? prompt + transcript
        : prompt + " " + transcript
}

struct NotchMaterialView<Content: View>: NSViewRepresentable {
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
    @ObservedObject var dictation: DictationController
    let expandedWidth: CGFloat
    let promptFocusRequests: AnyPublisher<Void, Never>
    let onHoverChange: (Bool) -> Void
    let onSelect: () -> Void
    let onSubmitPrompt: (String, Bool) -> Void
    let onToggleVoice: () -> Void
    let onToggleDictation: () -> Void
    let onContentHeightChange: (CGFloat) -> Void

    @State private var prompt = ""
    @AppStorage(ModelProviderPreferences.configurationsKey)
    private var storedProviderConfigurations = ""
    @AppStorage(ModelProviderPreferences.selectedConfigurationIDKey)
    private var selectedProviderID = ""
    @AppStorage("takeScreenContext") private var takeScreenContext = false
    @AppStorage("includeSelectedContent") private var includeSelectedContent = false
    @State private var promptIsFocused = false

    var body: some View {
        GeometryReader { geometry in
            let isExpanded = session.isExpanded
            let cornerRadius = NotchMaterialFactory.cornerRadius
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

            NotchMaterialView(cornerRadius: cornerRadius) {
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
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height,
                        alignment: .top
                    )
                    .onHover { hovering in
                        onHoverChange(hovering)
                    }
                    .onPreferenceChange(ControlTrayHeightPreferenceKey.self) { height in
                        guard height > 0 else { return }
                        onContentHeightChange(height)
                    }
                    .animation(.easeOut(duration: 0.1), value: isExpanded)
                    .animation(.easeOut(duration: 0.1), value: voiceMode.state)
                    .animation(.easeOut(duration: 0.1), value: dictation.state)
                    .onChange(of: session.isGenerating) {
                        if !session.isGenerating, !session.isExpanded {
                            prompt = ""
                        }
                    }
                    .onReceive(dictation.transcripts) { transcript in
                        prompt = appendingDictation(transcript, to: prompt)
                    }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(shape)
        }
    }

    private func controlTray(isExpanded: Bool) -> some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                AppIcon.layerLogo
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)

                Spacer()

                if let label = voiceMode.state.label ?? dictation.state.label {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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

            if let notice = dictation.notice {
                noticeBanner(notice) { dictation.dismissNotice() }
            }

            if !hasActiveProvider {
                WarningBanner(message: "No model provider is selected") {
                    SwiftUI.Button(action: showSettings) {
                        Text("Open Settings")
                    }
                    .controlSize(.small)
                }
            }

            PromptField(
                text: $prompt,
                shouldFocus: isExpanded
                    && !voiceMode.isActive
                    && !dictation.isActive
                    && !session.isGenerating,
                focusRequests: promptFocusRequests,
                onCommandReturn: { submit(insertMode: true) },
                showsChrome: false,
                lineLimit: 1...5,
                textInsets: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18),
                minTextHeight: 62,
                isDisabled: voiceMode.isActive || dictation.isActive || session.isGenerating,
                onFocusChange: { promptIsFocused = $0 },
                onSubmit: { _ in submit(insertMode: false) }
            ) {
                HStack(spacing: 8) {
                    Button(
                        icon: Image(systemName: "display"),
                        label: "Entire screen",
                        isSelected: takeScreenContext
                    ) {
                        takeScreenContext.toggle()
                    }
                    .disabled(session.isGenerating)
                    .accessibilityHint("Include information from the screen with the prompt")

                    Button(
                        icon: Image(systemName: "text.quote"),
                        label: "Selected text",
                        isSelected: includeSelectedContent
                    ) {
                        includeSelectedContent.toggle()
                    }
                    .disabled(session.isGenerating)
                    .help("May briefly use the clipboard when required.")
                    .accessibilityHint("May briefly use the clipboard when required.")

                    Button(
                        icon: Image(
                            systemName: dictation.state == .recording
                                ? "mic.fill"
                                : "mic"
                        ),
                        label: dictation.state == .recording ? "Stop" : "Dictate",
                        showsProgress: dictation.state == .transcribing,
                        isSelected: dictation.state == .recording,
                        action: onToggleDictation
                    )
                    .disabled(
                        voiceMode.isActive
                            || session.isGenerating
                            || dictation.state == .transcribing
                    )

                    Spacer(minLength: 8)

                    Button(
                        label: "Ask",
                        shortcut: "↵",
                        appearance: .filled
                    ) {
                        submit(insertMode: false)
                    }
                    .disabled(!canSubmit)

                    Button(
                        label: session.isGenerating ? "Inserting" : "Insert",
                        shortcut: session.isGenerating ? nil : "⌘ ↵",
                        showsProgress: session.isGenerating,
                        appearance: .filled
                    ) {
                        submit(insertMode: true)
                    }
                    .disabled(!canSubmit && !session.isGenerating)
                    .allowsHitTesting(!session.isGenerating)
                    .accessibilityLabel(session.isGenerating ? "Generating" : "Insert")
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.34))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        promptIsFocused ? Color.accentColor : Color(nsColor: .separatorColor),
                        lineWidth: promptIsFocused ? 2 : 1
                    )
                    .allowsHitTesting(false)
            }
            .animation(.easeOut(duration: 0.1), value: promptIsFocused)

            HStack(spacing: 10) {
                Button(
                        icon: Image(systemName: "viewfinder"),
                        label: "Select area…",
                        action: onSelect
                    )
                    .disabled(session.isGenerating || dictation.isActive)
                    .accessibilityHint("Enter select mode")

                Spacer()

                Button(
                    icon: Image(systemName: voiceMode.isActive ? "waveform.fill" : "waveform"),
                    label: "Voice mode",
                    showsProgress: voiceMode.state == .connecting,
                    action: onToggleVoice
                )
                .disabled(dictation.isActive)
            }
        }
        .padding(18)
    }

    private var hasActiveProvider: Bool {
        _ = storedProviderConfigurations
        _ = selectedProviderID
        return ModelProviderPreferences.activeConfiguration() != nil
    }

    private var canSubmit: Bool {
        !session.isGenerating
            && !voiceMode.isActive
            && !dictation.isActive
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
