import AppKit
import Carbon.HIToolbox

/// The settings window: General, Controls and Animation. Every control saves and applies at once.
@MainActor
final class SettingsWindow: NSWindowController, NSWindowDelegate {
    /// Tries to make `shortcut` the active one. Returns an error message, or nil on success.
    private let apply: (Shortcut) -> String?

    private var currentLabel = NSTextField(labelWithString: "")
    private var recordButton = NSButton(title: "Record…", target: nil, action: nil)
    private var resetShortcutButton = NSButton(title: "Reset to Default", target: nil, action: nil)
    private var messageLabel = NSTextField(wrappingLabelWithString: "")
    private var escapeCaption = NSTextField(wrappingLabelWithString: "")
    private var monitor: Any?
    private var isRecording = false
    /// Keeps each control's callback alive while its content is shown.
    private var targets: [ActionTarget] = []
    private var loginCheckbox: NSButton?

    init(apply: @escaping (Shortcut) -> String?) {
        self.apply = apply
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "SnapSack Settings"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        buildContent(in: window)
    }

    required init?(coder: NSCoder) {
        fatalError("SettingsWindow is built in code only")
    }

    func show() {
        loginCheckbox?.state = LoginItem.isEnabled ? .on : .off
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Layout

    private func buildContent(in window: NSWindow) {
        targets.removeAll()
        let content = NSView()
        window.contentView = content

        let tabs = NSTabView()
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.addTabViewItem(tabItem("General", generalPage()))
        tabs.addTabViewItem(tabItem("Controls", controlsPage()))
        tabs.addTabViewItem(tabItem("Animation", animationPage()))

        let reset = NSButton(title: "Reset All to Defaults", target: nil, action: nil)
        reset.translatesAutoresizingMaskIntoConstraints = false
        wire(reset) { [weak self] in self?.resetEverything() }

        let version = NSTextField(labelWithString: AppVersion.text)
        version.font = .systemFont(ofSize: 11)
        version.textColor = .secondaryLabelColor
        version.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(version)

        content.addSubview(tabs)
        content.addSubview(reset)
        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            tabs.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            tabs.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            tabs.bottomAnchor.constraint(equalTo: reset.topAnchor, constant: -10),
            reset.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            reset.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            version.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            version.centerYAnchor.constraint(equalTo: reset.centerYAnchor),
        ])
        refresh()
    }

    private func rebuild(message: String) {
        guard let window else { return }
        buildContent(in: window)
        messageLabel.stringValue = message
    }

    private func tabItem(_ title: String, _ view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        item.view = view
        return item
    }

    /// A tab's page: its rows stacked from the top, with a margin.
    private func page(_ rows: [NSView]) -> NSView {
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 24, bottom: 18, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let view = NSView()
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
        ])
        return view
    }

    /// Rows of "label — control". A nil label leaves the left column empty, for checkboxes and captions.
    private func form(_ rows: [(String?, NSView)]) -> NSGridView {
        let grid = NSGridView(numberOfColumns: 2, rows: 0)
        grid.rowSpacing = 12
        grid.columnSpacing = 14
        for (title, view) in rows {
            let left: NSView
            if let title {
                left = NSTextField(labelWithString: title)
            } else {
                left = NSGridCell.emptyContentView
            }
            grid.addRow(with: [left, view])
        }
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        return grid
    }

    private func checkbox(_ title: String, on: Bool, _ change: @escaping (Bool) -> Void) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        button.state = on ? .on : .off
        wire(button) { change(button.state == .on) }
        return button
    }

    private func popup<T: Equatable>(
        _ cases: [T],
        title: (T) -> String,
        selected: T,
        _ change: @escaping (T) -> Void
    ) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        for option in cases { button.addItem(withTitle: title(option)) }
        if let index = cases.firstIndex(of: selected) { button.selectItem(at: index) }
        wire(button) {
            let index = button.indexOfSelectedItem
            guard cases.indices.contains(index) else { return }
            change(cases[index])
        }
        return button
    }

    private func caption(_ text: String, width: CGFloat = 300) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = width
        return label
    }

    private func wire(_ control: NSControl, _ action: @escaping () -> Void) {
        let target = ActionTarget(action)
        targets.append(target)
        control.target = target
        control.action = #selector(ActionTarget.fire(_:))
    }

    // MARK: - Tabs

    private func generalPage() -> NSView {
        let heading = NSTextField(labelWithString: "Screenshot shortcut")
        heading.font = .boldSystemFont(ofSize: 13)

        currentLabel = NSTextField(labelWithString: "")
        currentLabel.font = .monospacedSystemFont(ofSize: 26, weight: .medium)

        recordButton = NSButton(title: "Record…", target: nil, action: nil)
        wire(recordButton) { [weak self] in self?.toggleRecording() }
        resetShortcutButton = NSButton(title: "Reset to Default", target: nil, action: nil)
        wire(resetShortcutButton) { [weak self] in self?.resetShortcut() }
        let buttons = NSStackView(views: [recordButton, resetShortcutButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        messageLabel = caption("", width: 400)
        messageLabel.font = .systemFont(ofSize: 11)

        let login = checkbox("Open at login", on: LoginItem.isEnabled) { [weak self] on in
            self?.setLoginItem(on)
        }
        loginCheckbox = login

        let clipboard = checkbox("Put my clipboard back after pasting", on: Settings.shared.restoreClipboard) {
            Settings.shared.restoreClipboard = $0
        }
        let keep = popup([1, 7, 30], title: { $0 == 1 ? "1 day" : "\($0) days" }, selected: Settings.shared.dropsKeepDays) {
            Settings.shared.dropsKeepDays = $0
        }

        return page([
            heading,
            currentLabel,
            buttons,
            messageLabel,
            form([
                (nil, clipboard),
                ("Keep dropped files", keep),
                (nil, login),
            ]),
        ])
    }

    private func controlsPage() -> NSView {
        let settings = Settings.shared
        escapeCaption = caption(settings.escapeAction.caption)

        let escape = popup(EscapeAction.allCases, title: { $0.title }, selected: settings.escapeAction) { [weak self] action in
            Settings.shared.escapeAction = action
            self?.escapeCaption.stringValue = action.caption
        }
        let sensitivity = popup(ShakeSensitivity.allCases, title: { $0.title }, selected: settings.shakeSensitivity) {
            Settings.shared.shakeSensitivity = $0
        }
        sensitivity.isEnabled = settings.shakeToToss
        let shake = checkbox("Shake to toss", on: settings.shakeToToss) { on in
            Settings.shared.shakeToToss = on
            sensitivity.isEnabled = on
        }
        let maxCards = popup([4, 5, 6, 7, 8], title: { "\($0)" }, selected: settings.maxCards) {
            Settings.shared.maxCards = $0
        }
        let size = popup(CardSize.allCases, title: { $0.title }, selected: settings.cardSize) {
            Settings.shared.cardSize = $0
        }

        return page([
            form([
                ("When I press Esc", escape),
                (nil, escapeCaption),
                (nil, shake),
                ("Shake sensitivity", sensitivity),
                ("Screenshots in hand", maxCards),
                ("Card size", size),
                ("Distance from cursor", popup(FollowDistance.allCases, title: { $0.title }, selected: settings.followDistance) {
                    Settings.shared.followDistance = $0
                }),
            ]),
        ])
    }

    private func animationPage() -> NSView {
        let settings = Settings.shared
        let animate = checkbox("Animate cards", on: settings.animationsEnabled) { Settings.shared.animationsEnabled = $0 }
        let reduce = popup(ReduceMotionSetting.allCases, title: { $0.title }, selected: settings.reduceMotion) {
            Settings.shared.reduceMotion = $0
        }
        let speed = popup([0.5, 1.0, 1.5, 2.0], title: { $0 == 1 ? "Normal" : String(format: "%g×", $0) }, selected: settings.motionSpeed) {
            Settings.shared.motionSpeed = $0
        }
        let tilt = popup(TiltSetting.allCases, title: { $0.title }, selected: settings.tilt) { Settings.shared.tilt = $0 }
        let hover = checkbox("Lift the card under the pointer in the fan", on: settings.fanHoverLift) {
            Settings.shared.fanHoverLift = $0
        }

        return page([
            form([
                (nil, animate),
                ("Reduce motion", reduce),
                ("Speed", speed),
                ("Tilt", tilt),
                (nil, hover),
            ]),
        ])
    }

    // MARK: - Login item

    private func setLoginItem(_ on: Bool) {
        do {
            try LoginItem.set(on)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't change the login item"
            NSApp.activate()
            alert.runModal()
        }
        // Show what actually happened, which may differ if the change failed.
        loginCheckbox?.state = LoginItem.isEnabled ? .on : .off
    }

    // MARK: - Reset

    private func resetEverything() {
        Settings.shared.resetAll()
        let message = apply(.standard) ?? "Everything is back to the defaults."
        // Rebuild after this click has finished, so the button that was pressed isn't torn down mid-action.
        Task { @MainActor [weak self] in self?.rebuild(message: message) }
    }

    // MARK: - Shortcut recording

    private func refresh() {
        currentLabel.stringValue = Shortcut.current.display
        recordButton.title = isRecording ? "Press a shortcut…" : "Record…"
        resetShortcutButton.isEnabled = !isRecording && Shortcut.current != .standard
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
            return
        }
        isRecording = true
        messageLabel.stringValue = "Press the new shortcut. It needs ⌘, ⌃ or ⌥. Esc cancels."
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let press = KeyPress(event)
            // Swallow the key press while recording: it's the new shortcut, not something to type.
            let swallow = MainActor.assumeIsolated { self?.handle(press) ?? false }
            return swallow ? nil : event
        }
        refresh()
    }

    /// Returns true when the key press was used by the recorder, so it shouldn't reach the window.
    private func handle(_ press: KeyPress) -> Bool {
        let hasCommandKey = !press.modifiers.intersection([.command, .control, .option]).isEmpty

        if Int(press.keyCode) == kVK_Escape && !hasCommandKey {
            stopRecording()
            messageLabel.stringValue = ""
            return true
        }
        guard let shortcut = Shortcut(press: press) else {
            messageLabel.stringValue = "Add ⌘, ⌃ or ⌥ to the key. Esc cancels."
            return true
        }

        stopRecording()
        messageLabel.stringValue = apply(shortcut) ?? "Saved. Press \(shortcut.display) to take a screenshot."
        refresh()
        return true
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        refresh()
    }

    private func resetShortcut() {
        messageLabel.stringValue = apply(.standard) ?? "Back to ⌃⌥S."
        refresh()
    }

    // MARK: - Window

    func windowWillClose(_ notification: Notification) {
        if isRecording { stopRecording() }
    }
}

/// Passes a control's action to a closure.
@MainActor
private final class ActionTarget: NSObject {
    private let run: () -> Void

    init(_ run: @escaping () -> Void) {
        self.run = run
    }

    @objc func fire(_ sender: Any?) {
        run()
    }
}
