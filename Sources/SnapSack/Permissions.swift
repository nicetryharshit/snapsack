import AppKit
import ApplicationServices
import CoreGraphics

/// The two things SnapSack needs from macOS:
///  - Accessibility: to catch the double-click / Esc while a screenshot is on the cursor, and to press ⌘V.
///  - Screen Recording: so the region you select actually contains other apps' pixels.
enum Permissions {
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        // Shows the system prompt that points at the right Settings pane.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }

    static func requestScreenRecording() {
        let key = "didAskScreenRecording"
        if UserDefaults.standard.bool(forKey: key) {
            // macOS only shows its own prompt once; after that the Settings pane is the only way.
            openSettings(pane: "Privacy_ScreenCapture")
        } else {
            UserDefaults.standard.set(true, forKey: key)
            _ = CGRequestScreenCaptureAccess()
        }
    }

    static func openSettings(pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
