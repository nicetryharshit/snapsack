import Foundation

enum Capture {
    /// Runs the system's own region picker (the same crosshair as ⌘⇧4, so it feels native: Space switches
    /// to window mode, Esc cancels). Calls back on the main thread with PNG data, or nil if cancelled.
    static func selectRegion(completion: @escaping @MainActor (Data?) -> Void) {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapsack-\(UUID().uuidString).png")

        DispatchQueue.global(qos: .userInteractive).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-x", "-o", file.path]   // interactive, silent, no window shadow

            let result: Data?
            do {
                try process.run()
                process.waitUntilExit()
                // No file is written when the user presses Esc.
                result = try? Data(contentsOf: file)
            } catch {
                result = nil
            }
            try? FileManager.default.removeItem(at: file)

            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(result) }
            }
        }
    }
}
