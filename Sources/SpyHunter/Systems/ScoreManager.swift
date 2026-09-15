import CoreGraphics
import Foundation

/// Score, the opening free-play timer and the bonus-car rules, reproduced from
/// the arcade original.
///
/// The arcade awards points for distance travelled and for destroying enemy
/// agents. Destroying a *friendly* does not deduct points: it stalls the score
/// counter for a second or two, which withholds roughly 150/300/450 points.
final class ScoreManager {

    private(set) var score = 0
    /// Fractional distance points not yet rolled into `score`.
    private var carry: CGFloat = 0

    /// Seconds left on the opening timer; cars are unlimited until it hits zero.
    private(set) var timeRemaining: TimeInterval = GameConfig.introTimerSeconds
    private(set) var introOver = false

    /// Cars in reserve, once the intro timer has expired.
    private(set) var cars = 0

    /// While positive, distance points are withheld (a friendly was destroyed).
    private(set) var penaltyRemaining: TimeInterval = 0

    private var nextExtraCarAt: Int
    private let extraCarInterval: Int

    /// Set when the player earns a car, so the scene can play the jingle.
    var onExtraCar: (() -> Void)?

    init() {
        extraCarInterval = Settings.difficulty.extraCarInterval
        nextExtraCarAt = extraCarInterval
    }

    var isPenalised: Bool { penaltyRemaining > 0 }
    /// During the intro period the player cannot run out of cars.
    var hasUnlimitedCars: Bool { !introOver }

    /// The arcade's on-screen counter runs 999 down to 0 over the intro period.
    var displayCounter: Int {
        Int((timeRemaining / GameConfig.introTimerSeconds * 999).rounded())
    }

    // MARK: - Update

    func update(dt: TimeInterval, distance: CGFloat, terrain: Terrain) {
        if penaltyRemaining > 0 {
            penaltyRemaining = max(0, penaltyRemaining - dt)
        } else {
            let perScreen = terrain == .water
                ? GameConfig.pointsPerScreenWater
                : GameConfig.pointsPerScreenRoad
            carry += distance / GameConfig.canvasHeight * CGFloat(perScreen)
            if carry >= 1 {
                let whole = Int(carry)
                carry -= CGFloat(whole)
                add(whole)
            }
        }

        guard !introOver else { return }
        timeRemaining = max(0, timeRemaining - dt)
        if timeRemaining == 0 { endIntro() }
    }

    /// The opening timer has run out: bank the bonus cars it earned.
    private func endIntro() {
        introOver = true
        // Reaching 18,000 before the timer expires is worth two cars, not one.
        cars = score >= GameConfig.doubleBonusThreshold ? 2 : 1
        // Extra-car awards are counted from here on.
        nextExtraCarAt = ((score / extraCarInterval) + 1) * extraCarInterval
    }

    // MARK: - Events

    func add(_ points: Int) {
        guard points > 0 else { return }
        score += points
        while score >= nextExtraCarAt {
            nextExtraCarAt += extraCarInterval
            if introOver {
                cars += 1
                onExtraCar?()
            }
        }
    }

    /// Stalls the score counter, the arcade's penalty for hitting a friendly.
    func applyPenalty(_ seconds: TimeInterval) {
        penaltyRemaining = max(penaltyRemaining, seconds)
    }

    /// Consumes a car. Returns false when the game is over.
    func loseCar() -> Bool {
        if hasUnlimitedCars { return true }
        if cars > 0 {
            cars -= 1
            return true
        }
        return false
    }
}
