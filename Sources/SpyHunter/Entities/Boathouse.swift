import SpriteKit

/// The boathouse that sits at the end of a fork. Driving through its doorway
/// transforms the car into a boat (or the boat back into a car on the way out).
final class Boathouse: RoadEntity {

    let enteringWater: Bool
    private(set) var used = false

    init(enteringWater: Bool) {
        self.enteringWater = enteringWater
        super.init()
        team = .friendly
        // The building is scenery; the doorway below does the work.
        hitSize = .zero
        setArt(Art.barnFront)
        // Above the player, so the vehicle disappears *into* the building
        // while it changes form rather than sliding over the roof.
        node.zPosition = ZOrder.air + 5

        // A roof band drawn over the doorway sells driving "into" the building.
        let roof = Atlas.shared.node(Art.barnRoof)
        roof.position = CGPoint(x: 0, y: Art.barnFront.size.height / 2 - 6)
        roof.zPosition = 2
        node.addChild(roof)
    }

    /// The doorway the player must pass through.
    var doorway: CGRect {
        CGRect(x: x - 22, y: worldY - 14, width: 44, height: 28)
    }

    override func update(dt: TimeInterval, world: GameWorld) {
        // Fixed to the world.
    }

    func markUsed() { used = true }
}
