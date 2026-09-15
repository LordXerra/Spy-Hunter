import SpriteKit

/// A rectangle in sheet pixel coordinates, origin top-left.
struct SpriteRect {
    let x: Int, y: Int, w: Int, h: Int
    init(_ x: Int, _ y: Int, _ w: Int, _ h: Int) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }
    var size: CGSize { CGSize(width: w, height: h) }
}

/// The four poses every vehicle on the sheet is drawn in.
///
/// The sheet stores them in a consistent order: upright, upright with the brake
/// lights lit, banking right and banking left. They are *poses*, not animation
/// frames — cycling through them makes a car flash its brakes and swerve on the
/// spot — so they are selected from how the vehicle is actually moving.
struct VehicleFrames {
    let straight: SpriteRect
    let braking: SpriteRect
    let turnRight: SpriteRect
    let turnLeft: SpriteRect

    /// Pose for a vehicle steering by `steer` (-1 left ... +1 right).
    func pose(steer: CGFloat, braking isBraking: Bool = false) -> SpriteRect {
        if steer > 0.25 { return turnRight }
        if steer < -0.25 { return turnLeft }
        return isBraking ? braking : straight
    }
}

/// Named regions of `spritesheet.png` (592x960, ripped by Yawackhary).
/// Coordinates were derived by background-keyed segmentation of the sheet
/// (see Tools/build_assets.py --report).
enum Art {

    // MARK: Player car — G-6155 Interceptor
    static let playerCar        = SpriteRect(  8,  12, 27, 44)
    static let playerCarBraking = SpriteRect( 48,  12, 27, 44)
    static let playerCarBank    = SpriteRect( 88,  13, 32, 43)   // banking right
    /// The player's car only has a right-bank pose on the sheet; the left bank
    /// is the same art mirrored at draw time.
    static let playerFrames = VehicleFrames(
        straight:  SpriteRect( 8, 12, 27, 44),
        braking:   SpriteRect(48, 12, 27, 44),
        turnRight: SpriteRect(88, 13, 32, 43),
        turnLeft:  SpriteRect(88, 13, 32, 43))
    static let playerSideways   = SpriteRect(128,  24, 53, 32)   // spun broadside
    static let playerWreck      = SpriteRect(192,  24, 32, 32)
    /// Car-to-boat transformation: the vehicle is swallowed by expanding rings
    /// until it vanishes. Played forward to dissolve, reversed to materialise.
    static let playerTransform: [SpriteRect] = [
        SpriteRect(232, 24, 31, 32), SpriteRect(275, 25, 27, 31),
        SpriteRect(312, 26, 27, 30), SpriteRect(352, 35, 16, 21),
        SpriteRect(369, 36,  9, 20),
    ]
    static let muzzleFlash: [SpriteRect] = [
        SpriteRect(392, 47, 10, 9), SpriteRect(416, 44, 13, 9),
    ]
    static let gunFlare: [SpriteRect] = [
        SpriteRect(448, 48, 15, 8), SpriteRect(472, 48, 23, 8),
    ]

    // MARK: Enemy cars

    /// Switchblade — "Never To Be Trusted". Tyre slashers.
    static let switchbladeFrames = VehicleFrames(
        straight:  SpriteRect(  8, 87, 27, 41),
        braking:   SpriteRect( 48, 87, 27, 41),
        turnRight: SpriteRect( 88, 86, 32, 42),
        turnLeft:  SpriteRect(128, 87, 31, 41))

    /// The Enforcer — limousine with a shotgun-toting thug.
    static let enforcerFrames = VehicleFrames(
        straight:  SpriteRect(168, 70, 28, 58),
        braking:   SpriteRect(208, 70, 28, 58),
        turnRight: SpriteRect(248, 69, 36, 59),
        turnLeft:  SpriteRect(296, 69, 36, 59))

    /// The Road Lord — bulletproof armour plating.
    static let roadLordFrames = VehicleFrames(
        straight:  SpriteRect(344, 87, 25, 41),
        braking:   SpriteRect(376, 85, 27, 43),
        turnRight: SpriteRect(416, 85, 31, 43),
        turnLeft:  SpriteRect(456, 85, 31, 43))

    // MARK: Civilian traffic (never shoot these)

    static let civilianCarFrames = VehicleFrames(
        straight:  SpriteRect(  8, 152, 26, 32),
        braking:   SpriteRect( 48, 152, 26, 32),
        turnRight: SpriteRect( 88, 152, 29, 32),
        turnLeft:  SpriteRect(128, 152, 29, 32))

    static let civilianTruckFrames = VehicleFrames(
        straight:  SpriteRect(312, 142, 31, 42),
        braking:   SpriteRect(352, 142, 31, 42),
        turnRight: SpriteRect(392, 142, 26, 42),
        turnLeft:  SpriteRect(432, 139, 32, 45))

    static let motorbike        = SpriteRect(168, 152, 23, 32)
    static let motorbikeBraking = SpriteRect(200, 152, 23, 32)
    static let motorbikeCrashA  = SpriteRect(232, 154, 32, 28)
    static let motorbikeCrashB  = SpriteRect(272, 152, 31, 32)
    static let motorbikeFrames = VehicleFrames(
        straight:  SpriteRect(168, 152, 23, 32),
        braking:   SpriteRect(200, 152, 23, 32),
        turnRight: SpriteRect(232, 154, 32, 28),
        turnLeft:  SpriteRect(272, 152, 31, 32))

    // MARK: Weapons van
    //
    // Each pair is (beacon dark, beacon lit) — the cab's roof light flashes.
    // With the ramp down the load itself is visible in the back, which is how
    // the player knows what the van is carrying before driving in.
    static let vanClosed: [SpriteRect] = [
        SpriteRect(  8, 192, 32, 64), SpriteRect( 48, 192, 32, 64)]
    static let vanMissiles: [SpriteRect] = [
        SpriteRect( 88, 192, 32, 64), SpriteRect(128, 192, 32, 64)]
    static let vanOil: [SpriteRect] = [
        SpriteRect(168, 192, 32, 64), SpriteRect(208, 192, 32, 64)]
    static let vanSmoke: [SpriteRect] = [
        SpriteRect(248, 192, 32, 64), SpriteRect(288, 192, 32, 64)]

    // MARK: Boats
    static let tugboat          = SpriteRect(328, 197, 32, 59)   // friendly — penalty
    static let civilianBoat     = SpriteRect(368, 202, 29, 54)
    static let barrelDumper     = SpriteRect(408, 211, 25, 45)
    static let doctorTorpedo    = SpriteRect(440, 202, 32, 54)
    static let doctorTorpedoAlt = SpriteRect(480, 202, 30, 54)

    // MARK: Player boat
    static let playerBoat: [SpriteRect] = [
        SpriteRect(  8, 279, 32, 49), SpriteRect( 48, 276, 30, 52),
        SpriteRect( 88, 267, 30, 61), SpriteRect(128, 271, 30, 57),
    ]
    /// Both banking frames on the sheet are *right* turns, at two angles; the
    /// left-hand versions are these mirrored at draw time.
    static let playerBoatBank     = SpriteRect(240, 283, 39, 45)
    static let playerBoatBankHard = SpriteRect(168, 289, 58, 39)
    static let playerBoatHit: [SpriteRect] = [
        SpriteRect(288, 272, 32, 56), SpriteRect(328, 270, 32, 58),
        SpriteRect(368, 272, 31, 56), SpriteRect(408, 273, 31, 55),
        SpriteRect(448, 296, 32, 32), SpriteRect(488, 302, 32, 26),
    ]

    // MARK: The Mad Bomber — helicopter
    static let heliBody         = SpriteRect(  8, 344, 32, 64)
    static let heliBank         = SpriteRect( 48, 352, 44, 56)
    static let heliSide         = SpriteRect(104, 376, 63, 32)
    static let heliSideFlat     = SpriteRect(176, 380, 64, 25)
    static let heliRotor: [SpriteRect] = [
        SpriteRect(248, 344, 64, 64), SpriteRect(320, 349, 65, 59),
    ]
    static let heliExploding    = SpriteRect(392, 344, 32, 64)

    // MARK: Scenery
    static let boathouse        = SpriteRect(  8, 417, 64, 63)
    static let boathouseAlt     = SpriteRect( 80, 417, 64, 63)
    static let barnFront        = SpriteRect(152, 416, 96, 59)
    static let barnRoof         = SpriteRect(256, 448, 64, 26)
    static let fencePost        = SpriteRect(330, 456,  9, 19)
    static let fencePostAlt     = SpriteRect(349, 456,  9, 19)
    static let treeA            = SpriteRect(368, 451, 14, 27)
    static let treeB            = SpriteRect(392, 458, 14, 22)
    /// Red-and-white float with a splash ring: the Barrel Dumper's charge.
    static let floatingMine     = SpriteRect(416, 460, 17, 20)
    static let bridgeSpan       = SpriteRect(440, 467, 26, 13)
    static let postA            = SpriteRect(480, 458,  6, 22)
    static let postB            = SpriteRect(506, 458,  6, 22)

    // MARK: Projectiles & deployables
    static let bullet           = SpriteRect( 83, 488,  2,  7)
    static let bulletAlt        = SpriteRect( 99, 511,  2,  7)
    static let enemyBullet      = SpriteRect(107, 496,  2,  7)
    /// Blue-and-white bollards. These were previously used as the Barrel
    /// Dumper's charges, which is why they read as nothing recognisable — they
    /// are roadside marker posts, the same art as `postA`/`postB`.
    static let markerPost       = SpriteRect(120, 498,  6, 22)
    static let markerPostAlt    = SpriteRect(136, 498,  6, 22)
    static let smokeColumn      = SpriteRect(152, 489, 20, 31)
    static let smokeColumnAlt   = SpriteRect(184, 488, 19, 32)
    /// Missile launch sequence (exhaust plume grows).
    static let missile: [SpriteRect] = [
        SpriteRect(216, 502,  8, 18), SpriteRect(232, 500, 10, 20),
        SpriteRect(256, 498, 10, 22), SpriteRect(280, 493, 11, 27),
        SpriteRect(304, 488, 13, 32), SpriteRect(328, 489, 13, 31),
    ]
    /// Dark racks holding teal drums. These match the load drawn inside the
    /// weapons van, so they are the van's internal racks rather than any kind
    /// of emplacement — an earlier guess at "gun turret" was wrong, and the
    /// 1983 arcade game has no such enemy.
    static let weaponRack       = SpriteRect(376, 504, 19, 16)
    static let weaponRackAlt    = SpriteRect(408, 501, 21, 19)
    static let roadDebrisA      = SpriteRect(352, 513, 12,  7)
    static let roadDebrisB      = SpriteRect(480, 507, 10, 13)
    static let roadDebrisC      = SpriteRect(494, 499,  6, 10)
    static let flameA           = SpriteRect(456, 505,  5, 14)
    static let flameB           = SpriteRect(468, 505,  5, 14)

    // MARK: Oil slick & smoke screen
    static let oilSlick: [SpriteRect] = [
        SpriteRect( 48, 615, 32, 25), SpriteRect( 88, 612, 32, 28),
        SpriteRect(128, 608, 32, 32),
    ]
    static let smokeScreen: [SpriteRect] = [
        SpriteRect(200, 613, 32, 27), SpriteRect(240, 614, 32, 26),
        SpriteRect(280, 608, 32, 32),
    ]
    static let smokeFade: [SpriteRect] = [
        SpriteRect( 10, 695, 22, 17), SpriteRect( 48, 690, 24, 22),
        SpriteRect( 88, 684, 28, 28), SpriteRect(128, 685, 27, 27),
        SpriteRect(175, 690, 17, 18), SpriteRect(211, 691, 21, 21),
    ]

    // MARK: Water
    static let wake             = SpriteRect(  8, 617, 30, 23)
    static let splashA          = SpriteRect(320, 617, 30, 23)
    static let splashB          = SpriteRect(362, 611, 29, 21)
    static let splashC          = SpriteRect(402, 611, 27, 29)
    static let splashD          = SpriteRect(444, 610, 21, 30)
    static let splashBurst      = SpriteRect(520, 664, 64, 48)

    // MARK: Explosions
    /// Compact fireball, good for bullets hitting a car.
    static let explosionSmall: [SpriteRect] = [
        SpriteRect( 11, 546, 20, 14), SpriteRect( 40, 536, 25, 24),
        SpriteRect( 72, 536, 27, 24), SpriteRect(115, 531, 27, 29),
        SpriteRect(152, 532, 31, 28), SpriteRect(192, 539, 23, 21),
    ]
    /// Full fireball with smoke — vehicle destruction.
    static let explosionBig: [SpriteRect] = [
        SpriteRect(  8, 575, 30, 25), SpriteRect( 48, 568, 32, 32),
        SpriteRect( 88, 569, 32, 31), SpriteRect(128, 570, 31, 30),
        SpriteRect(168, 573, 26, 27), SpriteRect(208, 571, 27, 29),
    ]
    /// Bright flame burst (no smoke) — layered over the fireball.
    static let flameBurst: [SpriteRect] = [
        SpriteRect(248, 577, 32, 23), SpriteRect(288, 573, 32, 27),
        SpriteRect(328, 572, 32, 28), SpriteRect(368, 568, 32, 32),
    ]
    /// Radiating star-burst — the biggest hits.
    static let starBurst: [SpriteRect] = [
        SpriteRect(240, 682, 28, 30), SpriteRect(463, 669, 42, 43),
        SpriteRect(320, 656, 55, 56), SpriteRect(390, 651, 54, 61),
    ]
    /// Grey smoke puffs left behind by an explosion.
    static let smokePuff: [SpriteRect] = [
        SpriteRect(408, 568, 11, 22), SpriteRect(432, 568, 11, 31),
        SpriteRect(456, 590,  9, 10), SpriteRect(472, 584, 13, 16),
    ]
    /// Small metal chunks thrown out on impact.
    static let debrisChunk: [SpriteRect] = [
        SpriteRect(352, 513, 12, 7), SpriteRect(480, 507, 10, 13),
        SpriteRect(494, 499,  6, 10), SpriteRect(440, 517,  6,  3),
    ]

    // MARK: Attract-mode logo
    /// "SPY" — four frames of the arcade's shimmering logo animation.
    static let logoSPY: [SpriteRect] = [
        SpriteRect(  8, 827, 70, 27), SpriteRect( 88, 827, 70, 27),
        SpriteRect(168, 827, 70, 27), SpriteRect(248, 827, 70, 27),
    ]
    /// "HUNTER", one rect per letter.
    static let logoHUNTER: [SpriteRect] = [
        SpriteRect(328, 827, 19, 27), SpriteRect(348, 827, 19, 27),
        SpriteRect(368, 827, 27, 27), SpriteRect(396, 827, 19, 27),
        SpriteRect(416, 827, 19, 27), SpriteRect(436, 827, 18, 27),
    ]
    static let copyright        = SpriteRect( 32, 864, 16, 16)
    static let ballyMidway      = SpriteRect( 56, 864, 112, 16)
    static let year1983         = SpriteRect(176, 864, 32, 16)
}

/// Loads the sprite sheet once and vends sub-textures for `SpriteRect`s.
final class Atlas {
    static let shared = Atlas()

    let sheet: SKTexture
    private let sheetSize: CGSize
    private var cache: [String: SKTexture] = [:]

    private init() {
        guard let url = GameResources.url("spritesheet", "png"),
              let image = NSImage(contentsOf: url) else {
            fatalError("spritesheet.png missing from bundle resources")
        }
        sheet = SKTexture(image: image)
        sheet.filteringMode = .nearest
        sheetSize = sheet.size()
    }

    /// Sub-texture for a sheet rectangle. Converts top-left pixel coordinates
    /// into SpriteKit's bottom-left normalised texture space.
    func texture(_ r: SpriteRect) -> SKTexture {
        let key = "\(r.x),\(r.y),\(r.w),\(r.h)"
        if let cached = cache[key] { return cached }
        let norm = CGRect(x: CGFloat(r.x) / sheetSize.width,
                          y: (sheetSize.height - CGFloat(r.y) - CGFloat(r.h)) / sheetSize.height,
                          width: CGFloat(r.w) / sheetSize.width,
                          height: CGFloat(r.h) / sheetSize.height)
        let tex = SKTexture(rect: norm, in: sheet)
        tex.filteringMode = .nearest
        cache[key] = tex
        return tex
    }

    func textures(_ rects: [SpriteRect]) -> [SKTexture] { rects.map(texture) }

    /// A sprite node sized to the artwork's native pixel dimensions.
    func node(_ r: SpriteRect) -> SKSpriteNode {
        let n = SKSpriteNode(texture: texture(r))
        n.size = r.size
        return n
    }
}
