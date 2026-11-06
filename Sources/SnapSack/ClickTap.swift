import CoreGraphics
import Foundation

/// A short-lived event tap that exists only while you're holding screenshots.
///
/// - First click of a double-click passes straight through, so the app under the cursor gets focus and the caret
///   lands where you clicked. The second click is swallowed and becomes "drop".
///   No checks happen inside this callback: the system disables a tap that answers slowly, and that is what made
///   double-clicks miss.
/// - While the fan is open (`fanMode`) every click is swallowed and reported, so nothing underneath is triggered.
/// - Esc is swallowed and becomes "put it away".
/// - `isPaused` makes the tap transparent (used while the system screenshot crosshair is up, so its Esc still works).
///
/// Because the tap is only alive while holding, SnapSack adds no overhead to normal input.
final class ClickTap: @unchecked Sendable {
    var onDoubleClick: (@MainActor () -> Void)?
    var onFanClick: (@MainActor () -> Void)?
    var onEscape: (@MainActor () -> Void)?
    var isPaused = false
    var fanMode = false

    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var swallowNextMouseUp = false
    private var stopAfterMouseUp = false
    private var swallowNextEscUp = false
    private var generation = 0        // lets a stale safety timer tell it belongs to an earlier session

    @discardableResult
    func start() -> Bool {
        if port != nil { return true }

        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .keyDown, .keyUp]
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
        if isPaused { return Unmanaged.passUnretained(event) }

        switch type {
        case .leftMouseDown:
            if fanMode {
                swallowNextMouseUp = true
                fire(onFanClick)
                return nil
            }
            if event.getIntegerValueField(.mouseEventClickState) >= 2 {
                swallowNextMouseUp = true
                fire(onDoubleClick)
                return nil
            }
            return Unmanaged.passUnretained(event)

        case .leftMouseUp:
            if swallowNextMouseUp {
                swallowNextMouseUp = false
                if stopAfterMouseUp {
                    stopAfterMouseUp = false
                    DispatchQueue.main.async { [weak self] in self?.stop() }
                }
                return nil
            }
            return Unmanaged.passUnretained(event)

        case .rightMouseDown, .rightMouseUp:
            return fanMode ? nil : Unmanaged.passUnretained(event)

        case .keyDown:
            if event.getIntegerValueField(.keyboardEventKeycode) == 53 {   // Esc
                swallowNextEscUp = true
                fire(onEscape)
                return nil
            }
            return Unmanaged.passUnretained(event)

        case .keyUp:
            if swallowNextEscUp, event.getIntegerValueField(.keyboardEventKeycode) == 53 {
                swallowNextEscUp = false
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
