import AppKit
import Carbon.HIToolbox

enum InvocationModifier: String, CaseIterable, Identifiable {
    case control
    case option
    case command
    case shift

    var id: Self { self }

    var name: String {
        switch self {
        case .control: "Control"
        case .option: "Option"
        case .command: "Command"
        case .shift: "Shift"
        }
    }

    var eventFlag: NSEvent.ModifierFlags {
        switch self {
        case .control: .control
        case .option: .option
        case .command: .command
        case .shift: .shift
        }
    }
}

enum InvocationShortcutPreferences {
    static let isEnabledKey = "invocationShortcutEnabled"
    static let modifierKey = "invocationShortcutModifier"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            isEnabledKey: true,
            modifierKey: InvocationModifier.control.rawValue
        ])
    }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: isEnabledKey)
    }

    static var modifier: InvocationModifier {
        InvocationModifier(
            rawValue: UserDefaults.standard.string(forKey: modifierKey) ?? ""
        ) ?? .control
    }
}

enum SelectionShortcutPreferences {
    static let isEnabledKey = "selectionShortcutEnabled"
    static let modifierFlagsKey = "selectionShortcutModifierFlags"
    static let characterKey = "selectionShortcutCharacter"
    static let keyCodeKey = "selectionShortcutKeyCode"
    static let defaultModifiers: NSEvent.ModifierFlags = [.command, .shift]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            isEnabledKey: true,
            modifierFlagsKey: Int(defaultModifiers.rawValue),
            characterKey: "A",
            keyCodeKey: 0
        ])
    }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: isEnabledKey)
    }

    static var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(
            rawValue: UInt(UserDefaults.standard.integer(forKey: modifierFlagsKey))
        )
    }

    static var character: String {
        UserDefaults.standard.string(forKey: characterKey) ?? "A"
    }

    static var keyCode: UInt32 {
        UInt32(UserDefaults.standard.integer(forKey: keyCodeKey))
    }
}

enum DictationShortcutPreferences {
    static let isEnabledKey = "dictationShortcutEnabled"
    static let modifierFlagsKey = "dictationShortcutModifierFlags"
    static let characterKey = "dictationShortcutCharacter"
    static let keyCodeKey = "dictationShortcutKeyCode"
    static let defaultModifiers: NSEvent.ModifierFlags = [.command, .shift]
    static let defaultKeyCode = UInt32(kVK_ANSI_M)

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            isEnabledKey: true,
            modifierFlagsKey: Int(defaultModifiers.rawValue),
            characterKey: "M",
            keyCodeKey: Int(defaultKeyCode)
        ])
    }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: isEnabledKey)
    }

    static var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(
            rawValue: UInt(UserDefaults.standard.integer(forKey: modifierFlagsKey))
        )
    }

    static var character: String {
        UserDefaults.standard.string(forKey: characterKey) ?? "M"
    }

    static var keyCode: UInt32 {
        UInt32(UserDefaults.standard.integer(forKey: keyCodeKey))
    }
}

@MainActor
final class GlobalSelectionShortcut {
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private let hotKeyID: UInt32
    private let action: @MainActor () -> Void
    private let releaseAction: (@MainActor () -> Void)?

    init(
        id: UInt32,
        action: @escaping @MainActor () -> Void,
        releaseAction: (@MainActor () -> Void)? = nil
    ) {
        self.hotKeyID = id
        self.action = action
        self.releaseAction = releaseAction

        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }
                var pressed = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressed
                )
                guard status == noErr else {
                    return OSStatus(eventNotHandledErr)
                }
                return MainActor.assumeIsolated {
                    let shortcut = Unmanaged<GlobalSelectionShortcut>
                        .fromOpaque(userData)
                        .takeUnretainedValue()
                    guard pressed.id == shortcut.hotKeyID else {
                        return OSStatus(eventNotHandledErr)
                    }
                    if GetEventKind(event) == UInt32(kEventHotKeyReleased) {
                        shortcut.releaseAction?()
                    } else {
                        shortcut.action()
                    }
                    return noErr
                }
            },
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    func invalidate() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    func register(
        keyCode: UInt32,
        modifiers: NSEvent.ModifierFlags,
        enabled: Bool
    ) {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        guard enabled else { return }

        RegisterEventHotKey(
            keyCode,
            Self.carbonModifiers(from: modifiers),
            EventHotKeyID(signature: 0x4C_59_52_53, id: hotKeyID),
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
    }

    nonisolated static func carbonModifiers(
        from modifiers: NSEvent.ModifierFlags
    ) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        return result
    }
}

enum FnHoldEvent: Equatable {
    case began
    case ended
    case cancelled
}

struct FnHoldRecognizer {
    private var isDown = false
    private var held = false

    mutating func process(
        flags: NSEvent.ModifierFlags,
        keyCode: UInt16,
        type: NSEvent.EventType
    ) -> FnHoldEvent? {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        let fnDown = flags.contains(.function)
        let extraModifiers = !flags.subtracting(.function).isEmpty

        if type == .keyDown {
            guard held, keyCode != UInt16(kVK_Function) else { return nil }
            held = false
            isDown = fnDown
            return .cancelled
        }

        guard type == .flagsChanged else { return nil }

        if fnDown, !extraModifiers, !isDown {
            isDown = true
            held = true
            return .began
        }
        if held, fnDown, extraModifiers {
            held = false
            isDown = true
            return .cancelled
        }
        if held, !fnDown {
            held = false
            isDown = false
            return .ended
        }

        isDown = fnDown
        return nil
    }
}

struct DoubleModifierPressRecognizer {
    private let maximumInterval: TimeInterval
    private var activeModifier: InvocationModifier?
    private var modifierIsDown = false
    private var previousPressAt: TimeInterval?

    init(maximumInterval: TimeInterval = 0.5) {
        self.maximumInterval = maximumInterval
    }

    mutating func processModifierFlags(
        _ flags: NSEvent.ModifierFlags,
        at timestamp: TimeInterval,
        modifier: InvocationModifier
    ) -> Bool {
        if activeModifier != modifier {
            reset()
            activeModifier = modifier
        }

        let flags = flags.intersection(.deviceIndependentFlagsMask)
        let isDown = flags.contains(modifier.eventFlag)
        defer { modifierIsDown = isDown }

        if isDown, flags != modifier.eventFlag {
            previousPressAt = nil
        }
        guard isDown, !modifierIsDown else { return false }
        guard flags == modifier.eventFlag else {
            return false
        }

        if let previousPressAt,
           timestamp >= previousPressAt,
           timestamp - previousPressAt <= maximumInterval {
            self.previousPressAt = nil
            return true
        }

        previousPressAt = timestamp
        return false
    }

    mutating func cancelSequence() {
        previousPressAt = nil
    }

    mutating func reset() {
        activeModifier = nil
        modifierIsDown = false
        previousPressAt = nil
    }
}
