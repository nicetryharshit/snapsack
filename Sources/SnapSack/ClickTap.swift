import CoreGraphics
import Foundation

/// A short-lived event tap that exists only while you're holding screenshots.
///
/// - First click of a double-click passes straight through, so the app under the cursor gets focus and the caret
///   lands where you clicked. The second click is swallowed and becomes "drop".
///   The only check is on a double-click, to see whether it's on Finder's background (see FinderDrop). It has a short
///   Accessibility timeout, because the system disables a tap that answers slowly.
/// - While the fan is open (`fanMode`) every click is swallowed and reported, so nothing underneath is triggered.
/// - Esc is swallowed and handed to Carrier, unless Settings passes it through to the app.
/// - `isPaused` makes the tap transparent (used while the system screenshot crosshair is up, so its Esc still works).
///
/// Because the tap is only alive while holding, SnapSack adds no overhead to normal input.
final class ClickTap: @unchecked Sendable {
    var onDoubleClick: (@MainActor () -> Void)?
    var onFanClick: (@MainActor () -> Void)?
    var onEscape: (@MainActor () -> Void)?
    var onFanDigit: (@MainActor (Int) -> Void)?
    /// Asked on Esc: false means nothing for SnapSack to do, so Esc goes to the app.
    var escapeHandled: (@MainActor () -> Bool)?
    /// Asked on ⌘Z: false means nothing to undo, so ⌘Z goes to the app.
    var onUndo: (@MainActor () -> Bool)?
    /// In the fan: a press, a drag starting, and a release after a drag or after a plain click.
    var onFanPress: (@MainActor () -> Void)?
    var onFanDragStart: (@MainActor () -> Void)?
    var onFanDrop: (@MainActor () -> Void)?
    /// Marks clicks SnapSack sends itself, so this tap lets them through.
    static let syntheticMarker: Int64 = 0x534E4150
    var isPaused = false
    var fanMode = false
    /// Asked on a double-click: false means the click isn't ours, so it passes through to whatever is under it.
    var classify: (@MainActor (CGPoint) -> Bool)?

    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var swallowNextMouseUp = false
    private var stopAfterMouseUp = false
    private var swallowNextEscUp = false
    private var swallowNextDigitUp: Int64?
    private var swallowNextZUp = false
    private var fanPressPoint: CGPoint?
    private var fanDragging = false
    private var generation = 0        // lets a stale safety timer tell it belongs to an earlier session

    @discardableResult
    func start() -> Bool {
        if port != nil { return true }

        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .keyDown, .keyUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: clickTapCallback,
            userInfo: refcon
        ) else { return false }

        self.port = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        generation += 1
        swallowNextMouseUp = false
        stopAfterMouseUp = false
        swallowNextEscUp = false
        swallowNextDigitUp = nil
        swallowNextZUp = false
        fanPressPoint = nil
        fanDragging = false
        fanMode = false
        return true
    }

    /// Stops right now.
    func stop() {
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        port = nil
        source = nil
        swallowNextMouseUp = false
        stopAfterMouseUp = false
        fanMode = false
    }

    /// Stops once the swallowed second click has been released, so the app never sees an orphan mouse-up.
    func stopAfterPendingMouseUp() {
        if swallowNextMouseUp {
            stopAfterMouseUp = true
            // Safety net in case the mouse-up never arrives.
            let owner = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, self.generation == owner else { return }
                self.stop()
            }
        } else {
            stop()
        }
    }

    /// The number a key stands for, on the top row: 1 to 8.
    private static func digit(forKeyCode code: Int64) -> Int? {
        switch code {
        case 18: return 1
        case 19: return 2
        case 20: return 3
        case 21: return 4
        case 23: return 5
        case 22: return 6
        case 26: return 7
        case 28: return 8
        default: return nil
        }
    }

    private func fire(_ handler: (@MainActor () -> Void)?) {
        guard let handler else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated { handler() }
        }
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == ClickTap.syntheticMarker { return Unmanaged.passUnretained(event) }
        if isPaused { return Unmanaged.passUnretained(event) }

        switch type {
        case .leftMouseDown:
            if fanMode {
                swallowNextMouseUp = true
                fanPressPoint = event.location
                fanDragging = false
                fire(onFanPress)
                return nil
            }
            if event.getIntegerValueField(.mouseEventClickState) >= 2 {
                if let classify, !MainActor.assumeIsolated({ classify(event.location) }) {
                    return Unmanaged.passUnretained(event)   // a folder icon, say: Finder keeps its double-click
                }
                swallowNextMouseUp = true
                fire(onDoubleClick)
                return nil
            }
            return Unmanaged.passUnretained(event)

        case .leftMouseUp:
            if swallowNextMouseUp {
                swallowNextMouseUp = false
                if fanPressPoint != nil {
                    let dragged = fanDragging
                    fanPressPoint = nil
                    fanDragging = false
                    fire(dragged ? onFanDrop : onFanClick)
                }
                if stopAfterMouseUp {
                    stopAfterMouseUp = false
                    DispatchQueue.main.async { [weak self] in self?.stop() }
                }
                return nil
            }
            return Unmanaged.passUnretained(event)

        case .leftMouseDragged:
            guard fanMode, let press = fanPressPoint else { return Unmanaged.passUnretained(event) }
            let moved = hypot(event.location.x - press.x, event.location.y - press.y)
            if !fanDragging, moved > 4 {
                fanDragging = true
                fire(onFanDragStart)
            }
            return nil

        case .rightMouseDown, .rightMouseUp:
            return fanMode ? nil : Unmanaged.passUnretained(event)

        case .keyDown:
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            if key == 53, MainActor.assumeIsolated({ escapeHandled?() ?? false }) {   // Esc, when SnapSack has something for it
                swallowNextEscUp = true
                fire(onEscape)
                return nil
            }
            // Plain digits only: ⌘1 and friends belong to the app in front.
            if fanMode, event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty,
               let digit = Self.digit(forKeyCode: key) {
                swallowNextDigitUp = key
                let handler = onFanDigit
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if let handler { handler(digit) }
                    }
                }
                return nil
            }
            // Exactly ⌘Z: ⇧⌘Z (redo) and other combinations go to the app in front.
            if key == 6, event.flags.intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate]) == .maskCommand,
               MainActor.assumeIsolated({ onUndo?() ?? false }) {   // ⌘Z
                swallowNextZUp = true
                return nil
            }
            return Unmanaged.passUnretained(event)

        case .keyUp:
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            if swallowNextEscUp, key == 53 {
                swallowNextEscUp = false
                return nil
            }
            if let digitKey = swallowNextDigitUp, key == digitKey {
                swallowNextDigitUp = nil
                return nil
            }
            if swallowNextZUp, key == 6 {
                swallowNextZUp = false
                return nil
            }
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }
}

private func clickTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<ClickTap>.fromOpaque(refcon).takeUnretainedValue()
    return tap.handle(type: type, event: event)
}
