import Carbon.HIToolbox
import Foundation

/// A global hotkey via Carbon's RegisterEventHotKey. Unlike an event monitor it needs no
/// Input Monitoring permission, and the key press is consumed instead of leaking to the front app.
///
/// Dropping the last reference unregisters the key, so a shortcut can be replaced by releasing the old one first.
final class HotKey {
    private static var nextID: UInt32 = 1
    /// Weak, so the registry never keeps a hotkey alive: that's what lets `deinit` unregister it.
    private static var registry: [UInt32: WeakHotKey] = [:]
    private static var handlerInstalled = false

    private let id: UInt32
    private var ref: EventHotKeyRef?
    private let action: @MainActor () -> Void

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) {
        self.id = HotKey.nextID
        self.action = action
        HotKey.nextID += 1
        HotKey.installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: OSType(0x534E534B), id: id)   // 'SNSK'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return nil }
        HotKey.registry[id] = WeakHotKey(self)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        HotKey.registry[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                let id = hotKeyID.id
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { HotKey.registry[id]?.value?.action() }
                }
                return noErr
            },
            1,
            &spec,
            nil,
            nil
        )
    }
}

private final class WeakHotKey {
    weak var value: HotKey?
    init(_ value: HotKey) { self.value = value }
}
