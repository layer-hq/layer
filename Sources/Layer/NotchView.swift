import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

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

enum ScreenContextChipLayout {
    static let focusHaloClearance: CGFloat = 6
    static let maximumLabelWidth: CGFloat = 140

    static func hoverIconName(isAttached: Bool) -> String {
        isAttached ? "xmark" : "plus"
    }
}

private struct ScreenContextChip: View {
    let target: ScreenContextTarget
    let isAttached: Bool
    let action: () -> Void
    let onHoverChange: (Bool) -> Void

    @State private var isHovering = false

    var body: some View {
        SwiftUI.Button(action: action) {
            HStack(spacing: 7) {
                ZStack {
                    targetIcon
                        .opacity(isHovering ? 0 : 1)

                    Image(
                        systemName: ScreenContextChipLayout.hoverIconName(
                            isAttached: isAttached
                        )
                    )
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(isHovering ? 1 : 0)
                }
                .frame(width: 14, height: 14)

                Text(target.label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(
                        maxWidth: ScreenContextChipLayout.maximumLabelWidth,
                        alignment: .leading
                    )
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(backgroundColor, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(
                        isAttached ? Color.accentColor.opacity(0.5) : Color.clear,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            onHoverChange(hovering)
        }
        .arrowCursor()
        .animation(.easeOut(duration: 0.1), value: isHovering)
        .help(isAttached ? "Remove \(target.label) context" : "Attach \(target.label) context")
        .accessibilityLabel(
            isAttached ? "Remove \(target.label) context" : "Attach \(target.label) context"
        )
    }

    private var backgroundColor: Color {
        if isAttached {
            return Color.accentColor.opacity(isHovering ? 0.32 : 0.2)
        }
        return Color.primary.opacity(isHovering ? 0.18 : 0.1)
    }

    @ViewBuilder
    private var targetIcon: some View {
        switch target.kind {
        case .entireScreen:
            Image(systemName: "display")
                .font(.system(size: 12))
        case .applicationWindow(let processID, _):
            if let image = NSRunningApplication(processIdentifier: processID)?.icon {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "macwindow")
                    .font(.system(size: 12))
            }
        }
    }
}

private struct ScreenContextActionChip: View {
    let iconName: String
    let label: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        SwiftUI.Button(action: action) {
            HStack(spacing: 7) {
                ZStack {
                    Image(systemName: iconName)
                        .font(.system(size: 12))
                        .opacity(isHovering ? 0 : 1)

                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .opacity(isHovering ? 1 : 0)
                }
                .frame(width: 14, height: 14)

                Text(label)
                    .lineLimit(1)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(
                Color.primary.opacity(isHovering ? 0.18 : 0.1),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .arrowCursor()
        .animation(.easeOut(duration: 0.1), value: isHovering)
        .help(label)
        .accessibilityLabel(label)
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
    let onHoverScreenContextTarget: (ScreenContextTarget?) -> Void
    let onAttachmentAdded: () -> Void
    let onSelect: () -> Void
    let onSubmitPrompt: (String, Bool, [ChatAttachment], [ScreenContextTarget]) -> Void
    // let onToggleVoice: () -> Void
    let onToggleDictation: () -> Void
    let onContentHeightChange: (CGFloat) -> Void

    @State private var prompt = ""
    @AppStorage(ModelProviderPreferences.configurationsKey)
    private var storedProviderConfigurations = ""
    @AppStorage(ModelProviderPreferences.selectedConfigurationIDKey)
    private var selectedProviderID = ""
    @AppStorage("includeSelectedContent") private var includeSelectedContent = false
    @State private var promptIsFocused = false
    @State private var isFileImporterPresented = false
    @State private var isAttachmentDropTargeted = false
    @StateObject private var draftAttachments = DraftAttachments()

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
                        guard !isAttachmentDropTargeted else { return }
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
                            draftAttachments.removeAll()
                        }
                    }
                    .onReceive(dictation.transcripts) { transcript in
                        guard dictation.surface == .notch else { return }
                        prompt = appendingDictation(transcript, to: prompt)
                    }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(shape)
            .onDrop(
                of: [UTType.fileURL.identifier, UTType.image.identifier],
                isTargeted: $isAttachmentDropTargeted,
                perform: { providers in
                    guard !session.isGenerating,
                          !dictation.isActive,
                          !voiceMode.isActive else { return false }
                    let accepted = draftAttachments.acceptDrop(providers)
                    if accepted { onAttachmentAdded() }
                    return accepted
                }
            )
            .onChange(of: isAttachmentDropTargeted) {
                guard isAttachmentDropTargeted, !session.isExpanded else { return }
                onHoverChange(true)
            }
            .onChange(of: draftAttachments.attachments) { previous, current in
                guard current.count > previous.count else { return }
                onAttachmentAdded()
            }
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

                if let label = voiceMode.state.label
                    ?? (dictation.isNotchActive ? dictation.state.label : nil) {
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

            if let notice = dictation.notice, dictation.surface == .notch {
                noticeBanner(notice) { dictation.dismissNotice() }
            }

            if let notice = draftAttachments.notice {
                noticeBanner(notice) { draftAttachments.notice = nil }
            }

            if !hasActiveProvider {
                WarningBanner(message: "No model provider is selected") {
                    SwiftUI.Button(action: showSettings) {
                        Text("Open Settings")
                    }
                    .controlSize(.small)
                }
            }

            VStack(spacing: 4) {
            PromptField(
                text: $prompt,
                shouldFocus: isExpanded
                    && !voiceMode.isActive
                    && !dictation.isNotchActive
                    && !session.isGenerating,
                focusRequests: promptFocusRequests,
                onCommandReturn: { submit(insertMode: true) },
                showsChrome: false,
                lineLimit: 1...5,
                textInsets: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18),
                minTextHeight: 62,
                topAccessory: composerTopAccessory,
                onPasteAttachments: { draftAttachments.acceptPastedItems($0) },
                onPasteText: { draftAttachments.acceptPastedText($0) },
                isDisabled: voiceMode.isActive || dictation.isNotchActive || session.isGenerating,
                onFocusChange: { promptIsFocused = $0 },
                onSubmit: { _ in submit(insertMode: false) }
            ) {
                HStack(spacing: 8) {
                        Button(
                            icon: Image(systemName: "paperclip"),
                            showsProgress: draftAttachments.isLoading
                        ) {
                            isFileImporterPresented = true
                        }
                        .disabled(session.isGenerating || dictation.isActive)
                        .help("Attach up to 5 images, PDFs, or text files (10 MB each, 25 MB total)")
                        .accessibilityLabel("Attach files")

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
                            icon: Image(systemName: isNotchRecording ? "mic.fill" : "mic"),
                            label: isNotchRecording ? "Stop" : "Dictate",
                            showsProgress: dictation.isNotchActive
                                && dictation.state == .transcribing,
                            isSelected: isNotchRecording,
                            action: onToggleDictation
                        )
                        .disabled(
                            voiceMode.isActive
                                || session.isGenerating
                                || dictation.state == .transcribing
                                || dictation.isChatActive
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
            .overlay(alignment: .topTrailing) {
                if isAttachmentDropTargeted {
                    Label("Drop to attach", systemImage: "paperclip")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .padding(10)
                        .allowsHitTesting(false)
                }
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.image, .pdf, .text],
                allowsMultipleSelection: true
            ) { result in
                guard case .success(let urls) = result else { return }
                Task { await draftAttachments.add(urls: urls) }
            }

                suggestedContextChips
            }

        }
        .padding(18)
    }

    private var hasActiveProvider: Bool {
        _ = storedProviderConfigurations
        _ = selectedProviderID
        return ModelProviderPreferences.activeConfiguration() != nil
    }

    private var isNotchRecording: Bool {
        dictation.isNotchActive && dictation.state == .recording
    }

    private var canSubmit: Bool {
        !session.isGenerating
            && !voiceMode.isActive
            && !dictation.isNotchActive
            && (!prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !draftAttachments.attachments.isEmpty)
    }

    private func submit(insertMode: Bool) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSubmit else { return }
        let attachments = draftAttachments.attachments
        let submittedPrompt = trimmedPrompt.isEmpty && !attachments.isEmpty
            ? "Please analyze the attached \(attachments.count == 1 ? "file" : "files")."
            : trimmedPrompt
        if !insertMode {
            prompt = ""
            draftAttachments.removeAll()
        }
        onSubmitPrompt(
            submittedPrompt,
            insertMode,
            attachments,
            session.selectedScreenContextTargets
        )
    }

    private var composerTopAccessory: AnyView? {
        let hasContext = !session.selectedScreenContextTargets.isEmpty
        let hasFiles = !draftAttachments.attachments.isEmpty
        guard hasContext || hasFiles else { return nil }

        return AnyView(
            VStack(spacing: 4) {
                if hasContext {
                    attachedContextChips
                }
                if hasFiles {
                    AttachmentStrip(attachments: draftAttachments.attachments) {
                        draftAttachments.remove($0)
                    }
                }
            }
            .padding(.top, 6)
        )
    }

    private var attachedContextChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(session.selectedScreenContextTargets) { target in
                    ScreenContextChip(target: target, isAttached: true) {
                        session.toggleScreenContextTarget(target)
                    } onHoverChange: { _ in
                        onHoverScreenContextTarget(nil)
                    }
                    .disabled(session.isGenerating)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, ScreenContextChipLayout.focusHaloClearance)
        }
    }

    private var suggestedContextChips: some View {
        let suggestions = session.screenContextTargets.filter {
            !session.selectedScreenContextTargetIDs.contains($0.id)
        }
        let entireScreen = suggestions.first { $0.kind == .entireScreen }
        let windows = suggestions.filter { $0.kind != .entireScreen }

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let entireScreen {
                    ScreenContextChip(target: entireScreen, isAttached: false) {
                        onHoverScreenContextTarget(nil)
                        session.toggleScreenContextTarget(entireScreen)
                    } onHoverChange: { hovering in
                        onHoverScreenContextTarget(hovering ? entireScreen : nil)
                    }
                    .disabled(session.isGenerating)
                }

                ScreenContextActionChip(
                    iconName: "viewfinder",
                    label: "Select area…"
                ) {
                    onHoverScreenContextTarget(nil)
                    onSelect()
                }
                .disabled(session.isGenerating || dictation.isActive)
                .accessibilityHint("Enter select mode")

                ForEach(windows) { target in
                    ScreenContextChip(target: target, isAttached: false) {
                        onHoverScreenContextTarget(nil)
                        session.toggleScreenContextTarget(target)
                    } onHoverChange: { hovering in
                        onHoverScreenContextTarget(hovering ? target : nil)
                    }
                    .disabled(session.isGenerating)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, ScreenContextChipLayout.focusHaloClearance)
        }
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
