import AppKit

// MARK: - Choices

/// What Esc does while you're holding screenshots.
enum EscapeAction: String, CaseIterable {
    case putAwayNewest, clearHand, closeFanOnly, passThrough

    var title: String {
        switch self {
        case .putAwayNewest: return "Put away the newest"
        case .clearHand: return "Clear the whole hand"
        case .closeFanOnly: return "Close the fan only"
        case .passThrough: return "Pass through to the app"
        }
    }

    var caption: String {
        switch self {
        case .putAwayNewest: return "Puts away the newest screenshot. If the fan is open, Esc closes it first."
        case .clearHand: return "Puts away every screenshot in your hand at once."
        case .closeFanOnly: return "Closes the fan and puts the screenshots back on the cursor. Otherwise Esc does nothing."
        case .passThrough: return "SnapSack ignores Esc, so the app you're in gets it as usual. Your screenshots stay in hand."
        }
    }
}

enum ShakeSensitivity: String, CaseIterable {
    case low, medium, high

    var title: String {
        switch self {
        case .low: return "Low (firm shake)"
        case .medium: return "Medium"
        case .high: return "High (light shake)"
        }
    }

    /// How far a stroke must travel, in points, to count.
    var minTravel: CGFloat {
        switch self {
        case .low: return 80
        case .medium: return 55
        case .high: return 40
        }
    }

    /// How many direction changes make a shake.
    var reversalsNeeded: Int {
        switch self {
        case .low: return 5
        case .medium: return 4
        case .high: return 3
        }
    }

    /// All the direction changes must land inside this many seconds.
    var window: TimeInterval {
        switch self {
        case .low, .medium: return 0.65
        case .high: return 0.8
        }
    }
}

enum ReduceMotionSetting: String, CaseIterable {
    case system, on, off

    var title: String {
        switch self {
        case .system: return "Match macOS"
        case .on: return "Always reduce"
        case .off: return "Never reduce"
        }
    }
}

enum TiltSetting: String, CaseIterable {
    case off, subtle, full

    var title: String {
        switch self {
        case .off: return "Off"
        case .subtle: return "Subtle"
        case .full: return "Full"
        }
    }

    /// Scales how far cards lean and fan out.
    var factor: CGFloat {
        switch self {
        case .off: return 0
        case .subtle: return 0.4
        case .full: return 1
        }
    }
}

enum CardSize: String, CaseIterable {
    case small, medium, large

    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    /// The area every thumbnail covers, in square points.
    var area: CGFloat {
        switch self {
        case .small: return 4_000
        case .medium: return 5_760
        case .large: return 8_000
        }
    }
}

/// How far cards hang from the cursor.
enum FollowDistance: String, CaseIterable {
    case close, medium, far

    var title: String {
        switch self {
        case .close: return "Close"
        case .medium: return "Medium"
        case .far: return "Far"
        }
    }

    /// Scales the gap between the pointer and the cards.
    var factor: CGFloat {
        switch self {
        case .close: return 1
        case .medium: return 2.2
        case .far: return 3.5
        }
    }
}

// MARK: - Store

/// Everything the user can change. Saved in UserDefaults and read live by the code that uses it,
/// so a change takes effect straight away.
@MainActor
final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    var escapeAction: EscapeAction {
        didSet { defaults.set(escapeAction.rawValue, forKey: "escapeAction") }
    }
    var shakeToToss: Bool {
        didSet { defaults.set(shakeToToss, forKey: "shakeToToss") }
    }
    var shakeSensitivity: ShakeSensitivity {
        didSet { defaults.set(shakeSensitivity.rawValue, forKey: "shakeSensitivity") }
    }
    var maxCards: Int {
        didSet { defaults.set(maxCards, forKey: "maxCards") }
    }
    var cardSize: CardSize {
        didSet { defaults.set(cardSize.rawValue, forKey: "cardSize") }
    }
    var animationsEnabled: Bool {
        didSet { defaults.set(animationsEnabled, forKey: "animationsEnabled") }
    }
    var reduceMotion: ReduceMotionSetting {
        didSet { defaults.set(reduceMotion.rawValue, forKey: "reduceMotion") }
    }
    var motionSpeed: Double {
        didSet { defaults.set(motionSpeed, forKey: "motionSpeed") }
    }
    var tilt: TiltSetting {
        didSet { defaults.set(tilt.rawValue, forKey: "tilt") }
    }
    var fanHoverLift: Bool {
        didSet { defaults.set(fanHoverLift, forKey: "fanHoverLift") }
    }
    var restoreClipboard: Bool {
        didSet { defaults.set(restoreClipboard, forKey: "restoreClipboard") }
    }
    var dropsKeepDays: Int {
        didSet { defaults.set(dropsKeepDays, forKey: "dropsKeepDays") }
    }

    var followDistance: FollowDistance {
        didSet { defaults.set(followDistance.rawValue, forKey: "followDistance") }
    }

    private init() {
        escapeAction = Self.choice(UserDefaults.standard, "escapeAction", EscapeAction.putAwayNewest)
        shakeToToss = Self.flag(UserDefaults.standard, "shakeToToss", true)
        shakeSensitivity = Self.choice(UserDefaults.standard, "shakeSensitivity", ShakeSensitivity.medium)
        maxCards = min(max(Self.number(UserDefaults.standard, "maxCards", 8), 4), 8)
        cardSize = Self.choice(UserDefaults.standard, "cardSize", CardSize.medium)
        animationsEnabled = Self.flag(UserDefaults.standard, "animationsEnabled", true)
        reduceMotion = Self.choice(UserDefaults.standard, "reduceMotion", ReduceMotionSetting.system)
        motionSpeed = Self.decimal(UserDefaults.standard, "motionSpeed", 1)
        tilt = Self.choice(UserDefaults.standard, "tilt", TiltSetting.full)
        fanHoverLift = Self.flag(UserDefaults.standard, "fanHoverLift", true)
        restoreClipboard = Self.flag(UserDefaults.standard, "restoreClipboard", true)
        dropsKeepDays = Self.number(UserDefaults.standard, "dropsKeepDays", 7)
        followDistance = Self.choice(UserDefaults.standard, "followDistance", FollowDistance.close)
    }

    /// Puts every choice back to its first-launch value. The shortcut is handled separately, in Shortcut.
    func resetAll() {
        escapeAction = .putAwayNewest
        shakeToToss = true
        shakeSensitivity = .medium
        maxCards = 8
        cardSize = .medium
        animationsEnabled = true
        reduceMotion = .system
        motionSpeed = 1
        tilt = .full
        fanHoverLift = true
        restoreClipboard = true
        dropsKeepDays = 7
        followDistance = .close
    }

    private static func choice<T: RawRepresentable>(_ defaults: UserDefaults, _ key: String, _ fallback: T) -> T
    where T.RawValue == String {
        defaults.string(forKey: key).flatMap { T(rawValue: $0) } ?? fallback
    }

    private static func flag(_ defaults: UserDefaults, _ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    private static func number(_ defaults: UserDefaults, _ key: String, _ fallback: Int) -> Int {
        defaults.object(forKey: key) == nil ? fallback : defaults.integer(forKey: key)
    }

    private static func decimal(_ defaults: UserDefaults, _ key: String, _ fallback: Double) -> Double {
        defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
    }
}

// MARK: - Text that follows the choices

extension Settings {
    /// The menu's hint line, built from the current choices.
    var hintLine: String {
        var parts = ["Double-click drops"]
        if shakeToToss { parts.append("Shake tosses") }
        switch escapeAction {
        case .putAwayNewest: parts.append("Esc puts away")
        case .clearHand: parts.append("Esc clears")
        case .closeFanOnly: parts.append("Esc closes fan")
        case .passThrough: break
        }
        return parts.joined(separator: "  ·  ")
    }

    /// The Esc sentence for the welcome message.
    var escapeSentence: String {
        switch escapeAction {
        case .putAwayNewest: return "Press Esc to put the newest one away."
        case .clearHand: return "Press Esc to clear everything in your hand."
        case .closeFanOnly: return "Press Esc to close the fan."
        case .passThrough: return "Esc goes to your apps as usual, so SnapSack doesn't use it."
        }
    }
}

// MARK: - Version

/// The version from the app's Info.plist, shown at the bottom of Settings.
enum AppVersion {
    static var text: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String
        if let build, build != short { return "Version \(short) (\(build))" }
        return "Version \(short)"
    }
}
