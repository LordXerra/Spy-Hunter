import SpriteKit

final class GameScene: SKScene, GameWorld {

    // MARK: - World

    /// Built in `didMove`; exposed non-optionally to satisfy `GameWorld`.
    private var roadStorage: RoadManager!
    var road: RoadManager { roadStorage }

    private(set) var player = Player()
    private(set) var cameraY: CGFloat = 0

    private let world = SKNode()
    private var effects: EffectsSystem!
    private let director = SpawnDirector()
    private var scores = ScoreManager()

    private var entities: [RoadEntity] = []
    private var projectiles: [Projectile] = []
    private var pendingEntities: [RoadEntity] = []
    private var pendingProjectiles: [Projectile] = []

    private var playerScreenY: CGFloat { GameConfig.canvasHeight * GameConfig.playerScreenY }

    /// Where the player's sprite is drawn. Normally fixed, but a replacement
    /// boat rises into it from below the bottom edge.
    private var currentPlayerScreenY: CGFloat {
        let rise = max(0, min(1, player.entryRise))
        return -34 + (playerScreenY + 34) * rise
    }

    // MARK: - State

    private var lastUpdate: TimeInterval = 0
    private var isPausedByPlayer = false
    private var isGameOver = false
    private var fireCooldown: TimeInterval = 0
    private var weaponCooldown: TimeInterval = 0
    private var respawnTimer: TimeInterval = 0
    private var shakeAmount: CGFloat = 0
    /// Most recent frame delta, shared with per-entity timers.
    private var lastFrameDelta: TimeInterval = 0
    /// Throttles impact sparks and sound while two cars stay in contact.
    private var contactFxCooldown: TimeInterval = 0
    /// World-Y of every boathouse already built, so each is spawned once.
    private var spawnedTransitions: Set<CGFloat> = []

    // MARK: - HUD

    /// Fog bank drawn over the play area during foggy stretches.
    private var fogOverlay: SKSpriteNode!
    private var currentWeather: Weather = .clear
    /// The van the player is currently riding inside, if any.
    private var vanRide: WeaponsVan?
    /// Non-nil while the pause menu is open.
    private var pauseMenu: PauseMenu?
    /// The van the player is currently rolling out of at the start of a life.
    private var openingVan: WeaponsVan?

    private let hud = SKNode()
    private var scoreLabel: BitmapLabel!
    private var hiLabel: BitmapLabel!
    private var timerLabel: BitmapLabel!
    private var weaponLabel: BitmapLabel!
    private var messageLabel: BitmapLabel!
    private var carIcons: [SKSpriteNode] = []

    // MARK: - Setup

    override func didMove(to view: SKView) {
        scaleMode = .aspectFit
        anchorPoint = .zero
        backgroundColor = .black
        InputManager.shared.clearKeyboard()

        addChild(world)
        roadStorage = RoadManager(parent: world)
        effects = EffectsSystem(parent: world)

        player.node.position.y = playerScreenY
        world.addChild(player.node)
        player.worldY = 0
        player.x = road.centreX(0)
        cameraY = player.worldY - playerScreenY
        beginOpening()

        buildWeatherOverlay()
        buildHUD()

        scores.onExtraCar = { [weak self] in
            AudioManager.shared.play(.extraCar)
            self?.flashMessage("EXTRA CAR")
        }

        AudioManager.shared.playMusic(.game)
        AudioManager.shared.startEngineNote()
        flashMessage("GET READY")
    }

    override func willMove(from view: SKView) {
        AudioManager.shared.stopEngineNote()
    }

    // MARK: - GameWorld

    func spawn(_ entity: RoadEntity) { pendingEntities.append(entity) }
    func spawn(_ projectile: Projectile) { pendingProjectiles.append(projectile) }

    var enemyCount: Int {
        entities.filter { $0.alive && $0.team == .enemy }.count
            + pendingEntities.filter { $0.team == .enemy }.count
    }

    var airborneEnemyCount: Int {
        entities.filter { $0.alive && $0.airborne && $0.team == .enemy }.count
            + pendingEntities.filter { $0.airborne && $0.team == .enemy }.count
    }

    var hasWeaponsVan: Bool {
        entities.contains { $0.alive && $0 is WeaponsVan }
            || pendingEntities.contains { $0 is WeaponsVan }
    }

    func isOccupied(x: CGFloat, worldY: CGFloat, radius: CGFloat) -> Bool {
        let check = { (e: RoadEntity) -> Bool in
            e.hitSize != .zero
                && abs(e.worldY - worldY) < radius
                && abs(e.x - x) < radius * 0.7
        }
        return entities.contains { $0.alive && check($0) } || pendingEntities.contains(where: check)
    }

    func explode(at point: CGPoint, size: ExplosionSize, water: Bool) {
        effects.explode(x: point.x, worldY: point.y + cameraY, size: size, water: water)
    }

    func addScore(_ points: Int) { scores.add(points) }
    func applyPenalty(_ seconds: TimeInterval) { scores.applyPenalty(seconds) }
    func shake(_ amount: CGFloat) { shakeAmount = max(shakeAmount, amount) }

    /// Convenience for world-space explosions.
    private func explodeWorld(x: CGFloat, worldY: CGFloat, size: ExplosionSize) {
        effects.explode(x: x, worldY: worldY, size: size, water: road.terrain == .water)
        shake(size == .large ? 7 : size == .medium ? 4 : 2)
        InputManager.shared.rumble(intensity: size == .large ? 1.0 : 0.55,
                                   duration: size == .large ? 0.35 : 0.15)
    }

    // MARK: - Loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 0 : min(1.0 / 30.0, currentTime - lastUpdate)
        lastUpdate = currentTime

        let input = InputManager.shared
        input.update()
        // While the pause menu is up it takes all input and the world is frozen.
        if let menu = pauseMenu {
            menu.update(dt: max(dt, 1.0 / 60.0), input: input)
            return
        }
        if (input.wasPressed(.back) || input.wasPressed(.pause)) && !isGameOver {
            openPauseMenu()
            return
        }
        guard dt > 0 else { return }

        if isGameOver {
            respawnTimer -= dt
            if respawnTimer <= 0 { finishGame() }
            return
        }

        stepWorld(dt: dt, input: input)
        updateHUD()
    }

    /// Sim-only: steers toward the middle of the road. Without it the headless
    /// player drifts onto the verge and crawls at minimum speed, which is slower
    /// than most traffic and makes the simulation unrepresentative.
    var autopilot = false

    private func stepWorld(dt: TimeInterval, input: InputManager) {
        lastFrameDelta = dt
        contactFxCooldown = max(0, contactFxCooldown - dt)
        updateVanRide(dt: dt)
        let previousY = player.worldY

        // --- Player ---
        if respawnTimer > 0 {
            respawnTimer -= dt
            if respawnTimer <= 0 { beginOpening() }
        }
        updateOpening()
        var steer = input.steerAxis
        var throttle = input.throttleAxis
        if autopilot {
            let target = road.nearestBranchCentre(x: player.x, worldY: player.worldY)
            steer = max(-1, min(1, (target - player.x) / 26))
            throttle = 0
        }
        player.update(dt: dt,
                      steer: player.isControllable ? steer : 0,
                      throttle: player.isControllable ? throttle : 0,
                      road: road)

        // Clamp so being carried into or out of a van cannot bank distance
        // points for a jump the car did not actually drive.
        let travelled = max(0, min(player.worldY - previousY,
                                   player.speed * CGFloat(dt) * 2))
        cameraY = player.worldY - playerScreenY

        // --- Weapons ---
        fireCooldown -= dt
        weaponCooldown -= dt
        if player.isVulnerable && !player.isTransforming {
            if input.isHeld(.fire) && fireCooldown <= 0 { firePrimary() }
            if input.wasPressed(.weapon) && weaponCooldown <= 0 { deployRearWeapon() }
        }

        // --- Track ---
        let ramp = Settings.difficulty.ramp
        let progress = player.worldY / 24_000 * ramp
        road.difficulty = min(1.4, progress)
        director.difficulty = min(1.6, progress)
        road.update(cameraY: cameraY)
        spawnBoathouses()
        updateTerrain()
        director.update(dt: dt, world: self)

        // --- Entities ---
        for e in entities where e.alive { e.update(dt: dt, world: self) }
        for p in projectiles where p.alive { p.update(dt: dt, world: self) }

        commitPending()
        separateVehicles()
        resolveCollisions()
        enforceRoadEdges()
        cull()
        positionNodes()

        // --- Scoring ---
        scores.update(dt: dt, distance: travelled, terrain: road.terrain)
        updateWeather(dt: dt)
        effects.update(dt: dt, cameraY: cameraY)
        AudioManager.shared.setEngineSpeed(player.normalisedSpeed)
        applyShake(dt: dt)
    }

    private func commitPending() {
        for e in pendingEntities {
            entities.append(e)
            world.addChild(e.node)
        }
        pendingEntities.removeAll()
        for p in pendingProjectiles {
            projectiles.append(p)
            world.addChild(p.node)
        }
        pendingProjectiles.removeAll()
    }

    // MARK: - Opening

    /// The arcade opens each life with the car rolling backwards out of a
    /// weapons van. A starter van is placed just ahead and pulls away while the
    /// player accelerates from a standstill.
    private func beginOpening() {
        // Never leave a previous starter van raised above the player, which is
        // what happens if a life ends before the last opening finished.
        releaseOpeningVan()
        player.respawn(at: road)

        // On the water there is no van: the boat simply resumes. Sending a road
        // lorry out onto the river to drop the player off looks absurd, and it
        // is what happens if this runs regardless of terrain.
        guard !road.isWater(player.worldY) else { return }

        // Only ever one lorry on the road. Anything already out there is
        // destroyed to make way for the one delivering the player.
        for e in entities where e.alive && e is WeaponsVan {
            e.alive = false
            explodeWorld(x: e.x, worldY: e.worldY, size: .medium)
        }

        let van = WeaponsVan()
        van.configureAsStarter()
        van.x = player.x
        // Overlapping the car, so it starts hidden *inside* the trailer and is
        // revealed as the van pulls away.
        van.worldY = player.worldY + 8
        // Drawn above the player for the same reason — otherwise the car simply
        // renders on top of the truck and never looks like it was inside it.
        van.node.zPosition = ZOrder.player + 5
        spawn(van)
        openingVan = van
    }

    /// Closes the starter van up once the player is clear of it.
    private func updateOpening() {
        guard let van = openingVan else { return }
        // Also release it if it has left the world, or the reference would
        // dangle and the reported gap would drift backwards.
        let stillPresent = entities.contains { $0 === van }
            || pendingEntities.contains { $0 === van }
        if player.isControllable || !van.alive || !stillPresent {
            releaseOpeningVan()
        }
    }

    /// Hands the starter van back to normal traffic.
    private func releaseOpeningVan() {
        guard let van = openingVan else { return }
        van.finish()
        van.node.zPosition = ZOrder.vehicle
        openingVan = nil
    }

    // MARK: - Pause

    private func openPauseMenu() {
        guard pauseMenu == nil else { return }
        let menu = PauseMenu()
        menu.onResume = { [weak self] in self?.closePauseMenu() }
        menu.onExit = { [weak self] in
            self?.closePauseMenu()
            self?.returnToTitle()
        }
        addChild(menu)
        pauseMenu = menu
        AudioManager.shared.stopEngineNote()
        AudioManager.shared.play(.blip, volume: 0.5)
    }

    private func closePauseMenu() {
        pauseMenu?.removeFromParent()
        pauseMenu = nil
        // Swallow the frame the menu closed on so the world does not jump.
        lastUpdate = 0
        if !isGameOver { AudioManager.shared.startEngineNote() }
    }

    // MARK: - Weapons van

    private func beginVanRide(_ van: WeaponsVan) {
        player.enterVan()
        van.beginLoading()
        vanRide = van
        AudioManager.shared.play(.weaponPickup, volume: 0.8)
    }

    /// Carries the player along inside the van while it loads them up.
    private func updateVanRide(dt: TimeInterval) {
        guard let van = vanRide, player.isInVan else { return }

        // Blown up with the player aboard: they get out unhurt but empty
        // handed, and it does not cost a life.
        guard van.alive else {
            let bounds = road.bounds(player.worldY)
            let toLeft = abs(player.x - bounds.left) < abs(player.x - bounds.right)
            let side = toLeft ? bounds.left + 18 : bounds.right - 18
            player.exitVan(x: side, worldY: player.worldY - 26)
            player.speed = GameConfig.playerMinSpeed
            vanRide = nil
            flashMessage("VAN DESTROYED")
            return
        }

        // Ease in rather than snapping, so the car is seen driving up the ramp
        // instead of teleporting into the trailer.
        let blend = min(1, CGFloat(dt) * 7)
        player.x += (van.x - player.x) * blend
        player.worldY += ((van.worldY - 8) - player.worldY) * blend
        player.speed = van.speed

        if (player.vanLoadProgress ?? 0) >= Player.vanLoadDuration {
            player.load(van.load)
            van.finish()
            // Roll back out of the rear and pick up where we left off.
            player.exitVan(x: van.x, worldY: van.worldY - 48)
            vanRide = nil
            AudioManager.shared.play(.confirm, volume: 0.7)
            flashMessage("\(van.load.name) LOADED")
        }
    }

    /// Puts a boathouse in the world for each upcoming terrain change, once it
    /// is close enough to be worth building.
    private func spawnBoathouses() {
        let horizon = cameraY + GameConfig.canvasHeight + 200
        for transition in road.transitions {
            guard transition.worldY <= horizon,
                  transition.worldY > cameraY - 100,
                  !spawnedTransitions.contains(transition.worldY) else { continue }
            spawnedTransitions.insert(transition.worldY)

            let house = Boathouse(enteringWater: transition.enteringWater)
            house.worldY = transition.worldY
            let s = road.shape(transition.worldY)
            house.x = s.isForked
                ? (transition.side < 0 ? s.leftCentre : s.rightCentre)
                : s.centre
            spawn(house)
        }
    }

    /// Switches the player between car and boat when they pass through a
    /// boathouse doorway, and re-skins the track.
    private func updateTerrain() {
        // Mark the boathouse as used for its sound and puff of spray; the
        // authority on terrain is the track itself, so the player can never end
        // up as a car on the river even if they clip past the doorway.
        let playerRect = CGRect(x: player.x - 14, y: player.worldY - 18,
                                width: 28, height: 36)
        for e in entities {
            guard let house = e as? Boathouse, !house.used else { continue }
            guard house.doorway.intersects(playerRect) else { continue }
            house.markUsed()
            // Driving through the doorway starts the change; the animation runs
            // while the building hides the vehicle.
            player.beginTransform(toBoat: house.enteringWater)
            flashMessage(house.enteringWater ? "BOAT MODE" : "BACK ON ROAD")
        }

        let waterHere = road.isWater(player.worldY)
        road.terrain = waterHere ? .water : .road
        // Safety net for a player who misses the boathouse entirely. It waits
        // until they are well past the boundary, so it never pre-empts the
        // building itself, which sits set back from the water's edge.
        let settled = road.isWater(player.worldY - 90) == waterHere
        if !player.isTransforming, settled, waterHere != player.isBoat {
            player.beginTransform(toBoat: waterHere)
        }
    }

    /// Wrecks anything that has been run off the road — the player included.
    /// This is what makes barging an agent onto the verge a kill, and what
    /// punishes the player for cutting a bend too tightly.
    private func enforceRoadEdges() {
        let limit = GameConfig.offRoadFatalDistanceEnemy

        for e in entities where e.alive && !e.airborne && e.hitSize != .zero {
            if !(e is Scenery) { e.tickPush(dt: lastFrameDelta) }
            // Scenery is fixed furniture; it is never itself run off the road.
            guard !(e is Scenery), !(e is Boathouse) else { continue }

            // Agents wreck on roadside furniture too.
            if let hit = entities.first(where: {
                $0 is Scenery && $0.alive && $0.overlaps(e)
            }) {
                _ = hit
                e.alive = false
                e.isWrecked = true
                explodeWorld(x: e.x, worldY: e.worldY, size: .medium)
                if e.team == .enemy { addScore(e.scoreValue) }
                continue
            }
            let off = road.offRoadDistance(x: e.x, worldY: e.worldY)
            guard off > limit else { continue }
            e.alive = false
            e.isWrecked = true
            // Off a bridge or causeway it goes into the water rather than
            // crashing, so the effect matches what it hit.
            let intoWater = road.isWaterBeside(x: e.x, worldY: e.worldY)
            effects.explode(x: e.x, worldY: e.worldY,
                            size: .medium, water: intoWater)
            shake(4)
            // Running an agent off the road scores; a civilian is penalised.
            if e.team == .enemy {
                addScore(e.scoreValue)
            } else {
                applyPenalty(e.penalty)
            }
        }

        // The player gets a more forgiving margin than the agents do.
        if player.isVulnerable, !player.isTransforming,
           player.offRoadDistance > GameConfig.offRoadFatalDistance {
            let intoWater = road.isWaterBeside(x: player.x, worldY: player.worldY)
            flashMessage(intoWater ? "SUNK" : "OFF ROAD")
            losePlayerCar(intoWater: intoWater)
        }
    }

    /// Keeps road vehicles from driving through one another. Cars that overlap
    /// are eased apart sideways, and a car that has caught the one in front
    /// slows to its pace rather than passing through it.
    /// Resolves vehicle-on-vehicle contact.
    ///
    /// Previously this only pushed overlapping cars apart geometrically, which
    /// made them grind along each other and appear stuck together. They now
    /// exchange a real impulse split by mass, so a bike cannons off a lorry
    /// while the lorry barely notices — the same way contact with the player
    /// behaves.
    private func separateVehicles() {
        let cars = entities.filter {
            $0.alive && !$0.airborne && $0.hitSize != .zero && !($0 is Scenery)
        }
        guard cars.count > 1 else { return }

        for i in 0..<(cars.count - 1) {
            for j in (i + 1)..<cars.count {
                let a = cars[i], b = cars[j]
                let dx = b.x - a.x
                let dy = b.worldY - a.worldY
                let minX = (a.hitSize.width + b.hitSize.width) / 2 + 2
                let minY = (a.hitSize.height + b.hitSize.height) / 2 + 2
                guard abs(dx) < minX, abs(dy) < minY else { continue }

                // Heavier vehicle yields less of the correction.
                let total = max(0.5, a.mass + b.mass)
                let aShare = b.mass / total
                let bShare = a.mass / total

                let overlapX = minX - abs(dx)
                let overlapY = minY - abs(dy)

                if overlapX < overlapY {
                    let dir: CGFloat = dx >= 0 ? 1 : -1
                    a.x -= dir * overlapX * aShare
                    b.x += dir * overlapX * bShare
                    // Bounce apart rather than sliding along one another.
                    let force: CGFloat = 120
                    a.applyPush(direction: -dir, speed: force * aShare, duration: 0.3)
                    b.applyPush(direction: dir, speed: force * bShare, duration: 0.3)
                    if contactFxCooldown <= 0 {
                        contactFxCooldown = 0.16
                        effects.impactDebris(x: (a.x + b.x) / 2, worldY: a.worldY)
                        AudioManager.shared.play(.crash, volume: 0.45)
                    }
                } else {
                    // Nose to tail: the trailing vehicle checks up behind the
                    // one in front and is nudged back off it.
                    let (front, rear) = dy >= 0 ? (b, a) : (a, b)
                    rear.speed = min(rear.speed, front.speed * 0.88)
                    front.speed = min(front.speed * 1.04, front.speed + 30)
                    front.worldY += overlapY * (dy >= 0 ? bShare : aShare)
                    rear.worldY -= overlapY * (dy >= 0 ? aShare : bShare)
                    if contactFxCooldown <= 0 {
                        contactFxCooldown = 0.16
                        AudioManager.shared.play(.crash, volume: 0.3)
                    }
                }
            }
        }
    }

    private func positionNodes() {
        for e in entities { e.node.position = CGPoint(x: e.x, y: e.worldY - cameraY) }
        for p in projectiles { p.node.position = CGPoint(x: p.x, y: p.worldY - cameraY) }
        player.node.position.y = currentPlayerScreenY
    }

    private func cull() {
        let bottom = cameraY - 120
        let top = cameraY + GameConfig.canvasHeight + 240

        entities.removeAll { e in
            // The van the player is riding, or rolling out of, is exempt from
            // the *distance* cull — but not from the terrain check below, or a
            // starter van simply drives on into the next water section and sits
            // there on the river.
            let inUse = (e === vanRide || e === openingVan) && e.alive
            var gone = inUse ? false : (!e.alive || e.worldY < bottom || e.worldY > top)
            // A car left floating on the river (or a boat beached on tarmac)
            // when the terrain changed under it is quietly retired.
            if !gone, !e.airborne, e.hitSize != .zero, !(e is Scenery), !(e is Boathouse) {
                if road.isWater(e.worldY) != e.isWaterborne { gone = true }
            }
            if gone { e.node.removeFromParent() }
            return gone
        }
        projectiles.removeAll { p in
            let gone = !p.alive || p.worldY < bottom || p.worldY > top
            if gone { p.node.removeFromParent() }
            return gone
        }
    }

    // MARK: - Firing

    private func firePrimary() {
        // Missiles are used automatically when a Mad Bomber is overhead, since
        // the arcade's guns simply cannot reach it.
        let airborneTarget = entities.contains { $0.alive && $0.airborne }
        // In the car, the guns cannot reach a helicopter, so a missile is
        // selected automatically. On the boat the missile lives on its own
        // button, leaving the guns free for the enemy boats.
        if airborneTarget && player.missileAmmo > 0 && !player.isBoat {
            fireCooldown = GameConfig.missileCooldown
            launchMissile()
            return
        }

        fireCooldown = GameConfig.bulletCooldown
        // Dual front-mounted guns.
        for offset in [-7, 7] as [CGFloat] {
            let b = Bullet()
            b.x = player.x + offset
            b.worldY = player.worldY + 22
            b.velocity = CGVector(dx: 0, dy: GameConfig.bulletSpeed)
            spawn(b)
        }
        AudioManager.shared.play(.gunshot, volume: 0.35)

        let flash = Atlas.shared.node(Art.muzzleFlash.randomElement()!)
        flash.position = CGPoint(x: 0, y: 26)
        flash.zPosition = 2
        flash.blendMode = .add
        player.node.addChild(flash)
        flash.run(.sequence([.wait(forDuration: 0.05), .removeFromParent()]))
    }

    /// Fires one missile, spending ammo only when the car is carrying it —
    /// the boat's launcher is standard equipment and never runs dry.
    private func launchMissile() {
        if !player.isBoat { player.missileAmmo = max(0, player.missileAmmo - 1) }
        let m = Missile()
        m.x = player.x
        m.worldY = player.worldY + 24
        m.velocity = CGVector(dx: 0, dy: GameConfig.missileSpeed)
        spawn(m)
        AudioManager.shared.play(.missileLaunch, volume: 0.7)
    }

    /// Space / L2 drops whichever rear weapon is stocked. In boat form it
    /// launches a missile instead: the boat carries them as standard, so the
    /// Mad Bomber always has an answer on the water.
    private func deployRearWeapon() {
        if player.isBoat {
            weaponCooldown = GameConfig.missileCooldown
            launchMissile()
            return
        }
        // A van carries one weapon, so deploy whichever is stocked. Missiles
        // were previously unreachable from this button, which made a van-load
        // of them do nothing at all.
        if player.oilAmmo > 0 {
            player.oilAmmo -= 1
            let slick = OilSlick()
            slick.x = player.x
            slick.worldY = player.worldY - 30
            spawn(slick)
            AudioManager.shared.play(.oilRelease, volume: 0.7)
            weaponCooldown = 0.35
        } else if player.smokeAmmo > 0 {
            player.smokeAmmo -= 1
            let smoke = SmokeScreen()
            smoke.x = player.x
            smoke.worldY = player.worldY - 30
            spawn(smoke)
            AudioManager.shared.play(.smokeRelease, volume: 0.7)
            weaponCooldown = 0.35
        } else if player.missileAmmo > 0 {
            weaponCooldown = GameConfig.missileCooldown
            launchMissile()
        } else {
            weaponCooldown = 0.25
        }
    }

    // MARK: - Collisions

    private func resolveCollisions() {
        let playerRect = CGRect(x: player.x - player.hitSize.width / 2,
                                y: player.worldY - player.hitSize.height / 2,
                                width: player.hitSize.width,
                                height: player.hitSize.height)

        // Projectiles vs entities
        for p in projectiles where p.alive {
            if p.owner == .player {
                for e in entities where e.alive && e.hitSize != .zero {
                    // Rounds pass over roadside furniture rather than "killing"
                    // it, which would otherwise read as a civilian hit.
                    if e is Scenery || e is Boathouse { continue }
                    guard e.overlaps(rect: p.worldRect) else { continue }
                    // Guns cannot touch the helicopter; missiles can.
                    if e.airborne && !p.hitsAir { continue }
                    if !e.airborne && p.hitsAir && e.armoured { continue }
                    p.alive = false
                    hitEntity(e, byMissile: p.hitsAir)
                    break
                }
            } else if p.owner == .enemy && !p.isHazard {
                if player.isVulnerable && p.worldRect.intersects(playerRect) {
                    p.alive = false
                    playerHit(fatal: false)
                }
            }
        }

        // Hazards (oil, smoke, blasts) vs whoever drives into them
        for p in projectiles where p.alive && p.isHazard {
            if p.owner == .player {
                for e in entities where e.alive && !e.airborne && e.team == .enemy {
                    if e.overlaps(rect: p.worldRect) && !e.isWrecked {
                        spinOutEnemy(e)
                    }
                }
            } else {
                // Enemy blasts also destroy weapons vans, including one the
                // player happens to be inside.
                for e in entities where e.alive && e is WeaponsVan {
                    guard e.overlaps(rect: p.worldRect) else { continue }
                    e.alive = false
                    explodeWorld(x: e.x, worldY: e.worldY, size: .large)
                }
                if player.isVulnerable && p.worldRect.intersects(playerRect) {
                    p.alive = false
                    playerHit(fatal: true)
                }
            }
        }

        // Player vs entities — solid while spinning or limping on blown tyres,
        // but intangible mid-transformation inside the boathouse.
        guard player.isVulnerable, !player.isTransforming else { return }
        for e in entities where e.alive && e.hitSize != .zero && !e.airborne {
            guard e.screenRect.intersects(playerRect) else { continue }

            if let van = e as? WeaponsVan {
                // Up the ramp and inside; clipping the side is just a bump.
                if van.isReceiving && van.entryRect.intersects(playerRect) {
                    beginVanRide(van)
                    return
                }
                shove(e)
                continue
            }

            // Roadside furniture is solid — hitting it wrecks the car.
            if e is Scenery {
                explodeWorld(x: player.x, worldY: player.worldY, size: .large)
                flashMessage("CRASHED")
                losePlayerCar()
                return
            }

            switch e.team {
            case .enemy:
                if let blade = e as? Switchblade, blade.bladesOut {
                    // Only the extended slashers cut. They take out the tyres,
                    // costing the player steering for a few seconds.
                    player.blowTyres(pushedToward: player.x < e.x ? -1 : 1)
                    effects.impactDebris(x: (e.x + player.x) / 2, worldY: e.worldY)
                    flashMessage("TYRES SLASHED")
                    shake(5)
                } else {
                    // Blades in — this is a fair fight, so barge it off.
                    shove(e)
                }
            case .civilian, .friendly:
                // Traffic can be run off the road too, though wrecking a
                // civilian is penalised in enforceRoadEdges().
                shove(e)
            }
        }
    }

    /// A bullet or missile connected.
    private func hitEntity(_ e: RoadEntity, byMissile: Bool) {
        if e.armoured && !byMissile {
            // Bulletproof — rounds spark off the plating however many land.
            effects.sparks(x: e.x, worldY: e.worldY + 12)
            AudioManager.shared.play(.ricochet, volume: 0.35)
            return
        }
        switch e.team {
        case .enemy:
            // A missile finishes anything outright; guns take a few rounds.
            e.hitPoints = byMissile ? 0 : e.hitPoints - 1
            if e.hitPoints > 0 {
                e.flashHit()
                effects.sparks(x: e.x, worldY: e.worldY + 8)
                AudioManager.shared.play(.ricochet, volume: 0.25)
                return
            }
            destroy(e, awardPoints: true)
        case .civilian, .friendly:
            // The arcade withholds points rather than deducting them.
            destroy(e, awardPoints: false)
            applyPenalty(e.penalty)
            flashMessage("CIVILIAN HIT")
        }
    }

    private func destroy(_ e: RoadEntity, awardPoints: Bool) {
        e.alive = false
        e.onDestroyed(world: self)
        let size: ExplosionSize = e.airborne ? .large : .medium
        explodeWorld(x: e.x, worldY: e.worldY, size: size)
        if awardPoints { addScore(e.scoreValue) }
    }

    /// Oil or smoke put an agent into a spin, which finishes it off.
    private func spinOutEnemy(_ e: RoadEntity) {
        e.isWrecked = true
        e.alive = false
        explodeWorld(x: e.x, worldY: e.worldY, size: .medium)
        addScore(e.scoreValue)
        AudioManager.shared.play(.skid, volume: 0.5)
    }

    /// Player rams an agent: shove it sideways, and if it reaches the verge it
    /// is run off the road — the only way to score against the Road Lord.
    /// Barges a vehicle sideways. Everything on the road can be shunted off,
    /// but how far depends on what it is: a motorbike is thrown clear, a lorry
    /// scarcely moves and costs the player most of their speed.
    ///
    /// The shove also stops the vehicle correcting its line for a moment, so a
    /// sustained barge walks it onto the verge — the only way past a Road Lord.
    /// `enforceRoadEdges()` wrecks whatever ends up over the line.
    private func shove(_ e: RoadEntity) {
        let d = CGFloat(lastFrameDelta)
        let direction: CGFloat = e.x < player.x ? -1 : 1
        let weight = max(0.25, e.mass)

        // Sustained contact keeps shoving, and the impulse carries on after the
        // vehicles part. Light things travel much further for the same hit.
        e.x += direction * (150 / weight) * d
        e.applyPush(direction: direction,
                    speed: min(430, 200 / weight),
                    duration: 1.1)

        // The player is nudged back in proportion to what they hit, and bleeds
        // speed the same way. Per-second, since contact resolves every frame.
        player.x -= direction * (18 * weight) * d
        player.speed = max(GameConfig.playerMinSpeed,
                           player.speed - (190 * weight) * d)

        if contactFxCooldown <= 0 {
            contactFxCooldown = 0.18
            let volume = Float(min(1.0, 0.5 + weight * 0.2))
            if road.terrain == .water {
                effects.explode(x: (e.x + player.x) / 2, worldY: e.worldY,
                                size: .small, water: true)
                AudioManager.shared.play(.splash, volume: volume)
            } else {
                effects.impactDebris(x: (e.x + player.x) / 2, worldY: e.worldY)
                // Heavier vehicles land a heavier hit.
                AudioManager.shared.play(.crash, volume: volume)
            }
            shake(min(5, 2 + weight))
        }
    }

    private func playerHit(fatal: Bool) {
        guard player.isVulnerable else { return }
        // A boat cannot spin out of a hit the way a car does — it goes down.
        if fatal || !player.spinsWhenHit {
            losePlayerCar()
        } else {
            player.spinOut()
            effects.sparks(x: player.x, worldY: player.worldY)
        }
    }

    private func losePlayerCar(intoWater: Bool = false) {
        effects.explode(x: player.x, worldY: player.worldY,
                        size: .large, water: intoWater || road.terrain == .water)
        shake(7)
        InputManager.shared.rumble(intensity: 1.0, duration: 0.35)
        player.destroy()

        if scores.loseCar() {
            respawnTimer = 1.2
            if !scores.hasUnlimitedCars { refreshCarIcons() }
        } else {
            isGameOver = true
            respawnTimer = 2.6
            flashMessage("GAME OVER")
            AudioManager.shared.stopEngineNote()
        }
    }

    private func applyShake(dt: TimeInterval) {
        guard shakeAmount > 0.05 else {
            world.position = .zero
            shakeAmount = 0
            return
        }
        world.position = CGPoint(x: CGFloat.random(in: -shakeAmount...shakeAmount),
                                 y: CGFloat.random(in: -shakeAmount...shakeAmount))
        shakeAmount *= pow(0.02, dt)
    }

    // MARK: - HUD

    private func buildHUD() {
        hud.zPosition = ZOrder.hud
        addChild(hud)

        let top = SKSpriteNode(color: SKColor(white: 0, alpha: 0.55),
                               size: CGSize(width: GameConfig.canvasWidth, height: 30))
        top.position = CGPoint(x: GameConfig.canvasWidth / 2, y: GameConfig.canvasHeight - 15)
        hud.addChild(top)

        let scoreCaption = BitmapLabel("SCORE", scale: 0.52, tint: SKColor(white: 0.65, alpha: 1),
                                       tracking: -3, align: .left)
        scoreCaption.position = CGPoint(x: 5, y: GameConfig.canvasHeight - 8)
        hud.addChild(scoreCaption)

        scoreLabel = BitmapLabel("0", scale: 0.72, tint: .white, tracking: -3, align: .left)
        scoreLabel.position = CGPoint(x: 5, y: GameConfig.canvasHeight - 21)
        hud.addChild(scoreLabel)

        let hiCaption = BitmapLabel("HI", scale: 0.52, tint: SKColor(white: 0.65, alpha: 1),
                                    tracking: -3, align: .right)
        hiCaption.position = CGPoint(x: GameConfig.canvasWidth - 5, y: GameConfig.canvasHeight - 8)
        hud.addChild(hiCaption)

        hiLabel = BitmapLabel(String(HighScoreStore.shared.topScore), scale: 0.72,
                              tint: SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1),
                              tracking: -3, align: .right)
        hiLabel.position = CGPoint(x: GameConfig.canvasWidth - 5, y: GameConfig.canvasHeight - 21)
        hud.addChild(hiLabel)

        let bottom = SKSpriteNode(color: SKColor(white: 0, alpha: 0.55),
                                  size: CGSize(width: GameConfig.canvasWidth, height: 24))
        bottom.position = CGPoint(x: GameConfig.canvasWidth / 2, y: 12)
        hud.addChild(bottom)

        weaponLabel = BitmapLabel("", scale: 0.52, tint: SKColor(white: 0.85, alpha: 1),
                                  tracking: -3, align: .center)
        weaponLabel.position = CGPoint(x: GameConfig.canvasWidth / 2, y: 12)
        hud.addChild(weaponLabel)

        timerLabel = BitmapLabel("999", scale: 0.78,
                                 tint: SKColor(red: 0.3, green: 1, blue: 0.4, alpha: 1),
                                 tracking: -3, align: .right)
        timerLabel.position = CGPoint(x: GameConfig.canvasWidth - 5, y: 12)
        hud.addChild(timerLabel)

        messageLabel = BitmapLabel("", scale: 1.0,
                                   tint: SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1),
                                   tracking: -3, align: .center)
        messageLabel.position = CGPoint(x: GameConfig.canvasWidth / 2,
                                        y: GameConfig.canvasHeight * 0.62)
        messageLabel.zPosition = ZOrder.overlay
        hud.addChild(messageLabel)
    }

    /// A soft grey bank that thickens toward the top of the screen, so fog
    /// hides what is coming rather than simply dimming everything.
    private func buildWeatherOverlay() {
        let height = GameConfig.canvasHeight
        fogOverlay = SKSpriteNode(color: SKColor(white: 0.80, alpha: 1),
                                  size: CGSize(width: GameConfig.canvasWidth, height: height))
        fogOverlay.position = CGPoint(x: GameConfig.canvasWidth / 2, y: height / 2)
        fogOverlay.zPosition = ZOrder.smoke + 5
        fogOverlay.alpha = 0
        addChild(fogOverlay)

        // Denser ahead of the player than behind, using a stack of bands.
        for i in 0..<6 {
            let band = SKSpriteNode(color: SKColor(white: 0.85, alpha: CGFloat(i) * 0.055),
                                    size: CGSize(width: GameConfig.canvasWidth, height: height / 6))
            band.position = CGPoint(x: 0, y: -height / 2 + height / 12 + CGFloat(i) * height / 6)
            fogOverlay.addChild(band)
        }
    }

    private func updateWeather(dt: TimeInterval) {
        let weather = road.weather(player.worldY)
        if weather != currentWeather {
            currentWeather = weather
            switch weather {
            case .fog: flashMessage("FOG")
            case .ice: flashMessage("ICE")
            case .clear: break
            }
        }
        let targetAlpha: CGFloat = weather == .fog ? 0.55 : 0
        fogOverlay.alpha += (targetAlpha - fogOverlay.alpha) * min(1, CGFloat(dt) * 1.5)
    }

    private func refreshCarIcons() {
        carIcons.forEach { $0.removeFromParent() }
        carIcons.removeAll()
        guard scores.introOver else { return }
        for i in 0..<min(scores.cars, 6) {
            let icon = Atlas.shared.node(Art.playerCar)
            icon.setScale(0.32)
            icon.position = CGPoint(x: 13 + CGFloat(i) * 13, y: 12)
            hud.addChild(icon)
            carIcons.append(icon)
        }
    }

    private func flashMessage(_ text: String) {
        messageLabel.text = text
        messageLabel.alpha = text.isEmpty ? 0 : 1
        messageLabel.removeAllActions()
        guard !text.isEmpty else { return }
        messageLabel.run(.sequence([.wait(forDuration: 1.3), .fadeOut(withDuration: 0.5)]))
    }

    private func updateHUD() {
        scoreLabel.text = String(scores.score)
        timerLabel.text = scores.introOver ? "" : String(scores.displayCounter)

        var parts: [String] = []
        if player.isBoat {
            parts.append("MSL")
        } else if player.missileAmmo > 0 {
            parts.append("MSL \(player.missileAmmo)")
        }
        if player.oilAmmo > 0 { parts.append("OIL \(player.oilAmmo)") }
        if player.smokeAmmo > 0 { parts.append("SMK \(player.smokeAmmo)") }
        weaponLabel.text = parts.joined(separator: "  ")

        if scores.introOver && carIcons.count != min(scores.cars, 6) { refreshCarIcons() }
    }

    // MARK: - Debug

    /// One-line world state, used by the headless simulation harness so the
    /// game can be verified without depending on the window being rendered.
    var debugSummary: String {
        let terrain = road.isWater(player.worldY) ? "water" : "road "
        let weather: String
        switch road.weather(player.worldY) {
        case .clear: weather = "clear"
        case .fog:   weather = "fog  "
        case .ice:   weather = "ice  "
        }
        var vehicle = player.isBoat ? "boat" : "car "
        if player.isInVan { vehicle = "inVan" }
        if player.isTransforming { vehicle = "morph" }
        let ammo = "m\(player.missileAmmo) o\(player.oilAmmo) s\(player.smokeAmmo)"
        let vans = entities.filter { $0 is WeaponsVan }.count
        let phase = scores.introOver ? "post" : "intro:\(scores.displayCounter)"
        let vansOnWater = entities.filter { $0 is WeaponsVan && road.isWater($0.worldY) }.count
        let heli = entities.filter { $0.alive && $0.airborne }.count
        let slicks = projectiles.filter { $0.isHazard && $0.owner == .player }.count
        // While the opening runs, report how far the car has emerged from the
        // starter van — it must grow, or the reveal reads backwards.
        let gap = openingVan.map { String(format: " vanGap=%+.0f", $0.worldY - player.worldY) } ?? ""
        return String(format:
            "y=%6.0f score=%5d cars=%d %@ %@ %@ ammo=%@ ents=%2d vans=%d proj=%2d drops=%d heli=%d wetVans=%d %@",
            player.worldY, scores.score, scores.cars, terrain, weather,
            vehicle, ammo, entities.count, vans, projectiles.count, slicks, heli, vansOnWater, phase) + gap
    }

    /// Test hook for the headless sim, which has no input and so never
    /// exercises the weapons. Arms the car once, then fires both.
    func simulateWeapons() {
        if player.missileAmmo == 0, player.oilAmmo == 0, player.smokeAmmo == 0 {
            player.load(.missiles)
            player.load(.oil)
            player.load(.smoke)
        }
        guard player.isVulnerable, !player.isTransforming else { return }
        if fireCooldown <= 0 { firePrimary() }
        if weaponCooldown <= 0 { deployRearWeapon() }
    }

    /// Drives one simulation step directly, bypassing the render loop.
    func simulateStep(dt: TimeInterval) {
        lastFrameDelta = dt
        contactFxCooldown = max(0, contactFxCooldown - dt)
        updateVanRide(dt: dt)
        guard !isGameOver else { return }
        stepWorld(dt: dt, input: InputManager.shared)
        updateHUD()
    }

    // MARK: - Exit

    private func finishGame() {
        AudioManager.shared.stopEngineNote()
        let final = scores.score
        if HighScoreStore.shared.qualifies(final) {
            let entry = HighScoreEntryScene(size: GameConfig.canvasSize, score: final)
            entry.scaleMode = .aspectFit
            view?.presentScene(entry, transition: .fade(withDuration: 0.5))
        } else {
            returnToTitle()
        }
    }

    private func returnToTitle() {
        AudioManager.shared.stopEngineNote()
        let scene = TitleScene(size: GameConfig.canvasSize)
        scene.scaleMode = .aspectFit
        view?.presentScene(scene, transition: .fade(withDuration: 0.4))
    }
}
