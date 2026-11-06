import AppKit
import Carbon.HIToolbox

/// The settings window. The one setting is the screenshot shortcut: click Record, then press the new combination.
@MainActor
final class SettingsWindow: NSWindowController, NSWindowDelegate {
    /// Tries to make `shortcut` the active one. Returns an error message, or nil on success.
    private let apply: (Shortcut) -> String?

    private let currentLabel = NSTextField(labelWithString: "")
    private let recordButton = NSButton(title: "Record…", target: nil, action: nil)
    private let resetButton = NSButton(title: "Reset to Default", target: nil, action: nil)
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private var monitor: Any?
    private var isRecording = false

    init(apply: @escaping (Shortcut) -> String?) {
        self.apply = apply
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 210),
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
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("SettingsWindow is built in code only")
    }

    func show() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Layout

    private func buildContent(in window: NSWindow) {
        let content = NSView()
        window.contentView = content

        let heading = NSTextField(labelWithString: "Screenshot shortcut")
        heading.font = .boldSystemFont(ofSize: 13)

        currentLabel.font = .monospacedSystemFont(ofSize: 26, weight: .medium)

        recordButton.target = self
        recordButton.action = #selector(toggleRecording)
        resetButton.target = self
        resetButton.action = #selector(resetToDefault)

        let buttons = NSStackView(views: [recordButton, resetButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        messageLabel.font = .systemFont(ofSize: 11)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.preferredMaxLayoutWidth = 332

        let stack = NSStackView(views: [heading, currentLabel, buttons, messageLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
        ])
    }

    private func refresh() {
        currentLabel.stringValue = Shortcut.current.display
        recordButton.title = isRecording ? "Press a shortcut…" : "Record…"
        resetButton.isEnabled = !isRecording && Shortcut.current != .standard
    }

    // MARK: - Recording

    @objc private func toggleRecording() {
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

    @objc private func resetToDefault() {
        messageLabel.stringValue = apply(.standard) ?? "Back to ⌃⌥S."
        refresh()
    }

    // MARK: - Window

    func windowWillClose(_ notification: Notification) {
        if isRecording { stopRecording() }
    }
}
