import SpriteKit

/// Roadside objects. Solid: hitting one at speed wrecks a car, which is what
/// makes the verge genuinely dangerous rather than just slow.
final class Scenery: RoadEntity {
    init(rect: SpriteRect, x: CGFloat, worldY: CGFloat) {
        super.init()
        team = .civilian
        setArt(rect)
        self.x = x
        self.worldY = worldY
        // Tight box so only a real collision counts.
        hitSize = CGSize(width: max(6, rect.size.width - 4),
                         height: max(6, rect.size.height - 6))
        node.zPosition = ZOrder.roadside
    }

    override func update(dt: TimeInterval, world: GameWorld) {
        // Scenery is fixed to the world; it only scrolls.
    }
}

/// Decides what appears on the road ahead and when.
///
/// Pressure rises with distance travelled: enemies arrive more often and the
/// dangerous ones start showing up. The weapons van is kept on its own steady
/// cadence so the player always has a route back to ammunition.
final class SpawnDirector {

    private var enemyTimer: TimeInterval = 2.0
    private var civilianTimer: TimeInterval = 1.4
    private var vanTimer: TimeInterval = 14
    private var sceneryTimer: TimeInterval = 0

    /// 0 at the start, rising toward 1 and beyond as the run continues.
    var difficulty: CGFloat = 0
    /// Whether to send road or river traffic.
    var terrain: Terrain = .road

    /// Distance ahead of the top of the screen at which things appear.
    private let spawnMargin: CGFloat = 60

    func reset() {
        enemyTimer = 2.0
        civilianTimer = 1.4
        vanTimer = 14
        sceneryTimer = 0
    }

    func update(dt: TimeInterval, world: GameWorld) {
        let spawnY = world.cameraY + GameConfig.canvasHeight + spawnMargin
        let d = min(1, difficulty)

        // Traffic must match the terrain *where it appears*, not where the
        // player currently is — otherwise cars get spawned onto the river as
        // the player approaches a water section.
        terrain = world.road.isWater(spawnY) ? .water : .road

        // The arcade sends agents at the player a few at a time, not in a pack.
        let maxEnemies = 2 + Int(d * 2)

        enemyTimer -= dt
        if enemyTimer <= 0 {
            enemyTimer = max(1.1, Double.random(in: 2.2...4.2) - Double(d) * 1.0)
            if world.enemyCount < maxEnemies {
                spawnEnemy(at: spawnY, world: world)
            }
        }

        civilianTimer -= dt
        if civilianTimer <= 0 {
            civilianTimer = Double.random(in: 2.2...4.2)
            spawnCivilian(at: spawnY, world: world)
        }

        vanTimer -= dt
        if vanTimer <= 0 {
            vanTimer = Double.random(in: 22...32)
            // Weapons vans are a road feature — a lorry has no business on the
            // river, and the boat carries its own missiles anyway.
            let vanX = world.road.centreX(spawnY)
            if terrain == .water {
                vanTimer = 4          // look again once back on tarmac
            } else if world.hasWeaponsVan {
                // Never two lorries at once — wait for the current one, which
                // includes the van dropping the player off, to clear.
                vanTimer = 4
            } else if !world.isOccupied(x: vanX, worldY: spawnY, radius: 90) {
                let van = WeaponsVan()
                van.x = vanX
                van.worldY = spawnY
                world.spawn(van)
            } else {
                vanTimer = 1.5   // try again shortly
            }
        }

        sceneryTimer -= dt
        if sceneryTimer <= 0 {
            sceneryTimer = Double.random(in: 0.25...0.7)
            spawnScenery(at: spawnY, world: world)
        }
    }

    // MARK: - Choices

    private func spawnEnemy(at y: CGFloat, world: GameWorld) {
        let d = min(1, difficulty)
        var pool: [(weight: Double, make: () -> RoadEntity)]

        // The Mad Bomber is held back until well into a run, and never more
        // than one at a time — two only on expert. Without missiles the player
        // has no answer to it, so a pack of them is unplayable.
        let heliCap = Settings.difficulty.helicopterCap
        let heliAllowed = world.airborneEnemyCount < heliCap

        if terrain == .water {
            // The river brings its own agents, plus the helicopter overhead.
            pool = [
                (3.0, { BarrelDumper(difficulty: self.difficulty) }),
                (2.2, { DoctorTorpedo(difficulty: self.difficulty) }),
            ]
            if difficulty > 0.55, heliAllowed {
                pool.append((1.0 + Double(d), { MadBomber(difficulty: self.difficulty) }))
            }
        } else {
            // Weighted pick; the tougher agents only appear once the player has
            // covered some ground, mirroring the arcade's ramp.
            pool = [(3.0, { Switchblade(difficulty: self.difficulty) })]
            if difficulty > 0.12 {
                pool.append((2.0, { RoadLord(difficulty: self.difficulty) }))
            }
            if difficulty > 0.25 {
                pool.append((1.6, { Enforcer(difficulty: self.difficulty) }))
            }
            if difficulty > 0.8, heliAllowed {
                pool.append((0.9 + Double(d), { MadBomber(difficulty: self.difficulty) }))
            }
        }

        let total = pool.reduce(0) { $0 + $1.weight }
        var pick = Double.random(in: 0..<total)
        for option in pool {
            pick -= option.weight
            if pick <= 0 {
                let e = option.make()
                // Helicopters fly in above the road, so lane spacing is moot.
                if e.airborne {
                    e.worldY = y
                    e.x = world.road.centreX(y)
                    world.spawn(e)
                } else if place(e, at: y, world: world) {
                    world.spawn(e)
                } else {
                    enemyTimer = 0.6   // road was busy; retry shortly
                }
                return
            }
        }
    }

    private func spawnCivilian(at y: CGFloat, world: GameWorld) {
        // On the water these are tugboats and pleasure craft; sinking either is
        // penalised just as running a civilian off the road is.
        let craft: RoadEntity
        if terrain == .water {
            craft = Double.random(in: 0...1) < 0.4 ? Tugboat() : CivilianBoat()
        } else {
            craft = CivilianCar(kind: Int.random(in: 0...4))
        }
        craft.speed = GameConfig.playerCruiseSpeed * CGFloat.random(in: 0.45...0.75)
        if place(craft, at: y, world: world) {
            world.spawn(craft)
        } else {
            civilianTimer = 0.6
        }
    }

    /// Finds a free lane for a new vehicle. Returns false if the road ahead is
    /// already busy, so nothing is ever dropped on top of another car.
    @discardableResult
    private func place(_ e: RoadEntity, at y: CGFloat, world: GameWorld) -> Bool {
        let b = world.road.bounds(y)
        let inset: CGFloat = 20
        guard b.right - inset > b.left + inset else { return false }

        for _ in 0..<6 {
            let x = CGFloat.random(in: (b.left + inset)...(b.right - inset))
            if !world.isOccupied(x: x, worldY: y, radius: 64) {
                e.worldY = y
                e.x = x
                if e.speed == 0 {
                    e.speed = GameConfig.playerCruiseSpeed * CGFloat.random(in: 0.8...1.05)
                }
                return true
            }
        }
        return false
    }

    private func spawnScenery(at y: CGFloat, world: GameWorld) {
        guard world.road.terrain == .road else { return }
        let b = world.road.bounds(y)
        // Trees and fence posts only — the barrels belong on the water.
        let options = [Art.treeA, Art.treeA, Art.treeB, Art.fencePost, Art.fencePostAlt]
        let rect = options.randomElement()!
        let onLeft = Bool.random()
        // Clear the tarmac by at least the sprite's own half-width, so solid
        // scenery never overlaps a lane the player is legitimately driving in.
        let gap = rect.size.width / 2 + CGFloat.random(in: 6...26)
        let x = onLeft ? b.left - gap : b.right + gap
        guard x > 8, x < GameConfig.canvasWidth - 8 else { return }
        guard !world.road.isOnRoad(x: x, worldY: y, margin: 2) else { return }
        // Nothing stands in the water beside a bridge or causeway.
        guard !world.road.isWaterBeside(x: x, worldY: y) else { return }
        world.spawn(Scenery(rect: rect, x: x, worldY: y))
    }
}
