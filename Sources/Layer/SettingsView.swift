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
    @State private var apiKey = ""
    @State private var isKeyVisible = false
    @State private var statusMessage: String?
    @AppStorage("openAIAPIKey") private var savedAPIKey = ""
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
    @AppStorage(VoiceShortcutPreferences.isEnabledKey)
    private var voiceShortcutEnabled = true
    @AppStorage(VoiceShortcutPreferences.modifierFlagsKey)
    private var voiceModifierFlags = Int(
        VoiceShortcutPreferences.defaultModifiers.rawValue
    )
    @AppStorage(VoiceShortcutPreferences.characterKey)
    private var voiceCharacter = "M"
    @AppStorage(VoiceShortcutPreferences.keyCodeKey)
    private var voiceKeyCode = Int(kVK_ANSI_M)

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170)
        } detail: {
            switch selection ?? .apiKeys {
            case .apiKeys:
                apiKeysView
            case .shortcuts:
                shortcutsView
            }
        }
        .frame(width: 650, height: 520)
        .onAppear(perform: loadKey)
    }

    private var apiKeysView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("API Keys")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("OpenAI API key")
                    .font(.headline)
                Text("Saved locally in this app's preferences for your macOS user account. Turns may use OpenAI web search, billed on this key.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Link(
                    "Get an API key",
                    destination: URL(string: "https://platform.openai.com/api-keys")!
                )
                .font(.subheadline)
            }

            HStack(spacing: 8) {
                Group {
                    if isKeyVisible {
                        TextField("sk-…", text: $apiKey)
                    } else {
                        SecureField("sk-…", text: $apiKey)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .onSubmit(saveKey)

                Button {
                    isKeyVisible.toggle()
                } label: {
                    Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help(isKeyVisible ? "Hide API key" : "Show API key")
                .accessibilityLabel(isKeyVisible ? "Hide API key" : "Show API key")
            }

            HStack {
                if let statusMessage {
                    Label(
                        statusMessage,
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(Color.green)
                }

                Spacer()

                if !savedAPIKey.isEmpty {
                    Button("Remove Key", role: .destructive, action: removeKey)
                }

                Button("Save", action: saveKey)
                    .keyboardShortcut(.defaultAction)
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
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
                    keyCode: $selectionKeyCode
                )
                .frame(width: 140, height: 28)
            }
            .disabled(!selectionShortcutEnabled)

            Divider()

            Toggle("Enable Voice Mode shortcut", isOn: $voiceShortcutEnabled)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Voice Mode")
                        .font(.headline)
                    Text("Starts or stops voice mode.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ShortcutRecorder(
                    modifierFlags: $voiceModifierFlags,
                    character: $voiceCharacter,
                    keyCode: $voiceKeyCode
                )
                .frame(width: 140, height: 28)
            }
            .disabled(!voiceShortcutEnabled)

            Text("macOS may ask for Input Monitoring permission so the shortcut works in other apps.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func loadKey() {
        apiKey = savedAPIKey
    }

    private func saveKey() {
        let cleanedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedKey.isEmpty else { return }

        savedAPIKey = cleanedKey
        apiKey = cleanedKey
        statusMessage = "API key saved"
    }

    private func removeKey() {
        savedAPIKey = ""
        apiKey = ""
        statusMessage = "API key removed"
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    @Binding var modifierFlags: Int
    @Binding var character: String
    @Binding var keyCode: Int

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        ShortcutRecorderControl()
    }

    func updateNSView(_ control: ShortcutRecorderControl, context: Context) {
        control.shortcut = (
            NSEvent.ModifierFlags(rawValue: UInt(modifierFlags)),
            character,
            UInt16(keyCode)
        )
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
        setAccessibilityLabel("Select shortcut")
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
