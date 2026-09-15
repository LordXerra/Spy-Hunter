import SpriteKit

/// The arcade sprite-sheet font, re-emitted by the asset pipeline as a
/// white-on-transparent alpha mask so it can be tinted to any colour.
final class BitmapFont {
    static let shared = BitmapFont()

    static let cell: CGFloat = 16
    /// Glyph order in font.png, packed 16 per row.
    private static let charset = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,:'-!?/<>")
    private static let columns = 16

    private let atlas: SKTexture
    private var cache: [Character: SKTexture] = [:]
    private let index: [Character: Int]

    private init() {
        guard let url = GameResources.url("font", "png"),
              let image = NSImage(contentsOf: url) else {
            fatalError("font.png missing from bundle resources")
        }
        atlas = SKTexture(image: image)
        atlas.filteringMode = .nearest
        var map: [Character: Int] = [:]
        for (i, c) in BitmapFont.charset.enumerated() { map[c] = i }
        index = map
    }

    /// Texture for a character, or nil for characters with no glyph (space).
    func texture(for character: Character) -> SKTexture? {
        let c = Character(String(character).uppercased())
        if c == " " { return nil }
        if let cached = cache[c] { return cached }
        guard let i = index[c] else { return nil }
        let cols = CGFloat(BitmapFont.columns)
        let rows = CGFloat((BitmapFont.charset.count + BitmapFont.columns - 1) / BitmapFont.columns)
        let col = CGFloat(i % BitmapFont.columns)
        let row = CGFloat(i / BitmapFont.columns)
        let rect = CGRect(x: col / cols,
                          y: (rows - row - 1) / rows,
                          width: 1 / cols,
                          height: 1 / rows)
        let tex = SKTexture(rect: rect, in: atlas)
        tex.filteringMode = .nearest
        cache[c] = tex
        return tex
    }
}

/// A line of text drawn with the arcade bitmap font.
final class BitmapLabel: SKNode {

    enum HAlign { case left, center, right }

    var text: String { didSet { if text != oldValue { rebuild() } } }
    var tint: SKColor { didSet { applyTint() } }
    /// Multiplier on the 16px glyph cell.
    var glyphScale: CGFloat { didSet { rebuild() } }
    /// Letter spacing in *font units* (not screen points), so it scales with
    /// `glyphScale`. The glyphs' ink is ~13 of the 16-unit cell, so a tracking
    /// of about -3 sets letters side by side without overlapping them.
    var tracking: CGFloat { didSet { rebuild() } }
    var hAlign: HAlign { didSet { layout() } }

    private var glyphs: [SKSpriteNode] = []
    /// Left-aligned x for each glyph, before alignment is applied.
    private var baseX: [CGFloat] = []
    private(set) var contentWidth: CGFloat = 0

    var lineHeight: CGFloat { BitmapFont.cell * glyphScale }

    init(_ text: String = "",
         scale: CGFloat = 1,
         tint: SKColor = .white,
         tracking: CGFloat = -3,
         align: HAlign = .left) {
        self.text = text
        self.tint = tint
        self.glyphScale = scale
        self.tracking = tracking
        self.hAlign = align
        super.init()
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    private func rebuild() {
        glyphs.forEach { $0.removeFromParent() }
        glyphs.removeAll()
        baseX.removeAll()

        let cellSize = BitmapFont.cell * glyphScale
        // Tracking is in font units so spacing stays proportional at any size.
        let advance = (BitmapFont.cell + tracking) * glyphScale
        var x: CGFloat = 0
        for ch in text {
            if let tex = BitmapFont.shared.texture(for: ch) {
                let n = SKSpriteNode(texture: tex)
                n.size = CGSize(width: cellSize, height: cellSize)
                n.anchorPoint = CGPoint(x: 0, y: 0.5)
                n.color = tint
                n.colorBlendFactor = 1
                addChild(n)
                glyphs.append(n)
                baseX.append(x)
            }
            x += advance
        }
        contentWidth = text.isEmpty ? 0 : max(0, x - tracking * glyphScale)
        layout()
    }

    private func layout() {
        let offset: CGFloat
        switch hAlign {
        case .left:   offset = 0
        case .center: offset = -contentWidth / 2
        case .right:  offset = -contentWidth
        }
        for (i, g) in glyphs.enumerated() {
            g.position = CGPoint(x: baseX[i] + offset, y: 0)
        }
    }

    private func applyTint() {
        for g in glyphs { g.color = tint }
    }
}
