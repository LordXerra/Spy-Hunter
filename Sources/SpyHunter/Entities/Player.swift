import SpriteKit

/// The G-6155 Interceptor.
final class Player {

    enum State {
        case driving
        /// Spun out after a hit or leaving the road badly.
        case spinning(elapsed: TimeInterval)
        /// Tyres slashed by a Switchblade: no steering at all until they are
        /// shredded off and the car limps back under control.
        case tyresBlown(elapsed: TimeInterval, drift: CGFloat)
        /// Passing through a boathouse, changing between car and boat.
        case transforming(elapsed: TimeInterval, toBoat: Bool)
        /// Inside a weapons van being re-armed. The scene carries the car
        /// along with the van while this runs.
        case inVan(elapsed: TimeInterval)
        case destroyed
        /// Reversing out of the weapons van at the start of a life.
        case entering(elapsed: TimeInterval)
    }

    /// How long the car spends inside the van being loaded.
    static let vanLoadDuration: TimeInterval = 1.1

    /// How long the player is left without steering after a tyre slash.
    static let tyreBlowoutDuration: TimeInterval = 2.6
    /// Length of the boathouse transformation, half dissolving, half arriving.
    static let transformDuration: TimeInterval = 0.9
    /// Length of the opening roll-out from the weapons van.
    static let openingDuration: TimeInterval = 1.4

    /// Brief immunity after a transformation or a new life, so the player is
    /// never destroyed before they have had a chance to react.
    private(set) var graceRemaining: TimeInterval = 0
    var hasGrace: Bool { graceRemaining > 0 }

    /// 0 while a replacement boat is still entering from the bottom edge,
    /// reaching 1 at its normal station. The scene uses it to place the sprite.
    var entryRise: CGFloat = 1

    let node = SKNode()
    private let sprite: SKSpriteNode
    /// True while the player is actively slowing, which lights the brake lamps.
    private var isBraking = false
    /// How far off the tarmac the car currently is; the scene wrecks it past
    /// `GameConfig.offRoadFatalDistance`.
    private(set) var offRoadDistance: CGFloat = 0
    private var skidTimer: TimeInterval = 0
    /// Lateral velocity, which only really matters on ice: with grip gone the
    /// car keeps sliding after the player stops steering.
    private var lateralVelocity: CGFloat = 0

    var x: CGFloat = GameConfig.canvasWidth / 2
    var worldY: CGFloat = 0
    var speed: CGFloat = GameConfig.playerCruiseSpeed
    var state: State = .driving

    // Weapons — machine guns are unlimited; the rest come from the weapons van.
    var oilAmmo = 0
    var smokeAmmo = 0
    var missileAmmo = 0
    /// Which rear weapon the secondary button deploys.
    var rearWeaponPrefersOil = true

    /// The Interceptor converts to a boat for the water sections.
    private(set) var isBoat = false
    private var wakePhase: TimeInterval = 0

    var isAlive: Bool {
        if case .destroyed = state { return false }
        return true
    }
    var isControllable: Bool {
        if case .driving = state { return true }
        return false
    }
    /// True while the car is still solid and can be hit, but not steered.
    var isVulnerable: Bool {
        guard graceRemaining <= 0 else { return false }
        switch state {
        case .driving, .spinning, .tyresBlown: return true
        default: return false
        }
    }
    var isInVan: Bool {
        if case .inVan = state { return true }
        return false
    }
    var isTransforming: Bool {
        if case .transforming = state { return true }
        return false
    }

    /// Collision box, tighter than the sprite so near-misses feel fair.
    var hitSize: CGSize {
        isBoat ? CGSize(width: 26, height: 44) : CGSize(width: 24, height: 40)
    }

    init() {
        sprite = Atlas.shared.node(Art.playerCar)
        // Zero, not ZOrder.player: SpriteKit sums zPosition down the tree, so
        // setting it on both the node and its sprite put the car at double the
        // intended depth and drew it over the weapons van it was inside.
        sprite.zPosition = 0
        node.addChild(sprite)
        node.zPosition = ZOrder.player
    }

    // MARK: - Update

    func update(dt: TimeInterval, steer: CGFloat, throttle: CGFloat, road: RoadManager) {
        switch state {
        case .entering(let elapsed):
            let t = elapsed + dt
            let progress = min(1, CGFloat(t / Player.openingDuration))
            // A boat arrives under its own power from the bottom of the screen;
            // the car is delivered by the van and needs no such entrance.
            entryRise = isBoat ? progress * progress * (3 - 2 * progress) : 1
            state = t >= Player.openingDuration ? .driving : .entering(elapsed: t)
            // Rolling out of the van: the truck pulls away at cruising speed
            // while the car builds up from a standstill, so it appears to back
            // out of the open rear.
            speed = min(GameConfig.playerCruiseSpeed,
                        speed + GameConfig.playerAccel * 1.4 * CGFloat(dt))
            worldY += speed * CGFloat(dt)
            // Track the road while pulling away, so the car is always back on
            // the tarmac by the time control returns — and keep the off-road
            // reading clear so the new life does not inherit the fatal one.
            x = road.clamp(x: road.nearestBranchCentre(x: x, worldY: worldY),
                           worldY: worldY, margin: 10)
            offRoadDistance = 0
            animate(dt: dt, steer: 0)

        case .driving:
            drive(dt: dt, steer: steer, throttle: throttle, road: road)

        case .tyresBlown(let elapsed, let drift):
            let t = elapsed + dt
            // No steering: the car wanders on its slashed tyres and sheds speed.
            speed = max(GameConfig.playerMinSpeed * 0.7,
                        speed - 90 * CGFloat(dt))
            x += drift * CGFloat(dt)
            worldY += speed * CGFloat(dt)
            offRoadDistance = road.offRoadDistance(x: x, worldY: worldY)
            // Judder to sell the flat tyres.
            sprite.zRotation = sin(CGFloat(t) * 34) * 0.07
            skidTimer -= dt
            if skidTimer <= 0 {
                skidTimer = 0.42
                AudioManager.shared.play(.skid, volume: 0.3)
            }
            if t >= Player.tyreBlowoutDuration {
                sprite.zRotation = 0
                state = .driving
            } else {
                state = .tyresBlown(elapsed: t, drift: drift)
            }

        case .transforming(let elapsed, let toBoat):
            let t = elapsed + dt
            let half = Player.transformDuration / 2
            speed = max(GameConfig.playerMinSpeed, speed - 60 * CGFloat(dt))
            worldY += speed * CGFloat(dt)
            // Hold the middle of the channel while inside the boathouse.
            x += (road.nearestBranchCentre(x: x, worldY: worldY) - x) * min(1, CGFloat(dt) * 3)
            offRoadDistance = 0

            let frames = Art.playerTransform
            if t < half {
                // Dissolving: rings close in over the old vehicle.
                let i = min(frames.count - 1, Int(t / half * Double(frames.count)))
                setArt(frames[i])
            } else {
                if isBoat != toBoat {
                    isBoat = toBoat
                    AudioManager.shared.play(.splash, volume: 0.8)
                }
                // Arriving: the same rings played back out again.
                let p = (t - half) / half
                let i = min(frames.count - 1, Int((1 - p) * Double(frames.count)))
                setArt(frames[i])
            }
            if t >= Player.transformDuration {
                state = .driving
                // Coming out of a boathouse into fire with no chance to move is
                // unfair, so buy a moment to get oriented.
                graceRemaining = 1.6      // settling in after a boathouse
                setArt(toBoat ? Art.playerBoat[0] : Art.playerCar)
            } else {
                state = .transforming(elapsed: t, toBoat: toBoat)
            }

        case .spinning(let elapsed):
            let t = elapsed + dt
            // Bleed off speed while the car slews sideways.
            speed = max(GameConfig.playerMinSpeed * 0.5, speed - 320 * CGFloat(dt))
            worldY += speed * CGFloat(dt)
            // Roughly one and a bit turns, not three — a long spin is
            // disorienting and costs more control than the hit deserves.
            sprite.zRotation += CGFloat(dt) * 9
            if t >= 0.85 {
                sprite.zRotation = 0
                state = .driving
                // Nudge back toward the road so the player is not stranded.
                let c = road.nearestBranchCentre(x: x, worldY: worldY)
                x += (c - x) * 0.35
                offRoadDistance = road.offRoadDistance(x: x, worldY: worldY)
            } else {
                state = .spinning(elapsed: t)
            }

        case .inVan(let elapsed):
            // Position is driven by the scene from the van; just run the clock.
            state = .inVan(elapsed: elapsed + dt)

        case .destroyed:
            break
        }

        // Tick down the post-transformation immunity, blinking while it lasts
        // so the player can see they are briefly safe.
        if graceRemaining > 0 {
            graceRemaining = max(0, graceRemaining - dt)
            sprite.alpha = sin(CGFloat(graceRemaining) * 34) > 0 ? 1 : 0.35
            if graceRemaining == 0 { sprite.alpha = 1 }
        }

        // The scene owns the fixed screen-Y; we only drive the lateral position.
        node.position.x = x
    }

    private func drive(dt: TimeInterval, steer: CGFloat, throttle: CGFloat, road: RoadManager) {
        let d = CGFloat(dt)

        // Throttle
        isBraking = throttle < -0.05
        if throttle > 0.05 {
            speed += GameConfig.playerAccel * throttle * d
        } else if throttle < -0.05 {
            speed += GameConfig.playerBrake * throttle * d
        } else {
            // Coast toward cruising speed.
            let target = GameConfig.playerCruiseSpeed
            speed += (target - speed) * min(1, d * 1.5)
        }
        speed = max(GameConfig.playerMinSpeed, min(GameConfig.playerMaxSpeed, speed))

        // Steering — faster cars change lanes a little quicker.
        let steerScale = 0.75 + 0.45 * (speed / GameConfig.playerMaxSpeed)
        let target = steer * GameConfig.playerSteerSpeed * steerScale

        // Ice is loose, not heavy. The wheel still bites quickly — steering
        // that merely felt sluggish was the wrong idea — but there is almost no
        // lateral friction, so the car keeps sliding after the player lets go
        // and can be steered past its normal cornering limit.
        let grip = road.grip(worldY)
        if grip < 1 {
            let slide = target * 1.3          // freer than on dry tarmac
            let responsiveness: CGFloat = abs(target) > 0.01
                ? 9.0                          // answers the wheel readily
                : 1.1                          // but barely scrubs off speed
            lateralVelocity += (slide - lateralVelocity) * min(1, d * responsiveness)
        } else {
            lateralVelocity = target
        }
        x += lateralVelocity * d

        // The verge is drivable but punishing; stray too far and the car is
        // wrecked, exactly as running off the road did in the arcade. The
        // scene reads `offRoadDistance` and destroys the car past the limit.
        offRoadDistance = road.offRoadDistance(x: x, worldY: worldY)
        if offRoadDistance > 0 {
            let severity = min(1, offRoadDistance / GameConfig.offRoadFatalDistance)
            speed = min(speed, GameConfig.playerMinSpeed * (1.25 - 0.45 * severity))
            skidTimer -= dt
            if skidTimer <= 0 {
                skidTimer = 0.5
                AudioManager.shared.play(.skid, volume: 0.35)
            }
        }
        // Backstop so the car can never leave the play area entirely.
        x = max(6, min(GameConfig.canvasWidth - 6, x))

        worldY += speed * d
        animate(dt: dt, steer: steer)
    }

    private func animate(dt: TimeInterval, steer: CGFloat) {
        let rect: SpriteRect
        if isBoat {
            // The wake lengthens with speed.
            wakePhase += dt * Double(speed / 60)
            if abs(steer) > 0.35 {
                // One right-bank pose on the sheet, mirrored for a left turn.
                rect = abs(steer) > 0.75 ? Art.playerBoatBankHard : Art.playerBoatBank
                sprite.xScale = steer < 0 ? -1 : 1
            } else {
                let frame = min(Art.playerBoat.count - 1,
                                Int(normalisedSpeed * CGFloat(Art.playerBoat.count)))
                rect = Art.playerBoat[max(0, frame)]
                sprite.xScale = 1
            }
        } else {
            // Poses, not an animation cycle: upright, brake lights when
            // slowing, and banking only while actually steering.
            if abs(steer) > 0.25 {
                rect = Art.playerCarBank            // sheet only has the right bank
                sprite.xScale = steer < 0 ? -1 : 1  // mirrored for the left
            } else {
                rect = isBraking ? Art.playerCarBraking : Art.playerCar
                sprite.xScale = 1
            }
        }
        sprite.texture = Atlas.shared.texture(rect)
        sprite.size = rect.size
    }

    /// Forces the vehicle form without the boathouse animation (used on respawn).
    func setBoatForm(_ boat: Bool) {
        guard boat != isBoat else { return }
        isBoat = boat
        sprite.xScale = 1
        sprite.zRotation = 0
        setArt(boat ? Art.playerBoat[0] : Art.playerCar)
    }

    private func setArt(_ rect: SpriteRect) {
        sprite.texture = Atlas.shared.texture(rect)
        sprite.size = rect.size
    }

    // MARK: - Events

    /// A boat has no tyres to lose and nothing to spin on — a hit sinks it.
    var spinsWhenHit: Bool { !isBoat }

    func spinOut() {
        guard isControllable, spinsWhenHit else { return }
        state = .spinning(elapsed: 0)
        lateralVelocity = 0
        AudioManager.shared.play(.skid)
        InputManager.shared.rumble(intensity: 0.7, duration: 0.4)
    }

    /// A Switchblade's slashers caught the tyres: the player loses steering for
    /// a few seconds while the car wanders.
    func blowTyres(pushedToward direction: CGFloat) {
        guard isControllable else { return }
        state = .tyresBlown(elapsed: 0, drift: direction * CGFloat.random(in: 28...52))
        lateralVelocity = 0
        AudioManager.shared.play(.skid, volume: 0.9)
        InputManager.shared.rumble(intensity: 1.0, duration: 0.6)
    }

    /// Begins the boathouse change between car and boat.
    func beginTransform(toBoat: Bool) {
        guard !isTransforming, toBoat != isBoat else { return }
        state = .transforming(elapsed: 0, toBoat: toBoat)
        lateralVelocity = 0
        sprite.isHidden = false
        sprite.xScale = 1
        sprite.zRotation = 0
    }

    func destroy() {
        state = .destroyed
        graceRemaining = 0
        sprite.alpha = 1
        entryRise = 1
        sprite.isHidden = true
    }

    /// Puts the car back on the road for a new life.
    func respawn(at road: RoadManager) {
        sprite.isHidden = false
        // Clear the tyre-slash judder and any banking mirror, or the new car
        // inherits the wreck's appearance.
        sprite.zRotation = 0
        sprite.xScale = 1
        isBraking = false
        // Must outlast the entry itself, or the player becomes vulnerable a
        // fraction before they regain control — which on water means being shot
        // while still climbing into shot, with no way to answer.
        graceRemaining = Player.openingDuration + 1.2
        entryRise = road.isWater(worldY) ? 0 : 1
        // Come back in the right vehicle for where we are, then face straight
        // again — otherwise the car emerges still banked into whatever turn it
        // was making when it died.
        isBoat = road.isWater(worldY)
        setArt(isBoat ? Art.playerBoat[0] : Art.playerCar)
        state = .entering(elapsed: 0)
        lateralVelocity = 0
        // Starts almost stationary so the van visibly pulls away.
        speed = GameConfig.playerMinSpeed * 0.35
        x = road.clamp(x: road.nearestBranchCentre(x: x, worldY: worldY),
                       worldY: worldY, margin: 10)
        offRoadDistance = 0
        skidTimer = 0
        oilAmmo = 0
        smokeAmmo = 0
        missileAmmo = 0
    }

    /// Loads the single weapon the van was carrying.
    func load(_ weapon: WeaponLoad) {
        switch weapon {
        case .missiles: missileAmmo += GameConfig.vanAmmoMissiles
        case .oil:      oilAmmo += GameConfig.vanAmmoOil
        case .smoke:    smokeAmmo += GameConfig.vanAmmoSmoke
        }
    }

    /// Drives up the ramp and out of sight inside the van.
    func enterVan() {
        guard isControllable else { return }
        state = .inVan(elapsed: 0)
        sprite.isHidden = true
        sprite.zRotation = 0
        sprite.xScale = 1
        lateralVelocity = 0
    }

    /// Rolls back out and resumes play at the given spot.
    func exitVan(x newX: CGFloat, worldY newY: CGFloat) {
        x = newX
        worldY = newY
        sprite.isHidden = false
        state = .driving
        speed = max(GameConfig.playerMinSpeed, speed)
        lateralVelocity = 0
        offRoadDistance = 0
    }

    /// Elapsed time inside the van, or nil if not inside one.
    var vanLoadProgress: TimeInterval? {
        if case .inVan(let t) = state { return t }
        return nil
    }

    var normalisedSpeed: CGFloat {
        (speed - GameConfig.playerMinSpeed)
            / (GameConfig.playerMaxSpeed - GameConfig.playerMinSpeed)
    }
}
