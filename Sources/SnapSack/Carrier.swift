import AppKit

/// The whole interaction, start to finish:
///
///  ⌃⌥S         pick a region; it joins your hand (up to 8) and hangs off the cursor
///  double-click   one card floats to the click and pastes; several fan out so you can pick
///  click a card   in the fan: that card floats to the field and pastes, the rest go back on the cursor
///  Esc            closes the fan, or puts away the newest card
///  shake          lets the whole hand go
@MainActor
final class Carrier {
    private let hand = Hand()
    private let tap = ClickTap()
    private let dropper = Dropper()
    private var isCapturing = false
    private var fanLanding = CGPoint.zero      // where the double-click happened: where the pick will land
    private var pendingDrop: FinderDrop.Target = .paste   // decided on the double-click, used when the card lands
    private var fanDrop: FinderDrop.Target = .paste       // the same, kept while the fan is open

    init() {
        hand.onShake = { [weak self] in self?.tossAll() }
        tap.onDoubleClick = { [weak self] in self?.doubleClicked() }
        tap.onFanClick = { [weak self] in self?.fanClicked() }
        tap.onEscape = { [weak self] in self?.escaped() }
        tap.classify = { [weak self] point in self?.classifyDoubleClick(at: point) ?? true }
    }

    // MARK: - Capturing

    /// The hotkey: add another screenshot to your hand.
    func begin() {
        guard !isCapturing, !hand.isFanned else { return }
        guard Permissions.accessibilityGranted else {
            Permissions.requestAccessibility()
            return
        }
        guard Permissions.screenRecordingGranted else {
            Permissions.requestScreenRecording()
            return
        }

        isCapturing = true
        tap.isPaused = true          // the crosshair needs its own Esc
        hand.suspend()               // and the hand mustn't appear in the shot

        Task { @MainActor [self] in
            try? await Task.sleep(nanoseconds: 80_000_000)   // let the hand's windows disappear first
            Capture.selectRegion { [weak self] data in
                self?.finishCapture(data)
            }
        }
    }

    private func finishCapture(_ data: Data?) {
        isCapturing = false
        hand.resume()
        tap.isPaused = false

        guard let data, !data.isEmpty, let image = NSImage(data: data) else { return }
        guard tap.start() else {
            Permissions.requestAccessibility()
            return
        }
        hand.add(image: image, png: data)
    }

    // MARK: - Using the hand

    private func doubleClicked() {
        let landing = NSEvent.mouseLocation
        switch hand.count {
        case 0:
            return
        case 1:
            // One card: it floats to where you clicked, and the drop fires when it lands.
            let dropper = self.dropper
            let target = pendingDrop
            hand.flyNewest(to: landing) { png in dropper.deliver(png: png, to: target) }
            tap.stopAfterPendingMouseUp()
        default:
            // Several: spread them out, hold them, and let the next click choose.
            fanLanding = landing
            fanDrop = pendingDrop
            hand.openFan(at: landing)
            tap.fanMode = hand.isFanned
        }
    }

    private func fanClicked() {
        guard hand.isFanned else {
            tap.fanMode = false
            return
        }
        let dropper = self.dropper
        let target = fanDrop
        FinderDrop.log("fan click cards=\(hand.count)")
        hand.fanClick(at: NSEvent.mouseLocation, landing: fanLanding) { png in
            dropper.deliver(png: png, to: target)
        }
        tap.fanMode = hand.isFanned
        if hand.isEmpty { tap.stopAfterPendingMouseUp() }
    }

    /// Called on the double-click, before the tap decides whether to swallow it. Returns false when the click is on
    /// something Finder should handle itself, such as a folder icon.
    private func classifyDoubleClick(at point: CGPoint) -> Bool {
        // Nothing in hand means nothing to drop: never swallow a double-click for that.
        guard !hand.isEmpty else { return false }
        pendingDrop = FinderDrop.target(at: point)
        return pendingDrop != .leaveAlone
    }

    private func escaped() {
        switch Settings.shared.escapeAction {
        case .passThrough:
            // ClickTap lets Esc reach the app, so this isn't reached. It's here to keep the switch complete.
            return
        case .putAwayNewest:
            if hand.isFanned {
                hand.closeFan()
                tap.fanMode = false
                return
            }
            hand.removeNewest()
            if hand.isEmpty { tap.stop() }
        case .clearHand:
            hand.clearAll()
            tap.stop()
        case .closeFanOnly:
            guard hand.isFanned else { return }
            hand.closeFan()
            tap.fanMode = false
        }
    }

    private func tossAll() {
        hand.tossAll()
        tap.stop()
    }
}
