import AppKit
import SwiftUI

@main
struct LayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
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
