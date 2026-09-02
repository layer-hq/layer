import AppKit
import Carbon.HIToolbox
import Testing
@testable import Layer

struct InvocationShortcutTests {
    @Test
    func convertsSelectionShortcutModifiersForGlobalRegistration() {
        #expect(
            SelectionShortcutPreferences.defaultModifiers == [.command, .shift]
        )
        #expect(GlobalSelectionShortcut.carbonModifiers(
            from: [.command, .shift]
        ) == UInt32(cmdKey | shiftKey))
        #expect(GlobalSelectionShortcut.carbonModifiers(
            from: [.control, .option]
        ) == UInt32(controlKey | optionKey))
    }

    @Test
    func recognizesTwoControlPressesButNotAControlKeyCombination() {
        var recognizer = DoubleModifierPressRecognizer()

        let firstPress = recognizer.processModifierFlags(
            .control,
            at: 1,
            modifier: .control
        )
        let firstRelease = recognizer.processModifierFlags(
            [],
            at: 1.1,
            modifier: .control
        )
        let secondPress = recognizer.processModifierFlags(
            .control,
            at: 1.3,
            modifier: .control
        )
        #expect(!firstPress)
        #expect(!firstRelease)
        #expect(secondPress)

        recognizer.reset()
        let combinationFirstPress = recognizer.processModifierFlags(
            .control,
            at: 2,
            modifier: .control
        )
        recognizer.cancelSequence()
        _ = recognizer.processModifierFlags([], at: 2.1, modifier: .control)
        let pressAfterCancellation = recognizer.processModifierFlags(
            .control,
            at: 2.2,
            modifier: .control
        )
        #expect(!combinationFirstPress)
        #expect(!pressAfterCancellation)

        recognizer.reset()
        _ = recognizer.processModifierFlags(.control, at: 3, modifier: .control)
        _ = recognizer.processModifierFlags(
            [.control, .shift],
            at: 3.1,
            modifier: .control
        )
        _ = recognizer.processModifierFlags([], at: 3.2, modifier: .control)
        let pressAfterOtherModifier = recognizer.processModifierFlags(
            .control,
            at: 3.3,
            modifier: .control
        )
        #expect(!pressAfterOtherModifier)
    }
}
