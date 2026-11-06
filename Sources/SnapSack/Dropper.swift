import AppKit
import CoreGraphics

/// "Dropping" = pasting the screenshot into whatever is under the cursor, then putting your clipboard back.
///
/// The pasteboard item carries both the image data and a file URL. Image-aware apps (Notes, Slack, Docs,
/// Messages, Figma...) take the image; Finder takes the file; a terminal gets the path.
@MainActor
struct Dropper {
    private static let keepDays = 7

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SnapSack/Drops", isDirectory: true)
    }

    /// Removes dropped files older than a week. Nothing is ever filed for you permanently.
    static func pruneOldDrops() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-Double(keepDays) * 86_400)
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff { try? fm.removeItem(at: file) }
        }
    }

    func paste(png: Data) {
        let pasteboard = NSPasteboard.general
        let snapshot = Self.snapshot(of: pasteboard)
        let fileURL = Self.write(png, in: Self.directory)

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let fileURL { item.setString(fileURL.absoluteString, forType: .fileURL) }
        pasteboard.writeObjects([item])
        let ourChange = pasteboard.changeCount

        // Give the second click a beat to settle, then press ⌘V.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 70_000_000)
            Self.pressCommandV()

            // Hand the clipboard back, unless something else has copied in the meantime.
            try? await Task.sleep(nanoseconds: 900_000_000)
            if pasteboard.changeCount == ourChange {
                pasteboard.clearContents()
                if !snapshot.isEmpty { pasteboard.writeObjects(snapshot) }
            }
        }
    }

    /// Saves the screenshot as a file in the folder under a double-click on Finder's background. The clipboard
    /// is never touched, so the screenshot doesn't stay on it.
    func deliver(png: Data, to target: FinderDrop.Target) {
        FinderDrop.log("deliver target=\(target) bytes=\(png.count) hash=\(png.hashValue)")
        switch target {
        case .folder(let folder):
            _ = Self.write(png, in: folder)
        case .frontFinderWindow:
            if let folder = FinderDrop.frontWindowFolder() {
                _ = Self.write(png, in: folder)
            } else {
                paste(png: png)
            }
        case .paste, .leaveAlone:
            paste(png: png)
        }
    }

    private static func snapshot(of pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { original in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    private static func write(_ png: Data, in folder: URL) -> URL? {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = "Screenshot \(formatter.string(from: Date()))"
        var url = folder.appendingPathComponent("\(base).png")
        var n = 2
        while fm.fileExists(atPath: url.path) {          // two shots in the same second
            url = folder.appendingPathComponent("\(base) \(n).png")
            n += 1
        }
        do {
            try png.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func pressCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9   // kVK_ANSI_V
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }
}
