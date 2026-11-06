import AppKit

@main
@MainActor
struct SnapSackApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // menu bar only: no Dock icon, no app switcher entry
        app.run()
    }
}
