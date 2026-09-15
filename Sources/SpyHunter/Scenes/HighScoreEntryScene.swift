import SpriteKit

/// Arcade initials entry: three letters picked with up/down, confirmed with
/// fire. Times out on its own so an unattended cabinet returns to attract mode.
final class HighScoreEntryScene: SKScene {

    private let score: Int
    private var letters: [Character] = ["A", "A", "A"]
    private var cursor = 0

    private var letterLabels: [BitmapLabel] = []
    private var caret: SKSpriteNode!
    private var lastUpdate: TimeInterval = 0
    private var idleTimeout: TimeInterval = 30
    private var repeatDelay: TimeInterval = 0

    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ")

    init(size: CGSize, score: Int) {
        self.score = score
        super.init(size: size)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override func didMove(to view: SKView) {
        scaleMode = .aspectFit
        anchorPoint = .zero
        backgroundColor = .black
        InputManager.shared.clearKeyboard()
        AudioManager.shared.playMusic(.title)

        let heading = BitmapLabel("NEW HIGH SCORE", scale: 1.0,
                                  tint: SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1),
                                  tracking: -3, align: .center)
        heading.position = CGPoint(x: GameConfig.canvasWidth / 2,
                                   y: GameConfig.canvasHeight - 110)
        addChild(heading)

        let scoreLabel = BitmapLabel(String(score), scale: 1.3, tint: .white,
                                     tracking: -3, align: .center)
        scoreLabel.position = CGPoint(x: GameConfig.canvasWidth / 2,
                                      y: GameConfig.canvasHeight - 160)
        addChild(scoreLabel)

        let prompt = BitmapLabel("ENTER YOUR INITIALS", scale: 0.62,
                                 tint: SKColor(white: 0.75, alpha: 1),
                                 tracking: -3, align: .center)
        prompt.position = CGPoint(x: GameConfig.canvasWidth / 2,
                                  y: GameConfig.canvasHeight - 210)
        addChild(prompt)

        // Three letter slots.
        let spacing: CGFloat = 46
        let startX = GameConfig.canvasWidth / 2 - spacing
        for i in 0..<3 {
            let label = BitmapLabel(String(letters[i]), scale: 1.9,
                                    tint: SKColor(red: 0.4, green: 0.8, blue: 1, alpha: 1),
                                    tracking: 0, align: .center)
            label.position = CGPoint(x: startX + CGFloat(i) * spacing,
                                     y: GameConfig.canvasHeight - 275)
            addChild(label)
            letterLabels.append(label)
        }

        caret = SKSpriteNode(color: SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1),
                             size: CGSize(width: 26, height: 3))
        caret.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.1, duration: 0.3), .fadeAlpha(to: 1, duration: 0.3),
        ])))
        addChild(caret)
        positionCaret()

        let help = BitmapLabel("UP DOWN TO CHANGE   FIRE TO SET", scale: 0.48,
                               tint: SKColor(white: 0.6, alpha: 1),
                               tracking: -3, align: .center)
        help.position = CGPoint(x: GameConfig.canvasWidth / 2, y: 40)
        addChild(help)
    }

    private func positionCaret() {
        let spacing: CGFloat = 46
        let startX = GameConfig.canvasWidth / 2 - spacing
        caret.position = CGPoint(x: startX + CGFloat(cursor) * spacing,
                                 y: GameConfig.canvasHeight - 300)
    }

    private func cycle(by delta: Int) {
        let alphabet = Self.alphabet
        let current = alphabet.firstIndex(of: letters[cursor]) ?? 0
        var next = (current + delta) % alphabet.count
        if next < 0 { next += alphabet.count }
        letters[cursor] = alphabet[next]
        letterLabels[cursor].text = String(letters[cursor])
        AudioManager.shared.play(.blip, volume: 0.5)
    }

    private func advance() {
        AudioManager.shared.play(.confirm, volume: 0.6)
        cursor += 1
        if cursor >= 3 {
            commit()
        } else {
            positionCaret()
        }
    }

    private func commit() {
        HighScoreStore.shared.insert(initials: String(letters), score: score)
        let scene = TitleScene(size: GameConfig.canvasSize)
        scene.scaleMode = .aspectFit
        // Show the table straight away so the player sees their entry.
        view?.presentScene(scene, transition: .fade(withDuration: 0.5))
    }

    // MARK: - Loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 0 : min(0.05, currentTime - lastUpdate)
        lastUpdate = currentTime

        let input = InputManager.shared
        input.update()

        idleTimeout -= dt
        if idleTimeout <= 0 { commit(); return }

        if input.wasPressed(.start) || input.wasPressed(.fire) {
            idleTimeout = 30
            advance()
            return
        }
        if input.wasPressed(.back) && cursor > 0 {
            cursor -= 1
            positionCaret()
            return
        }

        // Held up/down scrolls through the alphabet at a steady rate.
        repeatDelay -= dt
        let axis = input.throttleAxis
        if input.wasPressed(.up) || input.wasPressed(.down) { repeatDelay = 0 }
        if repeatDelay <= 0 {
            if axis > 0.4 || input.isHeld(.up) {
                cycle(by: 1); repeatDelay = 0.16; idleTimeout = 30
            } else if axis < -0.4 || input.isHeld(.down) {
                cycle(by: -1); repeatDelay = 0.16; idleTimeout = 30
            }
        }

        // Left/right move between slots.
        if input.wasPressed(.left), cursor > 0 { cursor -= 1; positionCaret() }
        if input.wasPressed(.right), cursor < 2 { cursor += 1; positionCaret() }
    }
}
