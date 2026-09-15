import SpriteKit

/// Barrel Dumper — drops floating charges into the player's path.
final class BarrelDumper: RoadEntity {
    private var dropTimer: TimeInterval
    private let dropInterval: TimeInterval

    init(difficulty: CGFloat) {
        dropInterval = max(1.0, 2.4 - Double(min(1, difficulty)) * 1.0)
        dropTimer = 1.0
        super.init()
        isWaterborne = true
        team = .enemy
        scoreValue = GameConfig.scoreBarrelDumper
        hitPoints = 3
        mass = 2.4
        setArt(Art.barrelDumper)
        hitSize = CGSize(width: 23, height: 43)
    }

    override func update(dt: TimeInterval, world: GameWorld) {
        let d = CGFloat(dt)
        worldY += speed * d

        let player = world.player
        // Stay ahead so its charges land where the player is heading.
        let dx = player.x - x
        if !isPushed { x += max(-40, min(40, dx)) * 0.8 * d }
        let gap = worldY - player.worldY
        if gap > 105 {
            speed = max(player.speed * 0.82, speed - 70 * d)
        } else if gap < 55 {
            speed = min(player.speed * 1.1, speed + 70 * d)
        }
        clampToRoad(world.road, margin: 14)

        dropTimer -= dt
        if dropTimer <= 0, world.isOnScreen(worldY), player.isBoat,
           player.isControllable {
            dropTimer = dropInterval
            let charge = FloatingCharge()
            charge.x = x
            charge.worldY = worldY - 24
            world.spawn(charge)
        }
    }
}

/// Doctor Torpedo — fires torpedoes back down the channel.
final class DoctorTorpedo: RoadEntity {
    private var phase: TimeInterval = 0
    private var fireTimer: TimeInterval
    private let fireInterval: TimeInterval

    init(difficulty: CGFloat) {
        fireInterval = max(1.1, 2.4 - Double(min(1, difficulty)) * 1.1)
        fireTimer = fireInterval * 0.5
        super.init()
        isWaterborne = true
        team = .enemy
        scoreValue = GameConfig.scoreDoctorTorpedo
        hitPoints = 4
        mass = 2.8
        setArt(Art.doctorTorpedo)
        hitSize = CGSize(width: 30, height: 51)
    }

    override func update(dt: TimeInterval, world: GameWorld) {
        let d = CGFloat(dt)
        worldY += speed * d

        let player = world.player
        let dx = player.x - x
        if !isPushed { x += max(-50, min(50, dx)) * 0.85 * d }
        let gap = worldY - player.worldY
        if gap > 120 {
            speed = max(player.speed * 0.82, speed - 80 * d)
        } else if gap < 60 {
            speed = min(player.speed * 1.12, speed + 80 * d)
        }
        clampToRoad(world.road, margin: 14)

        phase += dt * 5
        setArt(Int(phase) % 2 == 0 ? Art.doctorTorpedo : Art.doctorTorpedoAlt)

        // Only fire while visible, and only at a player who is actually a boat
        // — otherwise torpedoes are already in the water before the transition.
        fireTimer -= dt
        if fireTimer <= 0, gap > 30, world.isOnScreen(worldY), player.isBoat,
           player.isControllable {
            fireTimer = fireInterval
            let torpedo = Torpedo()
            torpedo.x = x
            torpedo.worldY = worldY - 26
            let dy = max(40, worldY - player.worldY)
            torpedo.velocity = CGVector(dx: (player.x - x) / dy * 220, dy: -220)
            world.spawn(torpedo)
            AudioManager.shared.play(.splash, volume: 0.3)
        }
    }
}

/// A friendly tugboat. Sinking one is penalised, as in the arcade.
final class Tugboat: RoadEntity {
    override init() {
        super.init()
        isWaterborne = true
        team = .civilian
        mass = 3.4                      // a working tug barely notices a nudge
        penalty = GameConfig.penaltyTugboat
        setArt(Art.tugboat)
        hitSize = CGSize(width: 30, height: 56)
    }

    override func update(dt: TimeInterval, world: GameWorld) {
        worldY += speed * CGFloat(dt)
        clampToRoad(world.road, margin: 16)
    }
}

/// Ordinary river traffic.
final class CivilianBoat: RoadEntity {
    override init() {
        super.init()
        isWaterborne = true
        team = .civilian
        mass = 2.2
        penalty = GameConfig.penaltyCivilian
        setArt(Art.civilianBoat)
        hitSize = CGSize(width: 27, height: 51)
    }

    override func update(dt: TimeInterval, world: GameWorld) {
        worldY += speed * CGFloat(dt)
        clampToRoad(world.road, margin: 16)
    }
}

/// A charge dropped by the Barrel Dumper — drifts and detonates on contact.
final class FloatingCharge: Projectile {
    private var bob: TimeInterval = 0

    override init() {
        super.init()
        owner = .enemy
        isHazard = true
        setArt(Art.floatingMine)
        hitSize = CGSize(width: 16, height: 18)
        life = 8
        node.zPosition = ZOrder.slick
    }

    override func update(dt: TimeInterval, world: GameWorld) {
        super.update(dt: dt, world: world)
        // Rides the swell — there is only one frame, so bob it rather than
        // flipping between sprites.
        bob += dt * 4
        let swell = CGFloat(sin(bob))
        sprite.setScale(1 + swell * 0.12)
        sprite.zRotation = swell * 0.18
    }
}

/// Doctor Torpedo's torpedo.
final class Torpedo: Projectile {
    override init() {
        super.init()
        owner = .enemy
        setArt(Art.missile[1])
        sprite.zRotation = .pi        // pointing back down the channel
        hitSize = CGSize(width: 10, height: 18)
        life = 3
    }
}
