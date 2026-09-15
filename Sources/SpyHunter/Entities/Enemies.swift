import SpriteKit

/// Switchblade — "Never To Be Trusted".
/// Pulls alongside and extends wheel-mounted tyre slashers; contact spins the
/// player off the road. Vulnerable to machine guns.
final class Switchblade: RoadEntity {
    private var aggression: CGFloat
    /// Lateral station relative to the player, so two Switchblades close in
    /// from either side instead of queueing up in the same lane.
    private let approachOffset: CGFloat
    /// Lane it is currently driving to; re-aimed only on `decisionTimer`.
    private var targetX: CGFloat = 0
    private var decisionTimer: TimeInterval = 0

    /// The slashers are a telegraphed attack on a cycle, not a permanent state,
    /// so there is always a window in which the car can be rammed instead.
    private enum Blades { case retracted, extending, out, recovering }
    private var blades: Blades = .retracted
    private var bladeTimer: TimeInterval = 0
    private let bladeLeft = SKSpriteNode()
    private let bladeRight = SKSpriteNode()

    /// Only while fully extended do the slashers actually cut.
    var bladesOut: Bool { blades == .out }

    init(difficulty: CGFloat) {
        // Lateral speed is deliberately well below the player's, so a committed
        // dodge always beats it.
        aggression = 45 + 35 * min(1, difficulty)
        approachOffset = (Bool.random() ? 1 : -1) * CGFloat.random(in: 14...34)
        super.init()
        team = .enemy
        scoreValue = GameConfig.scoreSwitchblade
        hitPoints = 3
        mass = 0.9
        frames = Art.switchbladeFrames
        setArt(Art.switchbladeFrames.straight)
        hitSize = CGSize(width: 25, height: 38)

        for (blade, side) in [(bladeLeft, CGFloat(-1)), (bladeRight, CGFloat(1))] {
            blade.color = SKColor(white: 0.88, alpha: 1)
            blade.size = CGSize(width: 11, height: 4)
            blade.anchorPoint = CGPoint(x: side < 0 ? 1 : 0, y: 0.5)
            blade.position = CGPoint(x: side * 9, y: -2)
            blade.xScale = 0.01
            blade.zPosition = -1
            node.addChild(blade)
        }
    }

    /// Runs the extend / hold / retract cycle and drives the blade sprites.
    private func updateBlades(dt: TimeInterval, alongside: Bool) {
        bladeTimer -= dt
        switch blades {
        case .retracted:
            if alongside && bladeTimer <= 0 {
                blades = .extending
                bladeTimer = 0.35          // telegraph before they bite
            }
        case .extending:
            if bladeTimer <= 0 { blades = .out; bladeTimer = 1.3 }
        case .out:
            if bladeTimer <= 0 || !alongside { blades = .recovering; bladeTimer = 0.25 }
        case .recovering:
            if bladeTimer <= 0 { blades = .retracted; bladeTimer = 1.6 }
        }

        let target: CGFloat
        switch blades {
        case .retracted:  target = 0.01
        case .extending:  target = 0.55
        case .out:        target = 1
        case .recovering: target = 0.4
        }
        for blade in [bladeLeft, bladeRight] {
            blade.xScale += (target - blade.xScale) * min(1, CGFloat(dt) * 12)
            blade.alpha = min(1, blade.xScale * 1.6)
        }
        // The slashers only widen the car's reach while they are actually out.
        hitSize = CGSize(width: bladesOut ? 36 : 25, height: 38)
    }

    override func update(dt: TimeInterval, world: GameWorld) {
        let d = CGFloat(dt)
        worldY += speed * d

        let player = world.player

        // The arcade's Switchblade makes discrete passes at the player rather
        // than mirroring their steering. It commits to a lane, holds it, and
        // only re-aims every so often — which is what makes it dodgeable.
        decisionTimer -= dt
        if decisionTimer <= 0 {
            decisionTimer = Double.random(in: 0.7...1.3)
            targetX = player.x + approachOffset
        }
        if !isPushed {
            let dx = targetX - x
            if abs(dx) > 2 {
                x += (dx > 0 ? 1 : -1) * min(aggression * d, abs(dx))
            }
        }
        // Match pace with the player while alongside.
        let gap = worldY - player.worldY
        if gap > 60 {
            speed = max(player.speed * 0.82, speed - 90 * d)
        } else if gap < -40 {
            speed = min(player.speed * 1.12, speed + 90 * d)
        }
        clampToRoad(world.road, margin: 10)

        // The slashers are readied when it draws level with the player.
        updateBlades(dt: dt, alongside: abs(player.x - x) < 46 && abs(gap) < 60)
        updatePose(dt: dt)
    }
}

/// The Road Lord — "Bulletproof Bully".
/// Armour plating makes it immune to machine guns; the only way to score is to
/// ram it off the road.
final class RoadLord: RoadEntity {
    private var blockStrength: CGFloat
    private let approachOffset: CGFloat

    init(difficulty: CGFloat) {
        blockStrength = 40 + 35 * min(1, difficulty)
        approachOffset = CGFloat.random(in: -22...22)
        super.init()
        team = .enemy
        armoured = true
        scoreValue = GameConfig.scoreRoadLord
        mass = 1.9                      // heavy, and the only way through it
        frames = Art.roadLordFrames
        setArt(Art.roadLordFrames.straight)
        hitSize = CGSize(width: 25, height: 40)
    }

    override func update(dt: TimeInterval, world: GameWorld) {
        let d = CGFloat(dt)
        worldY += speed * d

        let player = world.player
        if isWrecked {
            // Shoved off the road — drift clear and explode at the verge.
            x += (x < world.road.centreX(worldY) ? -1 : 1) * 120 * d
            sprite.zRotation += d * 6
            return
        }

        // Sit ahead of the player and slide across to block.
        let dx = player.x + approachOffset - x
        if !isPushed, abs(dx) > 2 {
            x += (dx > 0 ? 1 : -1) * min(blockStrength * d, abs(dx))
        }
        let gap = worldY - player.worldY
        if gap > 90 {
            speed = max(player.speed * 0.9, speed - 80 * d)
        } else if gap < 30 {
            speed = min(player.speed * 1.15, speed + 80 * d)
        }
        clampToRoad(world.road, margin: 8)
        updatePose(dt: dt, braking: speed < player.speed * 0.95)
    }
}

/// The Enforcer — "Double Barrel Action".
/// A limousine carrying a shotgun-toting thug who fires back at the player.
final class Enforcer: RoadEntity {
    private var fireTimer: TimeInterval
    private let fireInterval: TimeInterval
    private var muzzleLeft = false
    private let approachOffset: CGFloat

    init(difficulty: CGFloat) {
        approachOffset = CGFloat.random(in: -26...26)
        fireInterval = max(0.75, 1.7 - Double(min(1, difficulty)) * 0.8)
        fireTimer = fireInterval * 0.6
        super.init()
        team = .enemy
        scoreValue = GameConfig.scoreEnforcer
        hitPoints = 4                   // a long armoured limousine
        mass = 1.7
        frames = Art.enforcerFrames
        setArt(Art.enforcerFrames.straight)
        hitSize = CGSize(width: 26, height: 55)
    }

    override func update(dt: TimeInterval, world: GameWorld) {
        let d = CGFloat(dt)
        worldY += speed * d

        let player = world.player
        // Hold station ahead of the player so the gunman has a clear shot.
        let dx = player.x + approachOffset - x
        if !isPushed { x += max(-45, min(45, dx)) * 0.9 * d }
        let gap = worldY - player.worldY
        if gap > 140 {
            speed = max(player.speed * 0.85, speed - 80 * d)
        } else if gap < 70 {
            speed = min(player.speed * 1.1, speed + 80 * d)
        }
        clampToRoad(world.road, margin: 10)
        updatePose(dt: dt, braking: speed < player.speed * 0.95)

        fireTimer -= dt
        // Never shoot from off the top of the screen, nor at a player who has
        // not been given control back yet.
        if fireTimer <= 0, gap > 20, abs(dx) < 90,
           world.isOnScreen(worldY), player.isControllable {
            fireTimer = fireInterval
            muzzleLeft.toggle()
            let shot = EnemyBullet()
            shot.x = x + (muzzleLeft ? -9 : 9)
            shot.worldY = worldY - 26
            // Aim back down the road at the player.
            let dy = max(40, worldY - player.worldY)
            shot.velocity = CGVector(dx: (player.x - x) / dy * 260, dy: -260)
            world.spawn(shot)
            AudioManager.shared.play(.gunshot, volume: 0.4)
        }
    }
}

/// The Mad Bomber — "Master Of The Sky".
/// A helicopter that drops bombs on the road. Machine guns cannot reach it;
/// only a missile brings it down.
final class MadBomber: RoadEntity {
    /// How long it will hunt before giving up and flying off. The player has no
    /// answer to it without missiles, so it must never be able to loiter
    /// indefinitely.
    static let patrolDuration: TimeInterval = 15

    private let rotor = SKSpriteNode()
    private var rotorPhase: TimeInterval = 0
    private var bombTimer: TimeInterval
    private let bombInterval: TimeInterval
    private var sway: CGFloat = 0
    private var lifetime: TimeInterval = 0
    /// Set once it breaks off and climbs away; it stops bombing and scores
    /// nothing, it simply leaves.
    private var isLeaving = false
    private var exitDirection: CGFloat = 1

    init(difficulty: CGFloat) {
        bombInterval = max(1.0, 2.2 - Double(min(1, difficulty)) * 0.9)
        bombTimer = 1.2
        super.init()
        team = .enemy
        airborne = true
        scoreValue = GameConfig.scoreMadBomber
        setArt(Art.heliBody)
        hitSize = CGSize(width: 30, height: 50)
        node.zPosition = ZOrder.air

        rotor.texture = Atlas.shared.texture(Art.heliRotor[0])
        rotor.size = Art.heliRotor[0].size
        rotor.alpha = 0.75
        rotor.zPosition = 1
        node.addChild(rotor)

        // A shadow on the road sells the altitude.
        let shadow = SKSpriteNode(color: SKColor(white: 0, alpha: 0.28),
                                  size: CGSize(width: 26, height: 40))
        shadow.position = CGPoint(x: 10, y: -12)
        shadow.zPosition = -1
        node.addChild(shadow)
    }

    override func update(dt: TimeInterval, world: GameWorld) {
        let d = CGFloat(dt)
        let player = world.player

        rotorPhase += dt * 22
        let spinning = Art.heliRotor[Int(rotorPhase) % Art.heliRotor.count]
        rotor.texture = Atlas.shared.texture(spinning)
        rotor.size = spinning.size

        lifetime += dt
        if !isLeaving, lifetime >= MadBomber.patrolDuration {
            isLeaving = true
            exitDirection = x < GameConfig.canvasWidth / 2 ? -1 : 1
        }

        if isLeaving {
            // Break off and climb away up the road.
            speed = player.speed + 260
            worldY += speed * d
            x += exitDirection * 90 * d
            return
        }

        // Hover above and ahead of the player, weaving side to side.
        sway += d
        let targetX = player.x + sin(sway * 1.6) * 55
        x += (targetX - x) * min(1, d * 2.2)
        let targetGap: CGFloat = 150
        let gap = worldY - player.worldY
        speed = player.speed + (targetGap - gap) * 0.9
        worldY += speed * d

        bombTimer -= dt
        if bombTimer <= 0, world.isOnScreen(worldY, margin: 10),
           player.isControllable {
            bombTimer = bombInterval
            let bomb = Bomb()
            bomb.x = x
            bomb.worldY = worldY - 8
            // Bombs fall behind the helicopter, onto the player's path.
            bomb.velocity = CGVector(dx: 0, dy: -40)
            world.spawn(bomb)
        }
    }

    override func onDestroyed(world: GameWorld) {
        rotor.removeFromParent()
    }
}
