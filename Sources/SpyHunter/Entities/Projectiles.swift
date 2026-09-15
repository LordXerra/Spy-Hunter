import SpriteKit

/// Bullets, missiles, bombs and the deployables dropped from the car's back.
class Projectile {

    enum Owner { case player, enemy }

    let node = SKNode()
    let sprite = SKSpriteNode()

    var x: CGFloat = 0
    var worldY: CGFloat = 0
    var velocity = CGVector(dx: 0, dy: 0)
    var alive = true
    var owner: Owner = .player
    var hitSize = CGSize(width: 4, height: 8)
    /// Missiles are the only thing that can reach the Mad Bomber.
    var hitsAir = false
    /// Deployables sit on the road and hurt whoever drives over them.
    var isHazard = false
    var life: TimeInterval = 4

    init() {
        node.addChild(sprite)
        node.zPosition = ZOrder.projectile
    }

    func setArt(_ rect: SpriteRect) {
        sprite.texture = Atlas.shared.texture(rect)
        sprite.size = rect.size
    }

    func update(dt: TimeInterval, world: GameWorld) {
        x += velocity.dx * CGFloat(dt)
        worldY += velocity.dy * CGFloat(dt)
        life -= dt
        if life <= 0 { alive = false }
    }

    var worldRect: CGRect {
        CGRect(x: x - hitSize.width / 2, y: worldY - hitSize.height / 2,
               width: hitSize.width, height: hitSize.height)
    }
}

/// The car's dual front-mounted machine guns — unlimited ammunition.
final class Bullet: Projectile {
    override init() {
        super.init()
        owner = .player
        setArt(Art.bullet)
        sprite.color = SKColor(red: 1, green: 0.95, blue: 0.5, alpha: 1)
        sprite.colorBlendFactor = 0.7
        hitSize = CGSize(width: 5, height: 10)
        life = 1.6
    }
}

/// Return fire from the Enforcer's gunman.
///
/// Drawn deliberately large and bright: the sheet's round is two pixels wide,
/// which made being shot look like the car spinning out for no reason at all.
final class EnemyBullet: Projectile {
    override init() {
        super.init()
        owner = .enemy
        setArt(Art.enemyBullet)
        sprite.size = CGSize(width: 5, height: 14)
        sprite.color = SKColor(red: 1, green: 0.35, blue: 0.15, alpha: 1)
        sprite.colorBlendFactor = 1
        sprite.blendMode = .add
        hitSize = CGSize(width: 6, height: 12)
        life = 2.5

        // A glowing tracer behind it, so the shot reads at a glance.
        let tracer = SKSpriteNode(color: SKColor(red: 1, green: 0.6, blue: 0.2, alpha: 0.55),
                                  size: CGSize(width: 3, height: 22))
        tracer.position = CGPoint(x: 0, y: 11)
        tracer.zPosition = -1
        tracer.blendMode = .add
        node.addChild(tracer)

        sprite.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.55, duration: 0.06),
            .fadeAlpha(to: 1, duration: 0.06),
        ])))
    }
}

/// Surface-to-air missile from the weapons van — the Mad Bomber's only answer.
final class Missile: Projectile {
    private var phase: TimeInterval = 0

    override init() {
        super.init()
        owner = .player
        hitsAir = true
        setArt(Art.missile[0])
        hitSize = CGSize(width: 10, height: 20)
        life = 2.2
    }

    override func update(dt: TimeInterval, world: GameWorld) {
        super.update(dt: dt, world: world)
        // The exhaust plume grows as the motor spins up.
        phase += dt * 18
        let frame = Art.missile[min(Art.missile.count - 1, Int(phase))]
        setArt(frame)
    }
}

/// Dropped by the Mad Bomber; detonates on the road after a short fall.
final class Bomb: Projectile {
    private var fuse: TimeInterval = 1.1

    override init() {
        super.init()
        owner = .enemy
        // Stand-in: the sheet has no dedicated air-dropped bomb, so a piece of
        // debris is tinted dark to read as a falling object.
        setArt(Art.roadDebrisB)
        sprite.color = SKColor(white: 0.12, alpha: 1)
        sprite.colorBlendFactor = 0.85
        hitSize = CGSize(width: 12, height: 12)
        life = 3
        node.zPosition = ZOrder.projectile
    }

    override func update(dt: TimeInterval, world: GameWorld) {
        super.update(dt: dt, world: world)
        fuse -= dt
        // Shrink as it falls, then burst on the road surface.
        let s = max(0.5, CGFloat(fuse / 1.1))
        sprite.setScale(0.7 + s * 0.6)
        if fuse <= 0 && alive {
            alive = false
            world.explode(at: CGPoint(x: x, y: world.screenY(worldY)),
                          size: .medium, water: world.road.terrain == .water)
            world.shake(4)
            // The blast itself is what hurts the player.
            let blast = BlastHazard()
            blast.x = x
            blast.worldY = worldY
            world.spawn(blast)
        }
    }
}

/// Short-lived damaging area left by a bomb detonation.
final class BlastHazard: Projectile {
    override init() {
        super.init()
        owner = .enemy
        isHazard = true
        hitSize = CGSize(width: 34, height: 34)
        life = 0.35
        sprite.alpha = 0
    }
}

/// Oil slick dropped from the back of the car: enemies that drive through it
/// spin out.
final class OilSlick: Projectile {
    private var age: TimeInterval = 0

    override init() {
        super.init()
        owner = .player
        isHazard = true
        setArt(Art.oilSlick[0])
        hitSize = CGSize(width: 30, height: 24)
        life = 7
        node.zPosition = ZOrder.slick
    }

    override func update(dt: TimeInterval, world: GameWorld) {
        super.update(dt: dt, world: world)
        age += dt
        // Spreads out over the first half-second.
        let i = min(Art.oilSlick.count - 1, Int(age * 6))
        setArt(Art.oilSlick[i])
        if life < 1.5 { sprite.alpha = CGFloat(life / 1.5) }
    }
}

/// Smoke screen: blinds pursuers and spins out anything that enters it.
final class SmokeScreen: Projectile {
    private var age: TimeInterval = 0

    override init() {
        super.init()
        owner = .player
        isHazard = true
        setArt(Art.smokeScreen[0])
        hitSize = CGSize(width: 32, height: 28)
        life = 4.5
        node.zPosition = ZOrder.smoke
    }

    override func update(dt: TimeInterval, world: GameWorld) {
        super.update(dt: dt, world: world)
        age += dt
        if age < 0.6 {
            setArt(Art.smokeScreen[min(2, Int(age * 5))])
        } else {
            let i = min(Art.smokeFade.count - 1, Int((age - 0.6) * 2.2))
            setArt(Art.smokeFade[i])
        }
        sprite.setScale(1 + CGFloat(age) * 0.35)
        if life < 1.5 { sprite.alpha = CGFloat(life / 1.5) }
    }
}
