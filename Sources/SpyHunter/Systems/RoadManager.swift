import SpriteKit

/// The terrain the player is currently travelling over.
enum Terrain {
    case road
    case water
}

/// What lies off the side of the road. On a bridge or causeway the verge is
/// open water, so anything barged over the line goes in rather than crashing.
enum Bank {
    case land
    case water
}

/// Driving conditions. The arcade changed the seasons as you drove far enough:
/// fog cut visibility and ice took away your grip.
enum Weather {
    case clear
    case fog
    case ice
}

/// Generates and draws the scrolling track.
///
/// The track is a run of discrete features rather than a continuously snaking
/// line: long straights, decisive bends, stretches that narrow, splits where
/// the road forks around an island, and boathouse branches that lead into the
/// water sections. Control nodes are generated on demand and eased between, so
/// the shape can be queried at any world-Y for spawning and collision.
final class RoadManager {

    // MARK: - Shape

    struct Shape {
        var centre: CGFloat
        var halfWidth: CGFloat
        /// 0 = single carriageway, 1 = fully split into two branches.
        var fork: CGFloat
        var isWater: Bool
        var weather: Weather = .clear
        var bankLeft: Bank = .land
        var bankRight: Bank = .land

        /// Distance from the centre line to each branch's own centre.
        var separation: CGFloat { halfWidth * 0.775 * fork }
        var branchHalfWidth: CGFloat { halfWidth * (1 - 0.525 * fork) }
        var leftCentre: CGFloat { centre - separation }
        var rightCentre: CGFloat { centre + separation }
        /// Full extent of tarmac, including both branches.
        var outerHalfWidth: CGFloat { separation + branchHalfWidth }

        /// Half-width of the island between the branches. Negative while the
        /// road is still merely widening and the two branches overlap.
        var islandHalfWidth: CGFloat { separation - branchHalfWidth }

        /// True only once a real island has opened up. While `fork` is ramping
        /// the branches still overlap, and the road must be drawn and driven as
        /// one carriageway — otherwise edge lines appear down the middle of it.
        var isForked: Bool { islandHalfWidth > 2 }
    }

    private struct TrackNode {
        var offset: CGFloat        // -1 ... +1 lateral position
        var halfWidth: CGFloat
        var fork: CGFloat
        var isWater: Bool
        var weather: Weather = .clear
        var bankLeft: Bank = .land
        var bankRight: Bank = .land
    }

    /// A boathouse where the track changes between road and water.
    struct Transition {
        let worldY: CGFloat
        let enteringWater: Bool
        /// Which side of a fork the boathouse sits on (-1 left, +1 right, 0 centre).
        let side: CGFloat
    }

    // MARK: - State

    private let sliceHeight: CGFloat = 8
    private let sliceCount: Int
    private let root = SKNode()
    private var slices: [RoadSlice] = []
    private let ground: SKSpriteNode

    private let nodeSpacing: CGFloat = 240
    private var nodes: [TrackNode] = []
    /// Fresh track every game. SPYHUNTER_SEED pins it for reproducible testing.
    private var rng = SeededRandom(
        seed: ProcessInfo.processInfo.environment["SPYHUNTER_SEED"].flatMap { UInt64($0) }
            ?? UInt64.random(in: 1...UInt64.max))
    private var lastBendDirection: CGFloat = 1
    /// Road covered before the first boathouse branch can appear. Lowered by
    /// SPYHUNTER_WATER so the water sections can be reached quickly in testing.
    private var nodesUntilWaterAllowed =
        ProcessInfo.processInfo.environment["SPYHUNTER_WATER"] != nil ? 2 : 14
    /// Road covered before the next bridge or causeway.
    private var nodesUntilBridgeAllowed =
        ProcessInfo.processInfo.environment["SPYHUNTER_BRIDGE"] != nil ? 2 : 8
    /// Road covered before fog or ice can set in.
    private var nodesUntilWeatherAllowed =
        ProcessInfo.processInfo.environment["SPYHUNTER_WEATHER"] != nil ? 2 : 10

    private(set) var transitions: [Transition] = []

    private let baseHalfWidth: CGFloat = 82
    private let minHalfWidth: CGFloat = 54
    /// Half-width of the carriageway where it meets a boathouse, matched to the
    /// building so the terrain seam is hidden behind it.
    private let doorwayHalfWidth: CGFloat = 46

    /// World-Y at which the terrain actually changes ahead of `node`.
    ///
    /// `shape` switches terrain at the midpoint between two control nodes, not
    /// at the node itself, so a boathouse aligned to the node would stand well
    /// inside the water.
    private func terrainSeamY(beforeNode index: Int) -> CGFloat {
        (CGFloat(index) - 0.5) * nodeSpacing
    }

    /// Rises with distance; bends sharpen and the road narrows more often.
    var difficulty: CGFloat = 0
    /// What the player is currently on, driven by the scene from `isWater`.
    var terrain: Terrain = .road

    static let grassColor = SKColor(red: 0.11, green: 0.42, blue: 0.15, alpha: 1)
    static let bankColor  = SKColor(red: 0.72, green: 0.66, blue: 0.42, alpha: 1)
    static let roadColor  = SKColor(red: 0.26, green: 0.26, blue: 0.28, alpha: 1)
    static let riverColor = SKColor(red: 0.10, green: 0.36, blue: 0.72, alpha: 1)
    /// Icy tarmac reads pale and blue, so the loss of grip is visible.
    static let iceColor   = SKColor(red: 0.62, green: 0.72, blue: 0.80, alpha: 1)
    /// Width of the decorative road drawn along a river bank.
    static let bankRoadWidth: CGFloat = 52
    static let snowColor  = SKColor(red: 0.82, green: 0.86, blue: 0.90, alpha: 1)

    init(parent: SKNode) {
        sliceCount = Int(GameConfig.canvasHeight / sliceHeight) + 3

        ground = SKSpriteNode(color: RoadManager.grassColor,
                              size: CGSize(width: GameConfig.canvasWidth,
                                           height: GameConfig.canvasHeight))
        ground.position = CGPoint(x: GameConfig.canvasWidth / 2,
                                  y: GameConfig.canvasHeight / 2)
        ground.zPosition = ZOrder.terrain
        parent.addChild(ground)

        root.zPosition = ZOrder.terrain + 1
        parent.addChild(root)

        for _ in 0..<sliceCount {
            let s = RoadSlice()
            root.addChild(s)
            slices.append(s)
        }
    }

    // MARK: - Generation

    private func node(at index: Int) -> TrackNode {
        let i = max(0, index)
        while nodes.count <= i { generateFeature() }
        return nodes[i]
    }

    /// Appends a whole feature at a time, so straights stay straight and each
    /// bend commits to a new line.
    private func generateFeature() {
        guard let previous = nodes.last else {
            nodes.append(contentsOf: repeatElement(
                TrackNode(offset: 0, halfWidth: baseHalfWidth, fork: 0,
                          isWater: false, weather: .clear),
                count: 3))
            return
        }

        let d = min(1, difficulty)
        nodesUntilWaterAllowed -= 1
        nodesUntilWeatherAllowed -= 1
        nodesUntilBridgeAllowed -= 1

        // In a water section the channel just meanders until the exit.
        if previous.isWater {
            generateWaterFeature(previous)
            return
        }

        let roll = rng.next()

        // Once enough road has gone by, a boathouse branch becomes likely so
        // the player actually reaches the water sections in a normal run.
        if nodesUntilWaterAllowed <= 0 && roll > 0.55 {
            waterSection(previous)
        } else if previous.weather != .clear {
            // Run the current weather out before considering anything else.
            weatherRun(previous, clearing: true)
        } else if previous.bankLeft == .water || previous.bankRight == .water {
            // Run the current bridge out before doing anything else.
            endBridge(previous)
        } else if nodesUntilBridgeAllowed <= 0 && roll > 0.42 {
            bridge(previous)
        } else if nodesUntilWeatherAllowed <= 0 && roll > 0.62 {
            weatherRun(previous, clearing: false)
        } else if roll < 0.28 {
            straight(previous)
        } else if roll < 0.68 {
            bend(previous, difficulty: d)
        } else if roll < 0.82 {
            narrowing(previous, difficulty: d)
        } else {
            fork(previous)
        }
    }

    /// Rolls in a stretch of fog or ice, or clears the current one.
    private func weatherRun(_ previous: TrackNode, clearing: Bool) {
        var next = previous
        if clearing {
            next.weather = .clear
            nodesUntilWeatherAllowed = rng.int(in: 12...22)
            nodes.append(next)
            nodes.append(contentsOf: repeatElement(next, count: 2))
            return
        }
        next.weather = rng.next() < 0.5 ? .fog : .ice
        // Weather stretches are long enough to change how the road plays.
        nodes.append(next)
        nodes.append(contentsOf: repeatElement(next, count: rng.int(in: 4...8)))
    }

    /// A stretch where the verge is open water on one or both sides: a shore
    /// road, or a causeway with nothing but water either side. Cars barged over
    /// the line go straight in.
    private func bridge(_ previous: TrackNode) {
        var next = previous
        // Straighten and centre so the crossing reads clearly.
        next.offset = previous.offset * 0.25
        let variant = rng.int(in: 0...9)
        if variant < 5 {
            // Causeway — water both sides, and a tighter roadway.
            next.bankLeft = .water
            next.bankRight = .water
            next.halfWidth = baseHalfWidth * 0.72
            next.offset = 0
        } else if variant < 8 {
            next.bankLeft = .water
            next.halfWidth = baseHalfWidth * 0.86
        } else {
            next.bankRight = .water
            next.halfWidth = baseHalfWidth * 0.86
        }
        // Ease onto it, hold, and the closing node is added by endBridge.
        var lead = previous
        lead.offset = next.offset
        nodes.append(lead)
        nodes.append(next)
        nodes.append(contentsOf: repeatElement(next, count: rng.int(in: 3...6)))
    }

    private func endBridge(_ previous: TrackNode) {
        var back = previous
        back.bankLeft = .land
        back.bankRight = .land
        back.halfWidth = baseHalfWidth
        nodes.append(back)
        nodes.append(contentsOf: repeatElement(back, count: 2))
        nodesUntilBridgeAllowed = rng.int(in: 6...12)
    }

    private func straight(_ previous: TrackNode) {
        nodes.append(contentsOf: repeatElement(previous, count: rng.int(in: 2...4)))
    }

    private func bend(_ previous: TrackNode, difficulty d: CGFloat) {
        var direction: CGFloat = rng.next() < 0.75 ? -lastBendDirection : lastBendDirection
        if previous.offset > 0.55 { direction = -1 }
        if previous.offset < -0.55 { direction = 1 }

        let reach = rng.cgFloat(in: 0.40...(0.65 + 0.30 * d))
        let target = max(-0.88, min(0.88, previous.offset + direction * reach))
        lastBendDirection = direction

        var mid = previous; mid.offset = (previous.offset + target) / 2
        var end = previous; end.offset = target
        nodes.append(mid)
        nodes.append(end)
        if rng.next() < 0.6 { nodes.append(end) }
    }

    private func narrowing(_ previous: TrackNode, difficulty d: CGFloat) {
        var next = previous
        let squeeze = rng.cgFloat(in: 0.25...1.0) * (0.4 + 0.6 * d)
        next.halfWidth = baseHalfWidth - (baseHalfWidth - minHalfWidth) * squeeze
        nodes.append(next)
        nodes.append(contentsOf: repeatElement(next, count: rng.int(in: 1...2)))
        var back = next; back.halfWidth = baseHalfWidth
        nodes.append(back)
    }

    /// The road splits around an island, runs as two branches, then rejoins.
    private func fork(_ previous: TrackNode) {
        // Centre the road first so both branches stay on screen.
        var settle = previous
        settle.offset = previous.offset * 0.35
        settle.halfWidth = baseHalfWidth
        nodes.append(settle)

        var opening = settle; opening.fork = 0.5
        var open = settle; open.fork = 1
        nodes.append(opening)
        nodes.append(open)
        nodes.append(contentsOf: repeatElement(open, count: rng.int(in: 1...3)))

        var closing = settle; closing.fork = 0.5
        nodes.append(closing)
        nodes.append(settle)
    }

    /// The road narrows into a boathouse on the bank and becomes a river.
    ///
    /// The building is placed on the terrain seam and the carriageway is
    /// squeezed to the width of the doorway either side of it, so the change
    /// happens *behind* the boathouse instead of as a visible straight edge.
    private func waterSection(_ previous: TrackNode) {
        nodesUntilWaterAllowed = rng.int(in: 16...26)

        // Straighten up and centre for the run-in.
        var settle = previous
        settle.offset = previous.offset * 0.3
        settle.halfWidth = baseHalfWidth
        settle.fork = 0
        nodes.append(settle)

        // Funnel down to the width of the boathouse doors.
        var narrow = settle
        narrow.halfWidth = doorwayHalfWidth
        nodes.append(narrow)
        nodes.append(narrow)

        let firstWaterIndex = nodes.count
        var mouth = narrow
        mouth.isWater = true
        mouth.weather = .clear
        nodes.append(mouth)

        // Open out into the channel proper.
        let side: CGFloat = rng.next() < 0.5 ? -1 : 1
        var water = mouth
        water.bankLeft = .land
        water.bankRight = .land
        water.halfWidth = baseHalfWidth * 0.92
        water.offset = max(-0.7, min(0.7, settle.offset + side * 0.25))
        nodes.append(water)
        // Long enough to be a section in its own right rather than a brief
        // detour. The boat carries its own missiles, so there is no need to cut
        // it short for want of a weapons van.
        nodes.append(contentsOf: repeatElement(water, count: rng.int(in: 30...40)))

        transitions.append(Transition(worldY: terrainSeamY(beforeNode: firstWaterIndex),
                                      enteringWater: true, side: 0))
    }

    private func generateWaterFeature(_ previous: TrackNode) {
        // Decide whether to keep winding down the river or return to land.
        if rng.next() < 0.18 {
            // Narrow the channel into the boathouse, then back onto the road.
            var mouth = previous
            mouth.halfWidth = doorwayHalfWidth
            mouth.offset = previous.offset * 0.4
            nodes.append(mouth)
            nodes.append(mouth)

            let firstLandIndex = nodes.count
            var land = mouth
            land.isWater = false
            land.fork = 0
            nodes.append(land)

            var open = land
            open.halfWidth = baseHalfWidth
            nodes.append(open)
            nodes.append(contentsOf: repeatElement(open, count: 3))

            transitions.append(Transition(worldY: terrainSeamY(beforeNode: firstLandIndex),
                                          enteringWater: false, side: 0))
            nodesUntilWaterAllowed = rng.int(in: 16...26)
            return
        }

        var direction: CGFloat = rng.next() < 0.72 ? -lastBendDirection : lastBendDirection
        if previous.offset > 0.45 { direction = -1 }
        if previous.offset < -0.45 { direction = 1 }
        lastBendDirection = direction

        // The river winds noticeably more than the road, and swings wider, so
        // it is not a long straight corridor of blue.
        var next = previous
        next.offset = max(-0.86, min(0.86,
            previous.offset + direction * rng.cgFloat(in: 0.45...0.95)))
        next.halfWidth = baseHalfWidth * rng.cgFloat(in: 0.70...1.0)
        var mid = previous
        mid.offset = (previous.offset + next.offset) / 2
        mid.halfWidth = (previous.halfWidth + next.halfWidth) / 2
        nodes.append(mid)
        nodes.append(next)
    }

    // MARK: - Queries

    func shape(_ worldY: CGFloat) -> Shape {
        let t = worldY / nodeSpacing
        let i = Int(floor(t))
        var f = t - CGFloat(i)
        if worldY < 0 { f = 0 }
        let a = node(at: i)
        let b = node(at: i + 1)
        let s = f * f * (3 - 2 * f)     // smoothstep

        let offset = a.offset + (b.offset - a.offset) * s
        let halfWidth = a.halfWidth + (b.halfWidth - a.halfWidth) * s
        let fork = a.fork + (b.fork - a.fork) * s
        // Terrain and weather switch at the node boundary rather than blending.
        let isWater = s < 0.5 ? a.isWater : b.isWater
        let weather = s < 0.5 ? a.weather : b.weather
        let bankL = s < 0.5 ? a.bankLeft : b.bankLeft
        let bankR = s < 0.5 ? a.bankRight : b.bankRight

        // Keep the whole carriageway, forks included, on screen.
        let outer = halfWidth * (1 + 0.30 * fork)
        let margin: CGFloat = 8
        let maxAmp = max(0, GameConfig.canvasWidth / 2 - outer - margin)
        let centre = GameConfig.canvasWidth / 2 + offset * maxAmp

        return Shape(centre: centre, halfWidth: halfWidth, fork: fork,
                     isWater: isWater, weather: weather,
                     bankLeft: bankL, bankRight: bankR)
    }

    func centreX(_ worldY: CGFloat) -> CGFloat {
        let s = shape(worldY)
        guard s.isForked else { return s.centre }
        // On a fork, "the centre" is the nearest branch for spawning purposes.
        return s.leftCentre
    }

    func halfWidth(_ worldY: CGFloat) -> CGFloat {
        let s = shape(worldY)
        return s.isForked ? s.branchHalfWidth : s.halfWidth
    }

    func isWater(_ worldY: CGFloat) -> Bool { shape(worldY).isWater }

    func weather(_ worldY: CGFloat) -> Weather { shape(worldY).weather }

    /// True when the ground beside the road at this point is open water, so a
    /// vehicle pushed over the line sinks instead of crashing.
    func isWaterBeside(x: CGFloat, worldY: CGFloat) -> Bool {
        let s = shape(worldY)
        if s.isWater { return false }        // already on the river
        return x < s.centre ? s.bankLeft == .water : s.bankRight == .water
    }

    /// Steering grip, 1 on dry tarmac and much lower on ice.
    func grip(_ worldY: CGFloat) -> CGFloat {
        shape(worldY).weather == .ice ? 0.30 : 1
    }

    /// Outer drivable extent, ignoring any island in the middle.
    func bounds(_ worldY: CGFloat) -> (left: CGFloat, right: CGFloat) {
        let s = shape(worldY)
        let hw = s.isForked ? s.outerHalfWidth : s.halfWidth
        return (s.centre - hw, s.centre + hw)
    }

    /// True when x is on tarmac — which on an open fork excludes the island.
    func isOnRoad(x: CGFloat, worldY: CGFloat, margin: CGFloat = 0) -> Bool {
        let s = shape(worldY)
        if !s.isForked {
            let hw = max(s.halfWidth, s.outerHalfWidth) + margin
            return abs(x - s.centre) <= hw
        }
        let hw = s.branchHalfWidth + margin
        return abs(x - s.leftCentre) <= hw || abs(x - s.rightCentre) <= hw
    }

    /// How far outside the tarmac a position is, in points. Zero when on the
    /// road. Used to decide when a vehicle has been run off and is wrecked.
    func offRoadDistance(x: CGFloat, worldY: CGFloat) -> CGFloat {
        let s = shape(worldY)
        if !s.isForked {
            let hw = max(s.halfWidth, s.outerHalfWidth)
            return max(0, abs(x - s.centre) - hw)
        }
        let hw = s.branchHalfWidth
        let toLeft = abs(x - s.leftCentre) - hw
        let toRight = abs(x - s.rightCentre) - hw
        return max(0, min(toLeft, toRight))
    }

    /// Centre of whichever branch the given x is closest to.
    func nearestBranchCentre(x: CGFloat, worldY: CGFloat) -> CGFloat {
        let s = shape(worldY)
        guard s.isForked else { return s.centre }
        return abs(x - s.leftCentre) <= abs(x - s.rightCentre) ? s.leftCentre : s.rightCentre
    }

    /// Clamps a lateral position onto the nearest branch.
    func clamp(x: CGFloat, worldY: CGFloat, margin: CGFloat) -> CGFloat {
        let s = shape(worldY)
        if !s.isForked {
            let hw = max(s.halfWidth, s.outerHalfWidth)
            return max(s.centre - hw + margin, min(s.centre + hw - margin, x))
        }
        let branch = nearestBranchCentre(x: x, worldY: worldY)
        let hw = max(margin + 1, s.branchHalfWidth)
        return max(branch - hw + margin, min(branch + hw - margin, x))
    }

    // MARK: - Drawing

    func update(cameraY: CGFloat) {
        let waterHere = terrain == .water
        // Verges turn to snow through an icy stretch.
        let icyHere = weather(cameraY + GameConfig.canvasHeight * 0.3) == .ice
        ground.color = waterHere ? RoadManager.bankColor
            : (icyHere ? RoadManager.snowColor : RoadManager.grassColor)

        let firstIndex = floor(cameraY / sliceHeight)
        for (i, slice) in slices.enumerated() {
            let worldY = (firstIndex + CGFloat(i)) * sliceHeight
            let screenY = worldY - cameraY
            let s = shape(worldY + sliceHeight / 2)
            let surface: SKColor
            if s.isWater {
                surface = RoadManager.riverColor
            } else if s.weather == .ice {
                surface = RoadManager.iceColor
            } else {
                surface = RoadManager.roadColor
            }
            let dashOn = !s.isWater && !s.isForked && Int(floor(worldY / 24)) % 2 == 0
            // Verge colour follows the terrain and season; bridge banks paint
            // themselves as water regardless.
            let land: SKColor
            if s.isWater {
                land = RoadManager.bankColor
            } else if s.weather == .ice {
                land = RoadManager.snowColor
            } else {
                land = RoadManager.grassColor
            }
            // On the water, put a road along whichever bank has room for one.
            // It is pure scenery — the channel is still the only way through —
            // but it stops the banks reading as empty brown margins.
            var sceneryRoad: CGFloat? = nil
            if s.isWater {
                let leftRoom = s.centre - s.halfWidth
                let rightRoom = GameConfig.canvasWidth - (s.centre + s.halfWidth)
                let needed = RoadManager.bankRoadWidth + 22
                if leftRoom >= needed && leftRoom >= rightRoom {
                    sceneryRoad = leftRoom / 2
                } else if rightRoom >= needed {
                    sceneryRoad = GameConfig.canvasWidth - rightRoom / 2
                }
            }
            slice.configure(shape: s, y: screenY, height: sliceHeight,
                            color: surface, markings: !s.isWater, dash: dashOn,
                            landColor: land, waterColor: RoadManager.riverColor,
                            sceneryRoadCentre: sceneryRoad,
                            sceneryDash: Int(floor(worldY / 24)) % 2 == 0)
        }
    }
}

/// One horizontal band of track. Draws either a single carriageway or, on a
/// fork, two branches with an island between them.
private final class RoadSlice: SKNode {
    /// Ground either side of the carriageway. On a bridge or causeway these
    /// are painted as open water.
    private let leftBank = SKSpriteNode()
    private let rightBank = SKSpriteNode()
    /// Decorative road along a river bank, plus its edge lines and centre dash.
    private let bankRoad = SKSpriteNode()
    private let bankEdges = [SKSpriteNode(), SKSpriteNode()]
    private let bankDash = SKSpriteNode()
    private let leftSurface = SKSpriteNode()
    private let rightSurface = SKSpriteNode()
    private let edges = [SKSpriteNode(), SKSpriteNode(), SKSpriteNode(), SKSpriteNode()]
    private let centreDash = SKSpriteNode()

    private static let edgeColor = SKColor(white: 0.92, alpha: 1)
    private static let darkEdgeColor = SKColor(red: 0.35, green: 0.42, blue: 0.5, alpha: 1)
    private static let edgeWidth: CGFloat = 3

    override init() {
        super.init()
        for n in [leftBank, rightBank] {
            n.anchorPoint = CGPoint(x: 0, y: 0)
            n.zPosition = -1
            addChild(n)
        }
        bankRoad.anchorPoint = CGPoint(x: 0.5, y: 0)
        bankRoad.zPosition = -0.5
        bankRoad.color = RoadManager.roadColor
        addChild(bankRoad)
        for e in bankEdges {
            e.anchorPoint = CGPoint(x: 0.5, y: 0)
            e.zPosition = -0.4
            e.color = SKColor(white: 0.86, alpha: 1)
            addChild(e)
        }
        bankDash.anchorPoint = CGPoint(x: 0.5, y: 0)
        bankDash.zPosition = -0.4
        bankDash.color = SKColor(white: 0.80, alpha: 1)
        addChild(bankDash)
        for n in [leftSurface, rightSurface] {
            n.anchorPoint = CGPoint(x: 0.5, y: 0)
            n.zPosition = 0
            addChild(n)
        }
        for e in edges {
            e.anchorPoint = CGPoint(x: 0.5, y: 0)
            e.zPosition = 1
            e.color = RoadSlice.edgeColor
            addChild(e)
        }
        centreDash.anchorPoint = CGPoint(x: 0.5, y: 0)
        centreDash.zPosition = 1
        centreDash.color = SKColor(white: 0.85, alpha: 1)
        addChild(centreDash)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    func configure(shape s: RoadManager.Shape, y: CGFloat, height: CGFloat,
                   color: SKColor, markings: Bool, dash: Bool,
                   landColor: SKColor, waterColor: SKColor,
                   sceneryRoadCentre: CGFloat? = nil, sceneryDash: Bool = false) {
        position = CGPoint(x: 0, y: y)
        let ew = RoadSlice.edgeWidth

        // Paint the verges. Each side is independent, so the road can run along
        // a shore with water on one side, or across a causeway with both.
        let outer = s.isForked ? s.outerHalfWidth : max(s.halfWidth, s.outerHalfWidth)
        let roadLeft = s.centre - outer
        let roadRight = s.centre + outer
        leftBank.color = s.bankLeft == .water ? waterColor : landColor
        leftBank.size = CGSize(width: max(0, roadLeft), height: height)
        leftBank.position = CGPoint(x: 0, y: 0)
        rightBank.color = s.bankRight == .water ? waterColor : landColor
        rightBank.size = CGSize(width: max(0, GameConfig.canvasWidth - roadRight),
                                height: height)
        rightBank.position = CGPoint(x: roadRight, y: 0)

        // Scenery road on the bank, when there is room for one.
        if let centre = sceneryRoadCentre {
            let w = RoadManager.bankRoadWidth
            let ew: CGFloat = 2
            bankRoad.isHidden = false
            bankRoad.size = CGSize(width: w, height: height)
            bankRoad.position = CGPoint(x: centre, y: 0)
            for (edge, offset) in zip(bankEdges, [-w / 2 + ew / 2, w / 2 - ew / 2]) {
                edge.isHidden = false
                edge.size = CGSize(width: ew, height: height)
                edge.position = CGPoint(x: centre + offset, y: 0)
            }
            bankDash.isHidden = !sceneryDash
            bankDash.size = CGSize(width: 2, height: height)
            bankDash.position = CGPoint(x: centre, y: 0)
        } else {
            bankRoad.isHidden = true
            bankEdges.forEach { $0.isHidden = true }
            bankDash.isHidden = true
        }
        // White lines vanish against pale ice, so darken them there.
        let lineColor = s.weather == .ice ? RoadSlice.darkEdgeColor : RoadSlice.edgeColor
        edges.forEach { $0.color = lineColor }
        centreDash.color = lineColor

        if s.isForked {
            let hw = s.branchHalfWidth
            leftSurface.isHidden = false
            rightSurface.isHidden = false
            for (node, centre) in [(leftSurface, s.leftCentre), (rightSurface, s.rightCentre)] {
                node.color = color
                node.size = CGSize(width: hw * 2, height: height)
                node.position = CGPoint(x: centre, y: 0)
            }
            centreDash.isHidden = true
            guard markings else { edges.forEach { $0.isHidden = true }; return }
            // Four edges: outer and inner sides of both branches.
            let positions = [s.leftCentre - hw + ew / 2, s.leftCentre + hw - ew / 2,
                             s.rightCentre - hw + ew / 2, s.rightCentre + hw - ew / 2]
            for (edge, x) in zip(edges, positions) {
                edge.isHidden = false
                edge.size = CGSize(width: ew, height: height)
                edge.position = CGPoint(x: x, y: 0)
            }
        } else {
            // One carriageway. While a fork is opening the branches overlap, so
            // the surface spans their full extent and only the outer edges are
            // drawn — no stray lines through the middle of the road.
            let hw = max(s.halfWidth, s.outerHalfWidth)
            leftSurface.isHidden = false
            rightSurface.isHidden = true
            leftSurface.color = color
            leftSurface.size = CGSize(width: hw * 2, height: height)
            leftSurface.position = CGPoint(x: s.centre, y: 0)

            guard markings else {
                edges.forEach { $0.isHidden = true }
                centreDash.isHidden = true
                return
            }
            let positions = [s.centre - hw + ew / 2, s.centre + hw - ew / 2]
            for (i, edge) in edges.enumerated() {
                if i < 2 {
                    edge.isHidden = false
                    edge.size = CGSize(width: ew, height: height)
                    edge.position = CGPoint(x: positions[i], y: 0)
                } else {
                    edge.isHidden = true
                }
            }
            centreDash.isHidden = !dash
            centreDash.size = CGSize(width: 2, height: height)
            centreDash.position = CGPoint(x: s.centre, y: 0)
        }
    }
}
