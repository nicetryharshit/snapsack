import AppKit

/// The short sounds SnapSack plays. The files live in Resources/Sounds and bundle.sh copies them into the app.
enum SoundEffect: String {
    case capture
    case drop
    case toss
    case fanOpen = "fan_open"
    case fanClose = "fan_close"
}

/// Plays the sound effects, unless the "Play sounds" setting is off.
@MainActor
enum Sounds {
    private static var cache: [SoundEffect: NSSound] = [:]

    static func play(_ effect: SoundEffect) {
        guard Settings.shared.soundsEnabled, let player = player(for: effect) else { return }
        if player.isPlaying { player.stop() }
        player.play()
    }

    private static func player(for effect: SoundEffect) -> NSSound? {
        if let cached = cache[effect] { return cached }
        guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav", subdirectory: "Sounds"),
              let sound = NSSound(contentsOf: url, byReference: false) else { return nil }
        cache[effect] = sound
        return sound
    }
}
