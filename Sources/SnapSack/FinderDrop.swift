import AppKit
import ApplicationServices

/// What a double-click means when the pointer is over Finder.
///
/// - An empty spot in a folder window, or on the desktop, saves the screenshot into that folder as a file.
/// - A file or folder icon is left alone, so Finder can open it and the screenshot stays on the cursor.
/// - Anywhere else, nothing changes: the screenshot is pasted into whatever is under the cursor.
///
/// This uses Accessibility, which SnapSack already needs. Every Finder decision is appended to
/// `finder-probe.log` in Application Support/SnapSack, so the role guesses below can be checked on a real Mac.
@MainActor
enum FinderDrop {
    enum Target: Equatable {
        case paste
        case folder(URL)            // a known folder: the desktop
        case frontFinderWindow      // the folder the front Finder window shows, asked of Finder when dropping
        case leaveAlone
    }

    /// Roles that count as the empty background of a folder window or the desktop, rather than an item on it.
    /// In list view the empty space below the rows is the outline itself.
    private static let backgroundRoles: Set<String> = [
        "AXWindow", "AXScrollArea", "AXSplitGroup", "AXGroup", "AXLayoutArea", "AXOutline", "AXDesktop",
    ]

    /// Called on the double-click, inside the event tap, so it has to answer quickly. The Accessibility timeout
    /// keeps a slow app from holding the tap up.
    static func target(at point: CGPoint) -> Target {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.12)

        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &found) == .success,
              let element = found else { return .paste }

        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first,
              finder.processIdentifier == pid else { return .paste }

        let role = attribute(element, "AXRole") ?? "?"
        let window = ancestor(of: element, withRole: "AXWindow")
        let decision: Target

        if let window {
            // Finder doesn't expose a folder window's path through Accessibility, so the folder is asked of Finder
            // when the screenshot lands. Only the background is ours; rows and icons stay with Finder.
            let title = attribute(window, "AXTitle") ?? "-"
            decision = backgroundRoles.contains(role) ? .frontFinderWindow : .leaveAlone
            log("role=\(role) window=\(title) decision=\(decision)")
        } else {
            let desktop = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop", isDirectory: true)
            decision = backgroundRoles.contains(role) ? .folder(desktop) : .leaveAlone
            log("role=\(role) window=none decision=\(decision)")
        }
        return decision
    }

    /// For a drop (not a double-click): the folder under the point, so the screenshot goes inside it. Finder exposes
    /// an item's file URL through Accessibility; this checks the item and its parent. Returns nil for files and
    /// anything that isn't a folder, which leaves those drops to the normal paste.
    static func folderItem(at point: CGPoint) -> URL? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.12)

        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &found) == .success,
              let first = found else { return nil }

        var pid: pid_t = 0
        AXUIElementGetPid(first, &pid)
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first,
              finder.processIdentifier == pid else { return nil }

        var element = first
        for _ in 0..<2 {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, "AXURL" as CFString, &value) == .success,
               let url = value as? URL {
                let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                log("drop item url=\(url.lastPathComponent) folder=\(isFolder)")
                return isFolder ? url : nil
            }
            guard let next = parent(of: element) else { break }
            element = next
        }
        log("drop item has no url")
        return nil
    }

    /// The folder the front Finder window shows, asked of Finder itself. Runs when the screenshot lands, not inside
    /// the event tap. Returns nil if Finder has no window open, or if the permission is refused.
    static func frontWindowFolder() -> URL? {
        let source = "tell application \"Finder\" to get POSIX path of (target of front Finder window as alias)"
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error),
              let path = result.stringValue else {
            log("front window folder unavailable: \(error?.description ?? "no result")")
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    // MARK: - Accessibility helpers

    private static func attribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXParent" as CFString, &value) == .success,
              let found = value, CFGetTypeID(found) == AXUIElementGetTypeID() else { return nil }
        return (found as! AXUIElement)
    }

    private static func ancestor(of element: AXUIElement, withRole role: String) -> AXUIElement? {
        var current = element
        for _ in 0..<30 {
            guard let next = parent(of: current) else { return nil }
            if attribute(next, "AXRole") == role { return next }
            current = next
        }
        return nil
    }

    // MARK: - Probe log

    static func log(_ message: String) {
        let file = Dropper.directory.deletingLastPathComponent().appendingPathComponent("finder-probe.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: file) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: file)
        }
    }
}
