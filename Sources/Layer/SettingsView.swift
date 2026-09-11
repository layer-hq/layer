import AppKit
import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case apiKeys = "API Keys"
        case shortcuts = "Shortcuts"

        var id: Self { self }

        var icon: String {
            switch self {
            case .apiKeys: "key"
            case .shortcuts: "keyboard"
            }
        }
    }

    @State private var selection: Section? = .apiKeys
    @State private var providerSelection: ModelProviderKind? = .openAI
    @State private var configurations: [ModelProviderConfiguration] = []
    @State private var activeConfigurationID: UUID?
    @State private var draftConfiguration = ModelProviderConfiguration(kind: .openAI)
    @State private var isKeyVisible = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @AppStorage(InvocationShortcutPreferences.isEnabledKey)
    private var invocationShortcutEnabled = true
    @AppStorage(InvocationShortcutPreferences.modifierKey)
    private var invocationModifier = InvocationModifier.control.rawValue
    @AppStorage(SelectionShortcutPreferences.isEnabledKey)
    private var selectionShortcutEnabled = true
    @AppStorage(SelectionShortcutPreferences.modifierFlagsKey)
    private var selectionModifierFlags = Int(
        SelectionShortcutPreferences.defaultModifiers.rawValue
    )
    @AppStorage(SelectionShortcutPreferences.characterKey)
    private var selectionCharacter = "A"
    @AppStorage(SelectionShortcutPreferences.keyCodeKey)
    private var selectionKeyCode = 0
    @AppStorage(DictationShortcutPreferences.isEnabledKey)
    private var dictationShortcutEnabled = true
    @AppStorage(DictationShortcutPreferences.modifierFlagsKey)
    private var dictationModifierFlags = Int(
        DictationShortcutPreferences.defaultModifiers.rawValue
    )
    @AppStorage(DictationShortcutPreferences.characterKey)
    private var dictationCharacter = "M"
    @AppStorage(DictationShortcutPreferences.keyCodeKey)
    private var dictationKeyCode = Int(kVK_ANSI_M)

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 150, max: 150)
        } detail: {
            switch selection ?? .apiKeys {
            case .apiKeys:
                apiKeysView
            case .shortcuts:
                shortcutsView
            }
        }
        .frame(minWidth: 650, minHeight: 480)
        .onAppear(perform: loadProviders)
    }

    private var apiKeysView: some View {
        HSplitView {
            List(ModelProviderKind.allCases, selection: $providerSelection) { kind in
                providerRow(kind)
                    .tag(kind)
            }
            .frame(width: 150)
            .onChange(of: providerSelection) {
                loadDraft()
            }

            providerEditor
                .frame(minWidth: 350)
        }
    }

    private func providerRow(_ kind: ModelProviderKind) -> some View {
        HStack(spacing: 8) {
            SwiftUI.Button {
                activate(kind)
            } label: {
                Image(
                    systemName: configuration(for: kind)?.id
                        == activeConfigurationID
                        ? "largecircle.fill.circle"
                        : "circle"
                )
            }
            .buttonStyle(.plain)
            .help("Use \(kind.name)")
            .accessibilityLabel("Use \(kind.name)")

            Text(kind.name)
        }
    }

    private var providerEditor: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(draftConfiguration.kind.name)
                .font(.title2.weight(.semibold))

            Text("Configure this provider, then choose the active provider with the radio button in the sidebar. Keys stay in this app's local preferences.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Use HTTPS for remote hosts. HTTP is intended for local providers such as localhost.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow {
                    Text("Base URL")
                    TextField("http://localhost:4000", text: $draftConfiguration.baseURL)
                        .textFieldStyle(.roundedBorder)
                        .disabled(draftConfiguration.kind == .openAI)
                        .help(
                            draftConfiguration.kind == .openAI
                                ? "OpenAI uses its official API endpoint."
                                : "The base URL of your LiteLLM proxy."
                        )
                }
                GridRow {
                    Text("API key")
                    HStack(spacing: 8) {
                        Group {
                            if isKeyVisible {
                                TextField("sk-…", text: $draftConfiguration.apiKey)
                            } else {
                                SecureField("sk-…", text: $draftConfiguration.apiKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)

                        SwiftUI.Button {
                            isKeyVisible.toggle()
                        } label: {
                            Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .help(isKeyVisible ? "Hide API key" : "Show API key")
                    }
                }
                GridRow {
                    Text("Model")
                    HStack(spacing: 8) {
                        TextField("Model name or proxy alias", text: $draftConfiguration.model)
                            .textFieldStyle(.roundedBorder)

                        if !availableModels.isEmpty {
                            Menu("Choose") {
                                ForEach(availableModels, id: \.self) { model in
                                    SwiftUI.Button(model) {
                                        draftConfiguration.model = model
                                    }
                                }
                            }
                        }
                    }
                }
            }

            HStack {
                SwiftUI.Button("Load Models", action: loadModels)
                    .disabled(isLoadingModels)

                if isLoadingModels {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                SwiftUI.Button("Save", action: saveProvider)
                    .keyboardShortcut(.defaultAction)
            }

            if draftConfiguration.kind == .liteLLM {
                Text("Chat and Insert use LiteLLM's OpenAI-compatible API. Voice currently requires an OpenAI connection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let statusMessage {
                Label(
                    statusMessage,
                    systemImage: statusIsError
                        ? "exclamationmark.triangle.fill"
                        : "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(statusIsError ? Color.orange : Color.green)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var shortcutsView: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Shortcuts")
                .font(.title2.weight(.semibold))

            Toggle("Enable Invoke Layer shortcut", isOn: $invocationShortcutEnabled)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Invoke Layer")
                        .font(.headline)
                    Text("Opens Layer and focuses the textbox.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Modifier", selection: $invocationModifier) {
                    ForEach(InvocationModifier.allCases) { modifier in
                        Text(modifier.name).tag(modifier.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 120)

                Text("twice")
                    .foregroundStyle(.secondary)
            }
            .disabled(!invocationShortcutEnabled)

            Divider()

            Toggle("Enable Select shortcut", isOn: $selectionShortcutEnabled)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Select")
                        .font(.headline)
                    Text("Starts selecting an area of the screen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ShortcutRecorder(
                    modifierFlags: $selectionModifierFlags,
                    character: $selectionCharacter,
                    keyCode: $selectionKeyCode,
                    accessibilityLabel: "Select shortcut"
                )
                .frame(width: 140, height: 28)
            }
            .disabled(!selectionShortcutEnabled)

            Divider()

            Toggle("Enable Dictation fallback shortcut", isOn: $dictationShortcutEnabled)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dictation")
                        .font(.headline)
                    Text("Hold Fn to dictate into the prompt. This chord is the fallback when Fn is unavailable.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ShortcutRecorder(
                    modifierFlags: $dictationModifierFlags,
                    character: $dictationCharacter,
                    keyCode: $dictationKeyCode,
                    accessibilityLabel: "Dictation shortcut"
                )
                .frame(width: 140, height: 28)
            }
            .disabled(!dictationShortcutEnabled)

            Text("macOS may ask for Input Monitoring permission so the shortcut works in other apps.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func loadProviders() {
        let storedConfigurations = ModelProviderPreferences.configurations()
        let selectedKind = storedConfigurations.first(where: {
            $0.id == ModelProviderPreferences.selectedConfigurationID()
        })?.kind
        configurations = ModelProviderKind.allCases.map { kind in
            storedConfigurations.first(where: { $0.kind == kind })
                ?? ModelProviderConfiguration(kind: kind)
        }
        ModelProviderPreferences.saveConfigurations(configurations)

        let activeConfiguration = configuration(for: selectedKind ?? .openAI)
        activeConfigurationID = activeConfiguration?.id
        ModelProviderPreferences.select(activeConfigurationID)
        providerSelection = selectedKind ?? .openAI
        loadDraft()
    }

    private func loadDraft() {
        guard let kind = providerSelection,
              let configuration = configuration(for: kind) else {
            return
        }
        draftConfiguration = configuration
        isKeyVisible = false
        availableModels = []
        statusMessage = nil
    }

    private func activate(_ kind: ModelProviderKind) {
        guard let configuration = configuration(for: kind) else { return }
        providerSelection = kind
        activeConfigurationID = configuration.id
        ModelProviderPreferences.select(configuration.id)
        statusMessage = configuration.isReady
            ? "\(configuration.name) is active"
            : "Save all required fields before using this connection"
        statusIsError = !configuration.isReady
    }

    private func saveProvider() {
        var cleaned = draftConfiguration.cleaned()
        cleaned.name = cleaned.kind.name
        if cleaned.kind == .openAI {
            cleaned.baseURL = ModelProviderKind.openAI.defaultBaseURL
        }
        guard cleaned.apiRootURL != nil else {
            showError("Enter a valid base URL using http or https.")
            return
        }
        guard !cleaned.apiKey.isEmpty else {
            showError("Enter an API key.")
            return
        }
        guard !cleaned.model.isEmpty else {
            showError("Enter or choose a model.")
            return
        }
        guard let index = configurations.firstIndex(where: { $0.id == cleaned.id }) else {
            return
        }
        configurations[index] = cleaned
        draftConfiguration = cleaned
        ModelProviderPreferences.saveConfigurations(configurations)
        activeConfigurationID = cleaned.id
        ModelProviderPreferences.select(cleaned.id)
        statusMessage = "Provider saved and activated"
        statusIsError = false
    }

    private func configuration(
        for kind: ModelProviderKind
    ) -> ModelProviderConfiguration? {
        configurations.first(where: { $0.kind == kind })
    }

    private func loadModels() {
        isLoadingModels = true
        statusMessage = nil
        let provider = draftConfiguration.cleaned()
        Task {
            do {
                availableModels = try await ModelCatalogClient().models(for: provider)
                statusMessage = availableModels.isEmpty
                    ? "The provider returned no models"
                    : "Loaded \(availableModels.count) models"
                statusIsError = availableModels.isEmpty
            } catch {
                showError(error.localizedDescription)
            }
            isLoadingModels = false
        }
    }

    private func showError(_ message: String) {
        statusMessage = message
        statusIsError = true
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    @Binding var modifierFlags: Int
    @Binding var character: String
    @Binding var keyCode: Int
    let accessibilityLabel: String

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        let control = ShortcutRecorderControl()
        control.setAccessibilityLabel(accessibilityLabel)
        return control
    }

    func updateNSView(_ control: ShortcutRecorderControl, context: Context) {
        control.shortcut = (
            NSEvent.ModifierFlags(rawValue: UInt(modifierFlags)),
            character,
            UInt16(keyCode)
        )
        control.setAccessibilityLabel(accessibilityLabel)
        control.onChange = {
            modifierFlags = Int($0.rawValue)
            character = $1
            keyCode = Int($2)
        }
    }
}

final class ShortcutRecorderControl: NSButton {
    var shortcut: (NSEvent.ModifierFlags, String, UInt16) = (.command, "A", 0) {
        didSet { updateTitle() }
    }
    var onChange: ((NSEvent.ModifierFlags, String, UInt16) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func beginRecording() {
        window?.makeFirstResponder(self)
        title = "Type shortcut"
    }

    override func keyDown(with event: NSEvent) {
        record(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        record(event)
        return true
    }

    override func resignFirstResponder() -> Bool {
        updateTitle()
        return super.resignFirstResponder()
    }

    private func record(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        guard event.keyCode != 53 else {
            window?.makeFirstResponder(nil)
            return
        }

        let modifiers = event.modifierFlags.intersection([
            .control, .option, .shift, .command
        ])
        guard !modifiers.isEmpty,
              let character = event.charactersIgnoringModifiers?.first else {
            NSSound.beep()
            return
        }

        let key = String(character).uppercased()
        shortcut = (modifiers, key, event.keyCode)
        onChange?(modifiers, key, event.keyCode)
        window?.makeFirstResponder(nil)
    }

    private func updateTitle() {
        let modifiers = shortcut.0
        title = [
            modifiers.contains(.control) ? "⌃" : "",
            modifiers.contains(.option) ? "⌥" : "",
            modifiers.contains(.shift) ? "⇧" : "",
            modifiers.contains(.command) ? "⌘" : "",
            shortcut.1.uppercased()
        ].joined()
    }
}
