import CoreGraphics
import Foundation

/// Global tuning constants. Values marked "arcade" reproduce the 1983
/// Bally Midway original; everything else is presentation.
enum GameConfig {

    static let version = "V0.99"

    // MARK: - Virtual canvas
    //
    // The arcade cabinet used a vertical monitor. We render everything into a
    // fixed portrait canvas at native sprite scale and letterbox it into the
    // window, so pixels stay crisp and gameplay is resolution independent.
    static let canvasWidth: CGFloat = 320
    static let canvasHeight: CGFloat = 480
    static var canvasSize: CGSize { CGSize(width: canvasWidth, height: canvasHeight) }

    // MARK: - Scoring (arcade)

    // Distance scoring.
    //
    // Contemporary sources give 15 points per screen on road and 25 on water,
    // but those cannot be reconciled with the same sources' 18,000-point
    // double-bonus threshold: at 15/screen the whole 90-second opening pays
    // about 675 points, so 18,000 would need a sustained 200 points a second.
    // Measured play here bore that out — a full intro period scored ~1,000.
    // The rates are scaled 12x so the documented threshold is a genuine stretch
    // for a strong run rather than unreachable, and so extra cars (awarded every
    // 10,000) are actually attainable. The road:water ratio is kept as documented.
    static let pointsPerScreenRoad = 180
    static let pointsPerScreenWater = 300

    /// Points for destroying each enemy type.
    static let scoreSwitchblade = 150
    static let scoreRoadLord = 150
    static let scoreEnforcer = 500
    static let scoreMadBomber = 700
    static let scoreBarrelDumper = 150
    static let scoreDoctorTorpedo = 500

    /// Destroying a friendly stalls the score counter for this long, which
    /// withholds roughly the point values the arcade documented.
    static let penaltyCivilian: TimeInterval = 1.0   // ~150 points withheld
    static let penaltyWeaponsVan: TimeInterval = 2.0 // ~300 points withheld
    static let penaltyTugboat: TimeInterval = 3.0    // ~450 points withheld

    // MARK: - Lives / bonus cars (arcade)

    /// Length of the opening "free play" period during which cars are unlimited.
    static let introTimerSeconds: TimeInterval = 90
    /// Reaching this score before the intro timer expires awards 2 bonus cars
    /// instead of 1.
    static let doubleBonusThreshold = 18_000
    // Extra-car thresholds and the difficulty ramp now live on `Difficulty`,
    // which carries all three skill levels.

    // MARK: - Driving

    static let playerMinSpeed: CGFloat = 120   // canvas points / second
    static let playerMaxSpeed: CGFloat = 420
    static let playerCruiseSpeed: CGFloat = 240
    static let playerAccel: CGFloat = 220
    static let playerBrake: CGFloat = 380
    static let playerSteerSpeed: CGFloat = 170
    /// How far up the screen the player's car sits (fraction of canvas height).
    static let playerScreenY: CGFloat = 0.22
    /// How far the player may stray past the edge of the tarmac before the car
    /// is wrecked. Generous, so clipping a bend is survivable.
    static let offRoadFatalDistance: CGFloat = 30
    /// Agents wreck as soon as they are properly over the line, which is what
    /// makes barging one off the road a practical way to kill it.
    static let offRoadFatalDistanceEnemy: CGFloat = 10

    // MARK: - Weapons

    static let bulletSpeed: CGFloat = 620
    static let bulletCooldown: TimeInterval = 0.11
    static let missileSpeed: CGFloat = 520
    static let missileCooldown: TimeInterval = 0.45
    /// Ammo granted by one weapons-van pickup.
    static let vanAmmoOil = 5
    static let vanAmmoSmoke = 5
    static let vanAmmoMissiles = 6

    // MARK: - High scores

    static let highScoreCount = 10
    /// Scaled to match the rescaled distance scoring — the old table topped out
    /// at 25,000, which a decent run now passes inside three minutes.
    static let defaultHighScores: [(String, Int)] = [
        ("TJB", 65_000), ("AKT", 56_000), ("TLM", 48_000), ("AJB", 41_000),
        ("NCS", 35_000), ("SPY", 29_000), ("MID", 24_000), ("WAY", 19_000),
        ("G65", 14_000), ("CAR",  9_000),
    ]
}

/// Sprite draw order.
enum ZOrder {
    static let terrain: CGFloat = 0
    static let roadMarkings: CGFloat = 5
    static let roadside: CGFloat = 10
    static let slick: CGFloat = 15
    static let debris: CGFloat = 18
    static let vehicle: CGFloat = 20
    static let player: CGFloat = 25
    static let projectile: CGFloat = 30
    static let air: CGFloat = 40
    static let explosion: CGFloat = 50
    static let smoke: CGFloat = 55
    static let hud: CGFloat = 100
    static let overlay: CGFloat = 200
}
