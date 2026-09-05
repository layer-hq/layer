import AppKit
import Sparkle
import SwiftUI

@main
struct LayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updaterController.checkForUpdates(nil)
                }
            }
        }
    }
}

@MainActor
func openScreenRecordingSettings() {
    openPrivacySettings("Privacy_ScreenCapture")
}

@MainActor
func openMicrophoneSettings() {
    openPrivacySettings("Privacy_Microphone")
}

@MainActor
private func openPrivacySettings(_ pane: String) {
    guard let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
    ) else {
        return
    }
    NSWorkspace.shared.open(url)
}

@MainActor
func openAccessibilitySettings() {
    openPrivacySettings("Privacy_Accessibility")
}
