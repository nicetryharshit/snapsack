import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let carrier = Carrier()
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private var settings: SettingsWindow?

    private var carryItem = NSMenuItem()
    private var permissionsSeparator = NSMenuItem.separator()
    private var accessibilityItem = NSMenuItem()
    private var screenRecordingItem = NSMenuItem()
    private var loginItem = NSMenuItem()
    private var hintItem = NSMenuItem()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Dropper.pruneOldDrops()
        setUpStatusItem()
        hotKey = makeHotKey(Shortcut.current)
        showWelcomeIfNeeded()
    }

    // MARK: - Shortcut

    private func makeHotKey(_ shortcut: Shortcut) -> HotKey? {
        HotKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
            self?.carrier.begin()
        }
    }

    /// Switches to `shortcut` and saves it. Returns an error message if it can't be used, leaving the old one in place.
    private func applyShortcut(_ shortcut: Shortcut) -> String? {
        let previous = Shortcut.current
        // Release the old registration first, so the same combination can be taken again.
        hotKey = nil
        guard let fresh = makeHotKey(shortcut) else {
            hotKey = makeHotKey(previous)
            return "That shortcut is already used by macOS or another app. Try a different one."
        }
        hotKey = fresh
        Shortcut.current = shortcut
        updateCarryItem()
        return nil
    }

    private func updateCarryItem() {
        let shortcut = Shortcut.current
        carryItem.keyEquivalent = shortcut.menuKey
        carryItem.keyEquivalentModifierMask = shortcut.menuModifiers
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuBarIcon.make()
        item.button?.toolTip = "SnapSack"

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        carryItem = NSMenuItem(title: "Carry a Screenshot", action: #selector(carryScreenshot), keyEquivalent: "")
        carryItem.target = self
        updateCarryItem()
        menu.addItem(carryItem)

        menu.addItem(.separator())
        hintItem = NSMenuItem(title: Settings.shared.hintLine, action: nil, keyEquivalent: "")
        hintItem.isEnabled = false
        menu.addItem(hintItem)

        menu.addItem(permissionsSeparator)
        accessibilityItem = NSMenuItem(title: "Allow Accessibility…", action: #selector(allowAccessibility), keyEquivalent: "")
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)
        screenRecordingItem = NSMenuItem(title: "Allow Screen Recording…", action: #selector(allowScreenRecording), keyEquivalent: "")
        screenRecordingItem.target = self
        menu.addItem(screenRecordingItem)

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit SnapSack", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let needsAccessibility = !Permissions.accessibilityGranted
        let needsScreen = !Permissions.screenRecordingGranted
        accessibilityItem.isHidden = !needsAccessibility
        screenRecordingItem.isHidden = !needsScreen
        permissionsSeparator.isHidden = !(needsAccessibility || needsScreen)
        loginItem.state = LoginItem.isEnabled ? .on : .off
        hintItem.title = Settings.shared.hintLine
    }

    @objc private func carryScreenshot() {
        // Let the menu finish closing before the crosshair appears.
        Task { @MainActor [self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            self.carrier.begin()
        }
    }

    @objc private func openSettings() {
        if settings == nil {
            settings = SettingsWindow { [weak self] shortcut in
                self?.applyShortcut(shortcut)
            }
        }
        settings?.show()
    }

    @objc private func allowAccessibility() {
        Permissions.requestAccessibility()
    }

    @objc private func allowScreenRecording() {
        Permissions.requestScreenRecording()
    }

    @objc private func toggleLogin() {
        do {
            try LoginItem.set(!LoginItem.isEnabled)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't change the login item"
            NSApp.activate()
            alert.runModal()
        }
    }

    // MARK: - First launch

    private func showWelcomeIfNeeded() {
        let key = "didShowWelcome"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "SnapSack is in your menu bar"
        var lines = [
            "Press \(Shortcut.current.display) and drag over anything on screen. The screenshot rides your cursor.",
            "",
            "Double-click to drop it into whatever's under the cursor.",
        ]
        if Settings.shared.shakeToToss { lines.append("Shake the mouse to toss it.") }
        lines.append(Settings.shared.escapeSentence)
        lines += [
            "",
            "You can change all of this in Settings.",
            "SnapSack will ask for Accessibility and Screen Recording access the first time you use it.",
        ]
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: "Got it")
        alert.runModal()

        if !Permissions.accessibilityGranted { Permissions.requestAccessibility() }
    }
}
