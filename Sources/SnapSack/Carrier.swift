import AppKit

/// The whole interaction, start to finish:
///
///  ⌃⌥S            pick a region; it joins your hand (up to 8) and hangs off the cursor
///  double-click   one card floats to the click and pastes; several fan out so you can pick
///  click a card   in the fan: that card floats to the field and pastes, the rest go back on the cursor
///  1–8            in the fan: picks that numbered card, the same as clicking it
///  Esc            set in Settings: put away the newest, clear the hand, close the fan, or pass through
///  ⌘Z             puts the last dropped or tossed screenshots back in hand
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
    /// The screenshots from the last drop or toss, oldest first, so undo can put them back.
    private var lastRemoved: [Data] = []

    var canUndo: Bool { !lastRemoved.isEmpty }

    init() {
        hand.onShake = { [weak self] in self?.tossAll() }
        tap.onDoubleClick = { [weak self] in self?.doubleClicked() }
        tap.onFanClick = { [weak self] in self?.fanClicked() }
        tap.onFanDigit = { [weak self] digit in self?.pickByNumber(digit) }
        tap.onEscape = { [weak self] in self?.escaped() }
        tap.escapeHandled = { [weak self] in self?.escapeHasWork() ?? false }
        tap.onUndo = { [weak self] in self?.undoLast() ?? false }
        tap.classify = { [weak self] point in self?.classifyDoubleClick(at: point) ?? true }
        tap.onFanPress = { [weak self] in self?.hand.beginFanPress(at: NSEvent.mouseLocation) }
        tap.onFanDragStart = { [weak self] in self?.dragStarted() }
        tap.onFanDrop = { [weak self] in self?.fanDropped() }
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
        Sounds.play(.capture)
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
            hand.flyNewest(to: landing) { [weak self] png in
                dropper.deliver(png: png, to: target)
                self?.remember([png])
            }
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
        hand.fanClick(at: NSEvent.mouseLocation, landing: fanLanding) { [weak self] png in
            dropper.deliver(png: png, to: target)
            self?.remember([png])
        }
        tap.fanMode = hand.isFanned
        if hand.isEmpty { tap.stopAfterPendingMouseUp() }
    }

    /// A number key in the fan picks that card, the same as clicking it.
    private func pickByNumber(_ digit: Int) {
        guard hand.isFanned, digit >= 1, digit <= hand.count else { return }
        let dropper = self.dropper
        let target = fanDrop
        hand.pickFanned(at: digit - 1, landing: fanLanding) { [weak self] png in
            dropper.deliver(png: png, to: target)
            self?.remember([png])
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

    // MARK: - Esc

    /// Whether Esc has anything to do right now. When it doesn't, ClickTap lets it through to the app.
    private func escapeHasWork() -> Bool {
        if hand.isDraggingFan { return Settings.shared.escapeAction != .passThrough }
        switch Settings.shared.escapeAction {
        case .passThrough: return false
        case .putAwayNewest, .clearHand: return !hand.isEmpty
        case .closeFanOnly: return hand.isFanned
        }
    }

    private func escaped() {
        // Esc during a drag takes the step back: the card returns to the fan and the fan stays open.
        if hand.isDraggingFan {
            hand.cancelFanDrag()
            tap.fanMode = hand.isFanned
            return
        }
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

    // MARK: - Dragging from the fan

    /// The pointer moved far enough for a drag: the card leaves the fan, and the tap stops treating clicks as fan clicks.
    private func dragStarted() {
        hand.startFanDrag()
        tap.fanMode = hand.isFanned
    }

    /// A fanned card was dragged and let go: it lands wherever the pointer is, not where the fan was opened.
    private func fanDropped() {
        guard hand.isDraggingFan else { return }
        let point = NSEvent.mouseLocation
        let cgPoint = Dropper.coreGraphicsPoint(point)
        let target = FinderDrop.folderItem(at: cgPoint).map { FinderDrop.Target.folder($0) } ?? FinderDrop.target(at: cgPoint)
        let dropper = self.dropper
        hand.dropFanDrag { [weak self] png in
            dropper.deliver(png: png, to: target, clickAt: point)
            self?.remember([png])
        }
        tap.fanMode = hand.isFanned
        if hand.isEmpty { tap.stopAfterPendingMouseUp() }
    }

    // MARK: - Toss and undo

    private func tossAll() {
        if !hand.isEmpty { Sounds.play(.toss) }
        remember(hand.pngsInHand)
        hand.tossAll()
        tap.stop()
    }

    private func remember(_ pngs: [Data]) {
        guard !pngs.isEmpty else { return }
        lastRemoved = pngs
    }

    /// Puts the last dropped or tossed screenshots back in hand, starting to hold again if nothing is held.
    /// It can't take back a paste that already landed in another app, and a file saved to a folder stays there.
    @discardableResult
    func undoLast() -> Bool {
        guard !lastRemoved.isEmpty, !isCapturing, !hand.isFanned else { return false }
        guard tap.start() else {
            Permissions.requestAccessibility()
            return false
        }
        let pngs = lastRemoved
        lastRemoved = []
        for png in pngs {
            if let image = NSImage(data: png) { hand.add(image: image, png: png) }
        }
        return true
    }
}
