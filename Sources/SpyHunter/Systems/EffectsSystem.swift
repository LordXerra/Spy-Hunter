import SpriteKit

enum ExplosionSize {
    case small      // bullet strike
    case medium     // car destroyed
    case large      // player car, helicopter, big collision

    var scale: CGFloat {
        switch self {
        case .small: return 0.8
        case .medium: return 1.25
        case .large: return 1.9
        }
    }
    var debrisCount: Int {
        switch self {
        case .small: return 4
        case .medium: return 9
        case .large: return 16
        }
    }
    var sparkCount: Int {
        switch self {
        case .small: return 14
        case .medium: return 34
        case .large: return 70
        }
    }
}

/// Explosions, debris and impact sparks.
///
/// Every effect is anchored in world space so it scrolls with the road, and is
/// built from three layers — a sprite-sheet fireball, generated particle bursts,
/// and tumbling debris chunks — which together read as a considerable upgrade
/// on the arcade's single-sprite blast.
final class EffectsSystem {

    private let root = SKNode()

    /// A node pinned to a world position, removed when its life runs out.
    private struct Anchored {
        let node: SKNode
        var worldX: CGFloat
        var worldY: CGFloat
        var vx: CGFloat = 0
        var vy: CGFloat = 0
        var spin: CGFloat = 0
        var life: TimeInterval
        let maxLife: TimeInterval
        var drag: CGFloat = 1
        var fades = false
    }

    private var items: [Anchored] = []

    private lazy var sparkTexture: SKTexture = EffectsSystem.dot(diameter: 8, soft: false)
    private lazy var smokeTexture: SKTexture = EffectsSystem.dot(diameter: 24, soft: true)

    init(parent: SKNode) {
        root.zPosition = ZOrder.explosion
        parent.addChild(root)
    }

    // MARK: - Public effects

    func explode(x: CGFloat, worldY: CGFloat, size: ExplosionSize, water: Bool) {
        if water {
            waterBurst(x: x, worldY: worldY, size: size)
        } else {
            fireball(x: x, worldY: worldY, size: size)
        }
        AudioManager.shared.play(size == .large ? .bigExplosion : .explosion,
                                 volume: size == .small ? 0.5 : 0.9)
    }

    /// Bullets striking armour — sparks only, no fire.
    func sparks(x: CGFloat, worldY: CGFloat) {
        let emitter = SKEmitterNode()
        emitter.particleTexture = sparkTexture
        emitter.particleBirthRate = 900
        emitter.numParticlesToEmit = 10
        emitter.particleLifetime = 0.28
        emitter.particleLifetimeRange = 0.15
        emitter.particleSpeed = 130
        emitter.particleSpeedRange = 80
        emitter.emissionAngle = .pi / 2
        emitter.emissionAngleRange = .pi * 2
        emitter.particleAlpha = 1
        emitter.particleAlphaSpeed = -3
        emitter.particleScale = 0.28
        emitter.particleScaleRange = 0.15
        emitter.particleScaleSpeed = -0.5
        emitter.particleColor = SKColor(red: 1, green: 0.9, blue: 0.5, alpha: 1)
        emitter.particleColorBlendFactor = 1
        emitter.particleBlendMode = .add
        emitter.targetNode = root
        add(node: emitter, x: x, worldY: worldY, life: 0.6)
    }

    /// Small impact puff when two cars touch.
    func impactDebris(x: CGFloat, worldY: CGFloat) {
        sparks(x: x, worldY: worldY)
        spawnDebris(x: x, worldY: worldY, count: 3, power: 90)
    }

    // MARK: - Composition

    private func fireball(x: CGFloat, worldY: CGFloat, size: ExplosionSize) {
        let atlas = Atlas.shared

        // 1. Sprite-sheet fireball, played once and scaled to the blast size.
        let frames: [SpriteRect]
        switch size {
        case .small:  frames = Art.explosionSmall
        case .medium: frames = Art.explosionBig
        case .large:  frames = Art.starBurst + Art.explosionBig
        }
        let fire = atlas.node(frames[0])
        fire.setScale(size.scale)
        fire.blendMode = .add
        fire.run(.sequence([
            .animate(with: atlas.textures(frames), timePerFrame: 0.055,
                     resize: true, restore: false),
            .fadeOut(withDuration: 0.12),
        ]))
        add(node: fire, x: x, worldY: worldY, life: Double(frames.count) * 0.055 + 0.2)

        // 2. A brief white flash so the blast reads instantly.
        let flash = SKSpriteNode(texture: smokeTexture)
        flash.size = CGSize(width: 44 * size.scale, height: 44 * size.scale)
        flash.blendMode = .add
        flash.color = .white
        flash.colorBlendFactor = 1
        flash.run(.group([
            .scale(to: 2.2, duration: 0.22),
            .fadeOut(withDuration: 0.22),
        ]))
        add(node: flash, x: x, worldY: worldY, life: 0.3)

        // 3. Spark burst.
        let sparkEmitter = SKEmitterNode()
        sparkEmitter.particleTexture = sparkTexture
        sparkEmitter.particleBirthRate = 4000
        sparkEmitter.numParticlesToEmit = size.sparkCount
        sparkEmitter.particleLifetime = 0.55
        sparkEmitter.particleLifetimeRange = 0.4
        sparkEmitter.particleSpeed = 170 * size.scale
        sparkEmitter.particleSpeedRange = 130
        sparkEmitter.emissionAngle = .pi / 2
        sparkEmitter.emissionAngleRange = .pi * 2
        sparkEmitter.yAcceleration = -70
        sparkEmitter.particleAlpha = 1
        sparkEmitter.particleAlphaSpeed = -1.6
        sparkEmitter.particleScale = 0.34 * size.scale
        sparkEmitter.particleScaleRange = 0.2
        sparkEmitter.particleScaleSpeed = -0.35
        sparkEmitter.particleColorSequence = SKKeyframeSequence(
            keyframeValues: [SKColor.white,
                             SKColor(red: 1, green: 0.85, blue: 0.25, alpha: 1),
                             SKColor(red: 1, green: 0.35, blue: 0.05, alpha: 1)],
            times: [0, 0.3, 1])
        sparkEmitter.particleColorBlendFactor = 1
        sparkEmitter.particleBlendMode = .add
        sparkEmitter.targetNode = root
        add(node: sparkEmitter, x: x, worldY: worldY, life: 1.2)

        // 4. Rolling smoke that lingers after the fire is gone.
        let smoke = SKEmitterNode()
        smoke.particleTexture = smokeTexture
        smoke.particleBirthRate = 90
        smoke.numParticlesToEmit = Int(10 * size.scale)
        smoke.particleLifetime = 1.3
        smoke.particleLifetimeRange = 0.7
        smoke.particleSpeed = 34
        smoke.particleSpeedRange = 26
        smoke.emissionAngle = .pi / 2
        smoke.emissionAngleRange = .pi * 2
        smoke.particleAlpha = 0.55
        smoke.particleAlphaSpeed = -0.45
        smoke.particleScale = 0.5 * size.scale
        smoke.particleScaleRange = 0.3
        smoke.particleScaleSpeed = 0.55
        smoke.particleColor = SKColor(white: 0.35, alpha: 1)
        smoke.particleColorBlendFactor = 1
        smoke.particleBlendMode = .alpha
        smoke.zPosition = -1
        smoke.targetNode = root
        add(node: smoke, x: x, worldY: worldY, life: 2.4)

        // 5. Tumbling debris chunks.
        spawnDebris(x: x, worldY: worldY,
                    count: size.debrisCount, power: 130 * size.scale)
    }

    private func waterBurst(x: CGFloat, worldY: CGFloat, size: ExplosionSize) {
        let atlas = Atlas.shared
        let splash = atlas.node(Art.splashBurst)
        splash.setScale(size.scale * 0.7)
        splash.blendMode = .add
        splash.run(.group([
            .scale(to: size.scale * 1.3, duration: 0.4),
            .fadeOut(withDuration: 0.4),
        ]))
        add(node: splash, x: x, worldY: worldY, life: 0.5)

        let spray = SKEmitterNode()
        spray.particleTexture = sparkTexture
        spray.particleBirthRate = 2500
        spray.numParticlesToEmit = size.sparkCount
        spray.particleLifetime = 0.7
        spray.particleLifetimeRange = 0.4
        spray.particleSpeed = 150 * size.scale
        spray.particleSpeedRange = 100
        spray.emissionAngle = .pi / 2
        spray.emissionAngleRange = .pi * 2
        spray.yAcceleration = -180
        spray.particleAlpha = 0.95
        spray.particleAlphaSpeed = -1.2
        spray.particleScale = 0.4 * size.scale
        spray.particleScaleRange = 0.25
        spray.particleColorSequence = SKKeyframeSequence(
            keyframeValues: [SKColor.white,
                             SKColor(red: 0.5, green: 0.8, blue: 1, alpha: 1)],
            times: [0, 1])
        spray.particleColorBlendFactor = 1
        spray.particleBlendMode = .add
        spray.targetNode = root
        add(node: spray, x: x, worldY: worldY, life: 1.3)
    }

    /// Metal chunks flung out from an impact, tumbling and slowing as they go.
    private func spawnDebris(x: CGFloat, worldY: CGFloat, count: Int, power: CGFloat) {
        for _ in 0..<count {
            let rect = Art.debrisChunk.randomElement()!
            let chunk = Atlas.shared.node(rect)
            chunk.zPosition = ZOrder.debris
            let angle = CGFloat.random(in: 0..<(.pi * 2))
            let speed = power * CGFloat.random(in: 0.45...1.3)
            var item = Anchored(node: chunk, worldX: x, worldY: worldY,
                                vx: cos(angle) * speed,
                                vy: sin(angle) * speed,
                                spin: CGFloat.random(in: -14...14),
                                life: Double.random(in: 0.7...1.4),
                                maxLife: 1.4,
                                drag: 0.955,
                                fades: true)
            item.node.setScale(CGFloat.random(in: 0.8...1.5))
            root.addChild(chunk)
            items.append(item)
        }
    }

    // MARK: - Bookkeeping

    private func add(node: SKNode, x: CGFloat, worldY: CGFloat, life: TimeInterval) {
        root.addChild(node)
        items.append(Anchored(node: node, worldX: x, worldY: worldY,
                              life: life, maxLife: life))
    }

    /// Advances debris physics and re-pins every effect to its world position.
    func update(dt: TimeInterval, cameraY: CGFloat) {
        let d = CGFloat(dt)
        var i = 0
        while i < items.count {
            items[i].life -= dt
            if items[i].life <= 0 {
                items[i].node.removeFromParent()
                items.remove(at: i)
                continue
            }
            if items[i].vx != 0 || items[i].vy != 0 {
                items[i].worldX += items[i].vx * d
                items[i].worldY += items[i].vy * d
                let decay = pow(items[i].drag, d * 60)
                items[i].vx *= decay
                items[i].vy *= decay
                items[i].node.zRotation += items[i].spin * d
            }
            let node = items[i].node
            node.position = CGPoint(x: items[i].worldX, y: items[i].worldY - cameraY)
            if items[i].fades {
                node.alpha = min(1, CGFloat(items[i].life / items[i].maxLife) * 2)
            }
            i += 1
        }
    }

    func clear() {
        items.forEach { $0.node.removeFromParent() }
        items.removeAll()
    }

    // MARK: - Generated particle textures

    /// A round particle sprite, optionally with a soft falloff.
    private static func dot(diameter: Int, soft: Bool) -> SKTexture {
        let size = CGSize(width: diameter, height: diameter)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: diameter, height: diameter,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return SKTexture() }

        let r = CGFloat(diameter) / 2
        if soft {
            let colors = [SKColor.white.withAlphaComponent(1).cgColor,
                          SKColor.white.withAlphaComponent(0).cgColor] as CFArray
            if let grad = CGGradient(colorsSpace: cs, colors: colors,
                                     locations: [0, 1]) {
                ctx.drawRadialGradient(grad,
                                       startCenter: CGPoint(x: r, y: r), startRadius: 0,
                                       endCenter: CGPoint(x: r, y: r), endRadius: r,
                                       options: [])
            }
        } else {
            ctx.setFillColor(SKColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(origin: .zero, size: size))
        }
        guard let image = ctx.makeImage() else { return SKTexture() }
        let tex = SKTexture(cgImage: image)
        return tex
    }
}
