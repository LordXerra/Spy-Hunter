import SpriteKit

/// What the scene exposes to entities, so behaviours never touch SKScene directly.
protocol GameWorld: AnyObject {
    var player: Player { get }
    var road: RoadManager { get }
    /// World-Y at the bottom edge of the screen.
    var cameraY: CGFloat { get }

    /// Live enemy agents, so the director can cap how many hunt at once.
    var enemyCount: Int { get }
    /// Helicopters currently in the air, which are capped separately.
    var airborneEnemyCount: Int { get }
    /// True when any weapons van is on the road. Only one is ever allowed,
    /// including the one that drops the player off.
    var hasWeaponsVan: Bool { get }
    /// True when something already occupies that stretch of road.
    func isOccupied(x: CGFloat, worldY: CGFloat, radius: CGFloat) -> Bool

    func spawn(_ entity: RoadEntity)
    func spawn(_ projectile: Projectile)
    func explode(at point: CGPoint, size: ExplosionSize, water: Bool)
    func addScore(_ points: Int)
    func applyPenalty(_ seconds: TimeInterval)
    func shake(_ amount: CGFloat)
}

extension GameWorld {
    /// Screen-Y for a world position.
    func screenY(_ worldY: CGFloat) -> CGFloat { worldY - cameraY }

    /// True when a world position is comfortably inside the visible area.
    /// Agents check this before shooting: being hit from off the top of the
    /// screen gives the player nothing to react to.
    func isOnScreen(_ worldY: CGFloat, margin: CGFloat = 24) -> Bool {
        let y = screenY(worldY)
        return y > margin && y < GameConfig.canvasHeight - margin
    }
}

/// Anything that occupies the road and scrolls with it.
class RoadEntity {

    enum Team {
        case enemy      // shooting these scores points
        case civilian   // shooting these is penalised
        case friendly   // the weapons van
    }

    let node = SKNode()
    let sprite = SKSpriteNode()

    var x: CGFloat = 0
    var worldY: CGFloat = 0
    /// Forward travel in world units per second.
    var speed: CGFloat = 0
    var alive = true

    var team: Team = .enemy
    /// Bulletproof — the Road Lord must be forced off the road instead.
    var armoured = false
    /// Flies above the road; only missiles reach it.
    var airborne = false
    /// True for boats. Used to remove anything that finds itself on the wrong
    /// terrain when the track changes between road and river.
    var isWaterborne = false
    /// Rounds it takes to destroy. The Road Lord ignores this — its armour
    /// makes it immune to gunfire whatever the count.
    var hitPoints = 1
    /// How heavily it resists being barged: a motorbike is flung clear, a lorry
    /// barely shifts. Push distance and the player's speed loss both scale off
    /// this, so ramming has weight to it.
    var mass: CGFloat = 1
    /// Points awarded when destroyed.
    var scoreValue = 0
    /// Seconds of score-counter stall if this is destroyed (friendlies only).
    var penalty: TimeInterval = 0
    var hitSize = CGSize(width: 24, height: 36)

    /// Set once the entity has been driven off the road and is doomed.
    var isWrecked = false

    init() {
        sprite.zPosition = 0
        node.addChild(sprite)
        node.zPosition = ZOrder.vehicle
    }

    /// Pose set for vehicles that bank when they steer.
    var frames: VehicleFrames?
    private var lastX: CGFloat = .nan
    /// Smoothed lateral velocity, used to choose the banking pose.
    private var steerAmount: CGFloat = 0

    func setArt(_ rect: SpriteRect) {
        sprite.texture = Atlas.shared.texture(rect)
        sprite.size = rect.size
    }

    /// Picks the banking pose from how the vehicle is actually moving sideways,
    /// rather than cycling poses on a timer.
    func updatePose(dt: TimeInterval, braking: Bool = false) {
        guard let frames, dt > 0 else { return }
        if lastX.isNaN { lastX = x }
        let lateral = (x - lastX) / CGFloat(dt)
        lastX = x
        // Ease so the pose does not flicker on tiny corrections.
        steerAmount += (lateral / 55 - steerAmount) * min(1, CGFloat(dt) * 9)
        setArt(frames.pose(steer: steerAmount, braking: braking))
    }

    /// Per-frame behaviour. Base implementation just travels forward.
    func update(dt: TimeInterval, world: GameWorld) {
        worldY += speed * CGFloat(dt)
    }

    /// Called when bullets or a collision destroy this entity.
    func onDestroyed(world: GameWorld) {}

    /// While positive the vehicle has been shoved and is out of control, which
    /// is what lets the player barge agents off the road.
    var pushTimer: TimeInterval = 0
    /// Sideways velocity imparted by a ram, so a sustained barge accumulates
    /// instead of the agent simply steering straight back on.
    var pushVelocityX: CGFloat = 0

    var isPushed: Bool { pushTimer > 0 }

    /// Applies a shove from a ram.
    func applyPush(direction: CGFloat, speed: CGFloat = 150, duration: TimeInterval = 0.9) {
        pushVelocityX = direction * speed
        pushTimer = max(pushTimer, duration)
    }

    /// Keeps a vehicle on the tarmac, following whichever branch of a fork it
    /// is nearest to — unless it has just been rammed, in which case it is left
    /// to run off the road and wreck.
    func clampToRoad(_ road: RoadManager, margin: CGFloat = 6) {
        guard !isPushed else { return }
        x = road.clamp(x: x, worldY: worldY, margin: margin)
    }

    /// Brief white flash when a round connects but does not finish it off.
    func flashHit() {
        sprite.removeAction(forKey: "hitFlash")
        sprite.color = .white
        sprite.colorBlendFactor = 0.85
        sprite.run(.sequence([
            .wait(forDuration: 0.06),
            .customAction(withDuration: 0.12) { node, elapsed in
                (node as? SKSpriteNode)?.colorBlendFactor = 0.85 * (1 - elapsed / 0.12)
            },
            .run { [weak sprite] in sprite?.colorBlendFactor = 0 },
        ]), withKey: "hitFlash")
    }

    /// Advances the shove: carries the vehicle sideways and decays the impulse.
    func tickPush(dt: TimeInterval) {
        guard pushTimer > 0 else { return }
        pushTimer = max(0, pushTimer - dt)
        x += pushVelocityX * CGFloat(dt)
        pushVelocityX *= pow(0.5, dt * 2)
        if pushTimer == 0 { pushVelocityX = 0 }
    }

    var screenRect: CGRect {
        CGRect(x: x - hitSize.width / 2, y: worldY - hitSize.height / 2,
               width: hitSize.width, height: hitSize.height)
    }

    /// World-space overlap test against another entity.
    func overlaps(_ other: RoadEntity) -> Bool {
        screenRect.intersects(other.screenRect)
    }

    func overlaps(rect: CGRect) -> Bool {
        screenRect.intersects(rect)
    }
}

// MARK: - Civilian traffic

/// Innocent road users. Destroying one stalls the score counter.
final class CivilianCar: RoadEntity {
    private var drift: CGFloat

    init(kind: Int) {
        let options: [(VehicleFrames, CGFloat)] = [
            (Art.civilianCarFrames, 1.0),
            (Art.civilianTruckFrames, 2.3),   // lorry: barely shifts
            (Art.motorbikeFrames, 0.32),      // bike: flung a long way
            (Art.civilianCarFrames, 1.1),
            (Art.civilianTruckFrames, 2.1),
        ]
        let (set, weight) = options[kind % options.count]
        drift = CGFloat.random(in: -12...12)
        super.init()
        team = .civilian
        penalty = GameConfig.penaltyCivilian
        mass = weight
        frames = set
        setArt(set.straight)
        // Close to the artwork, so contact registers when the sprites touch
        // rather than after they have visibly overlapped.
        hitSize = CGSize(width: set.straight.w - 2, height: set.straight.h - 3)
    }

    override func update(dt: TimeInterval, world: GameWorld) {
        worldY += speed * CGFloat(dt)
        // Gentle lane drift keeps traffic from looking rigid.
        if !isPushed { x += drift * CGFloat(dt) }
        clampToRoad(world.road, margin: 14)
        updatePose(dt: dt)
    }
}

// MARK: - Weapons van

/// What a weapons van is carrying. A van holds one weapon, not all three.
enum WeaponLoad {
    case missiles, oil, smoke

    var name: String {
        switch self {
        case .missiles: return "MISSILES"
        case .oil:      return "OIL SLICK"
        case .smoke:    return "SMOKE SCREEN"
        }
    }
}

/// The weapons van. It runs ahead of the player with its beacon flashing, drops
/// its rear ramp as they close in, and re-arms the car that drives inside.
/// Shooting one is penalised.
final class WeaponsVan: RoadEntity {

    enum Stage {
        case closed     // driving, ramp up
        case open       // ramp down, ready to accept the player
        case loading    // player is inside
        case spent      // already used, ramp back up
    }

    let load: WeaponLoad
    private(set) var stage: Stage = .closed
    private var beaconPhase: TimeInterval = 0
    /// The van the player starts a life in. It carries nothing and pulls away
    /// gradually so the car is revealed backing out of it.
    private(set) var isStarter = false

    override init() {
        load = [.missiles, .oil, .smoke].randomElement()!
        super.init()
        team = .friendly
        penalty = GameConfig.penaltyWeaponsVan
        mass = 2.8                      // an articulated van shrugs off a nudge
        setArt(Art.vanClosed[0])
        hitSize = CGSize(width: 30, height: 61)
        speed = GameConfig.playerCruiseSpeed * 0.72
    }

    /// The rear opening the player must drive into. Only meaningful with the
    /// ramp down; it sits behind the van so the car enters from directly astern.
    var entryRect: CGRect {
        CGRect(x: x - 12, y: worldY - 34, width: 24, height: 22)
    }

    var isReceiving: Bool { stage == .open }

    func beginLoading() { stage = .loading }

    /// The van the player starts a life in.
    ///
    /// Marked spent so its rear reads as empty — it carries no load, and
    /// showing missiles or smoke on a van that gives you nothing is a lie. It
    /// also starts barely moving, so it draws away from the car gradually
    /// instead of vanishing up the road.
    func configureAsStarter() {
        isStarter = true
        stage = .spent
        speed = GameConfig.playerMinSpeed * 0.4
    }

    /// Ramp back up once the car has rolled out; the van will not re-arm again.
    func finish() { stage = .spent }

    override func update(dt: TimeInterval, world: GameWorld) {
        // The starter van accelerates away rather than starting at speed.
        if isStarter {
            // Must out-accelerate the player, or the car overtakes the van
            // instead of being revealed backing out of it.
            speed = min(GameConfig.playerCruiseSpeed * 1.35,
                        speed + GameConfig.playerAccel * 2.2 * CGFloat(dt))
        }
        worldY += speed * CGFloat(dt)
        clampToRoad(world.road, margin: 18)

        // Drop the ramp once the player is close enough behind to use it.
        if stage == .closed, world.player.worldY > worldY - 380 {
            stage = .open
        }

        beaconPhase += dt * 5
        let lit = Int(beaconPhase) % 2 == 1
        let frames: [SpriteRect]
        switch stage {
        case .closed, .spent:
            frames = Art.vanClosed
        case .open, .loading:
            switch load {
            case .missiles: frames = Art.vanMissiles
            case .oil:      frames = Art.vanOil
            case .smoke:    frames = Art.vanSmoke
            }
        }
        setArt(frames[lit ? 1 : 0])
    }
}
