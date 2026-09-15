import SpriteKit

/// Title screen and attract mode.
///
/// The cycle is: title artwork -> high score table -> credits -> repeat,
/// exactly as the arcade cabinet cycled while waiting for a coin.
final class TitleScene: SKScene {

    private enum Page: Int, CaseIterable {
        case title, highScores, credits
        /// How long the page is shown before the attract cycle moves on.
        var duration: TimeInterval {
            switch self {
            case .title: return 9
            case .highScores: return 8
            case .credits: return 14
            }
        }
    }

    private var page: Page = .title
    private var pageNode: SKNode?
    private var pageElapsed: TimeInterval = 0
    private var lastUpdate: TimeInterval = 0
    /// Difficulty selector on the title page, rebuilt when the choice changes.
    private var difficultyLabel: BitmapLabel?
    /// Non-nil while the options menu is open over the attract screen.
    private var optionsMenu: PauseMenu?

    override func didMove(to view: SKView) {
        scaleMode = .aspectFit
        backgroundColor = .black
        anchorPoint = .zero
        InputManager.shared.clearKeyboard()
        AudioManager.shared.playMusic(.title)
        switch DevCapture.forcedPage {
        case "scores":  show(.highScores)
        case "credits": show(.credits)
        default:        show(.title)
        }
    }

    // MARK: - Pages

    private func show(_ p: Page) {
        pageNode?.removeFromParent()
        page = p
        pageElapsed = 0
        let node: SKNode
        switch p {
        case .title:      node = makeTitlePage()
        case .highScores: node = makeHighScorePage()
        case .credits:    node = makeCreditsPage()
        }
        node.alpha = 0
        node.run(.fadeIn(withDuration: 0.35))
        addChild(node)
        pageNode = node
    }

    private func advance() {
        let all = Page.allCases
        let next = all[(all.firstIndex(of: page)! + 1) % all.count]
        show(next)
    }

    /// The supplied title artwork, filling the canvas, with the version number
    /// in the bottom-right corner as specified.
    private func makeTitlePage() -> SKNode {
        let root = SKNode()

        if let url = GameResources.url("title", "jpg"),
           let image = NSImage(contentsOf: url) {
            let tex = SKTexture(image: image)
            let art = SKSpriteNode(texture: tex)
            // The artwork is 2:3, the same as the canvas, so it fills exactly.
            art.size = GameConfig.canvasSize
            art.position = CGPoint(x: GameConfig.canvasWidth / 2,
                                   y: GameConfig.canvasHeight / 2)
            art.zPosition = ZOrder.terrain
            root.addChild(art)
        }

        // A dark strip so the prompt, difficulty and version stay legible.
        let strip = SKSpriteNode(color: SKColor(white: 0, alpha: 0.6),
                                 size: CGSize(width: GameConfig.canvasWidth, height: 58))
        strip.position = CGPoint(x: GameConfig.canvasWidth / 2, y: 29)
        strip.zPosition = ZOrder.hud
        root.addChild(strip)

        // Novice / Expert, chosen before play as on the arcade cabinet. Expert
        // demands twice the score for each extra car and ramps up faster.
        let difficulty = BitmapLabel(Self.difficultyText, scale: 0.66,
                                     tint: SKColor(red: 0.4, green: 0.8, blue: 1, alpha: 1),
                                     tracking: -3, align: .center)
        difficulty.position = CGPoint(x: GameConfig.canvasWidth / 2, y: 44)
        difficulty.zPosition = ZOrder.hud + 1
        root.addChild(difficulty)
        difficultyLabel = difficulty

        let prompt = BitmapLabel("PRESS FIRE TO START", scale: 0.8,
                                 tint: SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1),
                                 tracking: -3, align: .center)
        prompt.position = CGPoint(x: GameConfig.canvasWidth / 2, y: 22)
        prompt.zPosition = ZOrder.hud + 1
        prompt.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.15, duration: 0.45), .fadeAlpha(to: 1, duration: 0.45),
        ])))
        root.addChild(prompt)

        let version = BitmapLabel(GameConfig.version, scale: 0.62,
                                  tint: SKColor(white: 0.85, alpha: 1),
                                  tracking: -3, align: .right)
        version.position = CGPoint(x: GameConfig.canvasWidth - 5, y: 7)
        version.zPosition = ZOrder.hud + 1
        root.addChild(version)

        // Fullscreen lives in the options menu now, so only the way into
        // that menu needs advertising. F1 still works as a shortcut.
        let hint = BitmapLabel("ESC OPTIONS", scale: 0.5,
                               tint: SKColor(white: 0.7, alpha: 1),
                               tracking: -3, align: .left)
        hint.position = CGPoint(x: 5, y: 7)
        hint.zPosition = ZOrder.hud + 1
        root.addChild(hint)

        return root
    }

    private func makeHighScorePage() -> SKNode {
        let root = SKNode()
        root.addChild(makeLogo(y: GameConfig.canvasHeight - 60))

        let heading = BitmapLabel("HIGH SCORES", scale: 1.05,
                                  tint: SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1),
                                  tracking: -3, align: .center)
        heading.position = CGPoint(x: GameConfig.canvasWidth / 2, y: GameConfig.canvasHeight - 122)
        root.addChild(heading)

        let entries = HighScoreStore.shared.entries
        var y = GameConfig.canvasHeight - 165
        for (i, entry) in entries.enumerated() {
            let rank = BitmapLabel(String(format: "%2d", i + 1), scale: 0.78,
                                   tint: SKColor(white: 0.6, alpha: 1),
                                   tracking: -3, align: .right)
            rank.position = CGPoint(x: 78, y: y)
            root.addChild(rank)

            let initials = BitmapLabel(entry.initials, scale: 0.78,
                                       tint: SKColor(red: 0.4, green: 0.8, blue: 1, alpha: 1),
                                       tracking: -3, align: .left)
            initials.position = CGPoint(x: 96, y: y)
            root.addChild(initials)

            let score = BitmapLabel(Self.formatScore(entry.score), scale: 0.78,
                                    tint: .white, tracking: -3, align: .right)
            score.position = CGPoint(x: GameConfig.canvasWidth - 78, y: y)
            root.addChild(score)

            y -= 24
        }
        return root
    }

    private func makeCreditsPage() -> SKNode {
        let root = SKNode()
        root.addChild(makeLogo(y: GameConfig.canvasHeight - 60))

        // Exactly the credits requested, wrapped to the canvas width.
        let blocks: [(lines: [String], tint: SKColor)] = [
            (["DEVELOPED BY", "TONY BRICE"],
             SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)),
            (["TECHNICAL SUPPORT BY", "AARON THORNE."],
             SKColor(red: 0.4, green: 0.8, blue: 1, alpha: 1)),
            (["TESTING BY", "TRIONA MELHUISH, AJ BRICE", "AND NAILESH SHETH."],
             SKColor(red: 0.4, green: 0.8, blue: 1, alpha: 1)),
            (["SPY HUNTER THEME REMIXED BY", "MOZZARATTI FROM THE ORIGINAL",
              "GAME MUSIC BY PETER GUN.", "USED WITH KIND PERMISSION."],
             SKColor(red: 0.55, green: 0.9, blue: 0.6, alpha: 1)),
            (["TITLE MUSIC BY -Z64"],
             SKColor(red: 0.55, green: 0.9, blue: 0.6, alpha: 1)),
            (["THIS GAME IS FREE INCLUDING", "THE SOURCE CODE. ALL IMAGES",
              "BELONG TO THEIR RESPECTIVE", "CREATORS."],
             SKColor(white: 0.8, alpha: 1)),
        ]

        // Tightened to fit the extra block on one page.
        var y = GameConfig.canvasHeight - 120
        for block in blocks {
            for line in block.lines {
                let label = BitmapLabel(line, scale: 0.52, tint: block.tint,
                                        tracking: -3, align: .center)
                label.position = CGPoint(x: GameConfig.canvasWidth / 2, y: y)
                root.addChild(label)
                y -= 16
            }
            y -= 10
        }
        return root
    }

    /// The arcade "SPY HUNTER" logo assembled from the sprite sheet, with the
    /// original's shimmering animation on the "SPY".
    private func makeLogo(y: CGFloat) -> SKNode {
        let root = SKNode()
        let atlas = Atlas.shared

        let spy = atlas.node(Art.logoSPY[0])
        spy.anchorPoint = CGPoint(x: 0, y: 0.5)
        spy.run(.repeatForever(.animate(with: atlas.textures(Art.logoSPY),
                                        timePerFrame: 0.12,
                                        resize: false, restore: true)))

        var letters: [SKSpriteNode] = []
        for rect in Art.logoHUNTER {
            let n = atlas.node(rect)
            n.anchorPoint = CGPoint(x: 0, y: 0.5)
            letters.append(n)
        }

        let gap: CGFloat = 8
        let hunterWidth = letters.reduce(0) { $0 + $1.size.width }
        let total = spy.size.width + gap + hunterWidth
        var x = -total / 2

        spy.position = CGPoint(x: x, y: 0)
        root.addChild(spy)
        x += spy.size.width + gap
        for n in letters {
            n.position = CGPoint(x: x, y: 0)
            root.addChild(n)
            x += n.size.width
        }

        root.position = CGPoint(x: GameConfig.canvasWidth / 2, y: y)
        return root
    }

    /// The selector line, with arrows showing it can be changed.
    private static var difficultyText: String {
        "< \(Settings.difficulty.name) >"
    }

    static func formatScore(_ score: Int) -> String {
        var s = String(score)
        // Thousands separators are not in the arcade font; pad instead.
        while s.count < 6 { s = " " + s }
        return s
    }

    // MARK: - Loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 0 : min(0.05, currentTime - lastUpdate)
        lastUpdate = currentTime

        let input = InputManager.shared
        input.update()

        // The options menu takes all input while it is up, and holds the
        // attract cycle where it is.
        if let optionsMenu {
            optionsMenu.update(dt: max(dt, 1.0 / 60.0), input: input)
            return
        }
        if input.wasPressed(.back) || input.wasPressed(.pause) {
            openMenu()
            return
        }

        // Left / right (or up / down) steps through the skill levels.
        if page == .title {
            let harder = input.wasPressed(.right) || input.wasPressed(.up)
            let easier = input.wasPressed(.left) || input.wasPressed(.down)
            if harder || easier {
                Settings.difficulty = harder
                    ? Settings.difficulty.next
                    : Settings.difficulty.previous
                difficultyLabel?.text = Self.difficultyText
                AudioManager.shared.play(.blip, volume: 0.5)
                pageElapsed = 0     // do not let attract mode move on mid-choice
                return
            }
        }

        if input.anyStartPressed {
            startGame()
            return
        }

        pageElapsed += dt
        if pageElapsed >= page.duration { advance() }
    }

    /// Escape opens the same options panel used in game, minus the row for
    /// returning to a title screen we are already on.
    private func openMenu() {
        guard optionsMenu == nil else { return }
        let panel = PauseMenu(context: .title)
        panel.onResume = { [weak self] in
            self?.optionsMenu?.removeFromParent()
            self?.optionsMenu = nil
        }
        addChild(panel)
        optionsMenu = panel
        AudioManager.shared.play(.blip, volume: 0.5)
    }

    private func startGame() {
        AudioManager.shared.play(.confirm)
        let scene = GameScene(size: GameConfig.canvasSize)
        scene.scaleMode = .aspectFit
        view?.presentScene(scene, transition: .fade(withDuration: 0.4))
    }
}
