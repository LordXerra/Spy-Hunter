import AppKit
import SpriteKit

/// The in-game pause menu, opened with Escape or P.
///
/// Options are toggled in place rather than opening sub-screens, so a paused
/// game is never more than one keypress from being resumed.
final class PauseMenu: SKNode {

    /// Where the menu was opened from. The title screen has nothing to return
    /// to, so it drops the "exit to title" row.
    enum Context {
        case game
        case title
    }

    private enum Item {
        case resume, fullscreen, music, sound, exitToTitle, exitGame

        func label(_ context: Context) -> String {
            switch self {
            case .resume:      return context == .title ? "BACK" : "RESUME"
            case .fullscreen:  return "SCREEN"
            case .music:       return "MUSIC"
            case .sound:       return "SOUND"
            case .exitToTitle: return "EXIT TO TITLE"
            case .exitGame:    return "EXIT GAME"
            }
        }

        /// Right-hand value shown for the toggles.
        var value: String? {
            switch self {
            case .fullscreen: return Settings.fullscreen ? "FULL" : "WINDOW"
            case .music:      return Settings.musicOn ? "ON" : "OFF"
            case .sound:      return Settings.soundOn ? "ON" : "OFF"
            default:          return nil
            }
        }
    }

    /// Called when the player resumes or leaves.
    var onResume: (() -> Void)?
    var onExit: (() -> Void)?

    private let context: Context
    private let items: [Item]
    private var selection = 0
    private var rows: [(label: BitmapLabel, value: BitmapLabel?)] = []
    private var cursor: SKSpriteNode!
    private var repeatDelay: TimeInterval = 0

    private let rowHeight: CGFloat = 30
    private let highlight = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
    private let dim = SKColor(white: 0.72, alpha: 1)

    init(context: Context = .game) {
        self.context = context
        items = context == .game
            ? [.resume, .fullscreen, .music, .sound, .exitToTitle, .exitGame]
            : [.resume, .fullscreen, .music, .sound, .exitGame]
        super.init()
        zPosition = ZOrder.overlay
        build()
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    private func build() {
        // Dim the game behind the panel.
        let shade = SKSpriteNode(color: SKColor(white: 0, alpha: 0.72),
                                 size: GameConfig.canvasSize)
        shade.position = CGPoint(x: GameConfig.canvasWidth / 2,
                                 y: GameConfig.canvasHeight / 2)
        addChild(shade)

        let panelHeight = CGFloat(items.count) * rowHeight + 76
        let panel = SKSpriteNode(color: SKColor(red: 0.05, green: 0.08, blue: 0.16, alpha: 0.96),
                                 size: CGSize(width: 250, height: panelHeight))
        panel.position = CGPoint(x: GameConfig.canvasWidth / 2,
                                 y: GameConfig.canvasHeight / 2)
        addChild(panel)

        let border = SKSpriteNode(color: highlight,
                                  size: CGSize(width: 250, height: 2))
        border.position = CGPoint(x: GameConfig.canvasWidth / 2,
                                  y: GameConfig.canvasHeight / 2 + panelHeight / 2)
        addChild(border)

        let title = BitmapLabel(context == .title ? "OPTIONS" : "PAUSED",
                                scale: 1.0, tint: highlight,
                                tracking: -3, align: .center)
        title.position = CGPoint(x: GameConfig.canvasWidth / 2,
                                 y: GameConfig.canvasHeight / 2 + panelHeight / 2 - 30)
        addChild(title)

        cursor = SKSpriteNode(color: highlight, size: CGSize(width: 8, height: 8))
        addChild(cursor)

        let top = GameConfig.canvasHeight / 2 + panelHeight / 2 - 68
        for (i, item) in items.enumerated() {
            let y = top - CGFloat(i) * rowHeight
            let label = BitmapLabel(item.label(context), scale: 0.62, tint: dim,
                                    tracking: -3, align: .left)
            label.position = CGPoint(x: GameConfig.canvasWidth / 2 - 92, y: y)
            addChild(label)

            var valueLabel: BitmapLabel?
            if let v = item.value {
                let vl = BitmapLabel(v, scale: 0.62, tint: dim,
                                     tracking: -3, align: .right)
                vl.position = CGPoint(x: GameConfig.canvasWidth / 2 + 100, y: y)
                addChild(vl)
                valueLabel = vl
            }
            rows.append((label, valueLabel))
        }
        refresh()
    }

    private func refresh() {
        for (i, row) in rows.enumerated() {
            let on = i == selection
            row.label.tint = on ? highlight : dim
            row.value?.tint = on ? highlight : dim
            row.value?.text = items[i].value ?? ""
        }
        cursor.position = CGPoint(x: GameConfig.canvasWidth / 2 - 104,
                                  y: rows[selection].label.position.y)
    }

    // MARK: - Input

    /// Drives the menu while it is open.
    func update(dt: TimeInterval, input: InputManager) {
        repeatDelay = max(0, repeatDelay - dt)

        if input.wasPressed(.up) || (input.throttleAxis > 0.5 && repeatDelay == 0) {
            move(-1)
        } else if input.wasPressed(.down) || (input.throttleAxis < -0.5 && repeatDelay == 0) {
            move(1)
        }

        if input.wasPressed(.start) || input.wasPressed(.fire) {
            activate()
            return          // activating may have closed the menu already
        }
        // Escape or pause closes the menu straight away.
        if input.wasPressed(.back) || input.wasPressed(.pause) {
            AudioManager.shared.play(.blip, volume: 0.5)
            onResume?()
        }
    }

    private func move(_ delta: Int) {
        let count = items.count
        selection = (selection + delta + count) % count
        repeatDelay = 0.18
        AudioManager.shared.play(.blip, volume: 0.4)
        refresh()
    }

    private func activate() {
        guard selection < items.count else { return }
        AudioManager.shared.play(.confirm, volume: 0.6)
        switch items[selection] {
        case .resume:
            onResume?()
        case .fullscreen:
            (NSApp.delegate as? AppDelegate)?.toggleFullscreen()
            // The window reports the new state back through Settings, so give
            // it a moment before re-reading the label.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.refresh()
            }
        case .music:
            Settings.musicOn.toggle()
            if Settings.musicOn {
                AudioManager.shared.startMusic()
            } else {
                AudioManager.shared.stopMusic()
            }
            refresh()
        case .sound:
            Settings.soundOn.toggle()
            refresh()
        case .exitToTitle:
            onExit?()
        case .exitGame:
            NSApp.terminate(nil)
        }
    }
}
