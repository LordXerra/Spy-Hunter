import CoreGraphics
import Foundation

/// Skill level, chosen on the title screen before play.
enum Difficulty: Int, CaseIterable {
    case novice = 0
    case normal = 1
    case expert = 2

    var name: String {
        switch self {
        case .novice: return "NOVICE"
        case .normal: return "NORMAL"
        case .expert: return "EXPERT"
        }
    }

    /// Points needed for each extra car once the opening timer has expired.
    var extraCarInterval: Int {
        switch self {
        case .novice: return 10_000
        case .normal: return 15_000
        case .expert: return 20_000
        }
    }

    /// Multiplier on how quickly the pressure ramps with distance.
    var ramp: CGFloat {
        switch self {
        case .novice: return 1.0
        case .normal: return 1.3
        case .expert: return 1.6
        }
    }

    /// Mad Bombers permitted in the air at once.
    var helicopterCap: Int {
        self == .expert ? 2 : 1
    }

    var next: Difficulty {
        Difficulty(rawValue: (rawValue + 1) % Difficulty.allCases.count) ?? .novice
    }

    var previous: Difficulty {
        let n = Difficulty.allCases.count
        return Difficulty(rawValue: (rawValue - 1 + n) % n) ?? .novice
    }
}

/// Player preferences that survive between launches.
enum Settings {
    private enum Key {
        static let fullscreen = "spyhunter.fullscreen"
        /// Stores the Difficulty raw value. Named for the old boolean it
        /// replaced; an existing `true` reads back as `.normal`, which is a
        /// sensible landing spot for someone who had picked expert before.
        static let expert = "spyhunter.expertMode"
        static let musicOn = "spyhunter.musicOn"
        static let soundOn = "spyhunter.soundOn"
    }

    /// Whether the game should start in fullscreen. Toggled with F1.
    static var fullscreen: Bool {
        get { UserDefaults.standard.bool(forKey: Key.fullscreen) }
        set {
            UserDefaults.standard.set(newValue, forKey: Key.fullscreen)
            UserDefaults.standard.synchronize()
        }
    }

    /// Skill level. SPYHUNTER_DIFFICULTY (0/1/2) forces it for headless testing.
    static var difficulty: Difficulty {
        get {
            if let forced = ProcessInfo.processInfo.environment["SPYHUNTER_DIFFICULTY"],
               let raw = Int(forced), let level = Difficulty(rawValue: raw) {
                return level
            }
            return Difficulty(rawValue: UserDefaults.standard.integer(forKey: Key.expert))
                ?? .novice
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.expert) }
    }

    static var musicOn: Bool {
        get {
            if UserDefaults.standard.object(forKey: Key.musicOn) == nil { return true }
            return UserDefaults.standard.bool(forKey: Key.musicOn)
        }
        set { UserDefaults.standard.set(newValue, forKey: Key.musicOn) }
    }

    /// Sound effects, separate from the music track.
    static var soundOn: Bool {
        get {
            if UserDefaults.standard.object(forKey: Key.soundOn) == nil { return true }
            return UserDefaults.standard.bool(forKey: Key.soundOn)
        }
        set { UserDefaults.standard.set(newValue, forKey: Key.soundOn) }
    }
}
