import AppKit
import SpriteKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private(set) var window: NSWindow!
    private(set) var skView: SKView!
    private var keyMonitor: Any?
    /// Set while we are programmatically entering fullscreen at launch.
    private var restoringFullscreen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["SPYHUNTER_ROADDUMP"] != nil {
            dumpRoad()
            NSApp.terminate(nil)
            return
        }
        if let seconds = ProcessInfo.processInfo.environment["SPYHUNTER_SIM"],
           let duration = Double(seconds) {
            simulate(seconds: duration)
            NSApp.terminate(nil)
            return
        }
        buildMenu()
        buildWindow()
        installGlobalKeyMonitor()

        AudioManager.shared.prepare()
        InputManager.shared.start()

        if DevCapture.forcedScene == "game" {
            let scene = GameScene(size: GameConfig.canvasSize)
            scene.scaleMode = .aspectFit
            skView.presentScene(scene)
        } else {
            skView.presentScene(TitleScene(size: GameConfig.canvasSize))
        }
        DevCapture.scheduleIfRequested(view: skView)

        if Settings.fullscreen {
            restoringFullscreen = true
            // Defer so the window has finished ordering in first.
            DispatchQueue.main.async { [weak self] in
                self?.window.toggleFullScreen(nil)
                self?.restoringFullscreen = false
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    // MARK: - Window

    private func buildWindow() {
        // Fit a 2:3 portrait canvas into most of the screen's usable height.
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let aspect = GameConfig.canvasWidth / GameConfig.canvasHeight
        var height = (visible.height * 0.88).rounded()
        var width = (height * aspect).rounded()
        if width > visible.width * 0.9 {
            width = (visible.width * 0.9).rounded()
            height = (width / aspect).rounded()
        }

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "Spy Hunter \(GameConfig.version)"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentAspectRatio = NSSize(width: GameConfig.canvasWidth,
                                           height: GameConfig.canvasHeight)
        window.center()

        skView = SKView(frame: NSRect(origin: .zero, size: CGSize(width: width, height: height)))
        skView.autoresizingMask = [.width, .height]
        skView.ignoresSiblingOrder = true
        skView.preferredFramesPerSecond = 60
        window.contentView = skView

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// F1 toggles fullscreen from any scene, and the choice is remembered.
    func toggleFullscreen() {
        window.toggleFullScreen(nil)
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        if !restoringFullscreen { Settings.fullscreen = true }
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        Settings.fullscreen = false
    }

    private func installGlobalKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // F1 (keyCode 122) is handled app-wide so every scene honours it.
            if event.keyCode == 122 {
                self?.toggleFullscreen()
                return nil
            }
            return event
        }
    }

    // MARK: - Menu

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Spy Hunter",
                        action: #selector(showAbout), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Toggle Full Screen",
                        action: #selector(menuToggleFullscreen), keyEquivalent: "f").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Spy Hunter",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Spy Hunter",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func menuToggleFullscreen() { toggleFullscreen() }

    /// Dev helper: runs the game loop headlessly at a fixed timestep and prints
    /// the world state each second.
    ///
    /// macOS stops rendering an occluded or background window, which freezes a
    /// SpriteKit scene's actions and `update(_:)` entirely — so timed
    /// screenshots of a hidden window capture nothing but the first frame.
    /// Driving the simulation directly sidesteps that and makes gameplay
    /// verifiable without a visible window. Enabled by SPYHUNTER_SIM=<seconds>.
    private func simulate(seconds: Double) {
        AudioManager.shared.prepare()
        let view = SKView(frame: NSRect(origin: .zero, size: GameConfig.canvasSize))
        let scene = GameScene(size: GameConfig.canvasSize)
        scene.scaleMode = .aspectFit
        view.presentScene(scene)
        scene.autopilot = true

        // SPYHUNTER_SIM_FIRE exercises the weapons, which a no-input sim never
        // reaches on its own.
        let exerciseWeapons = ProcessInfo.processInfo.environment["SPYHUNTER_SIM_FIRE"] != nil
        let step = 1.0 / 60.0
        var elapsed = 0.0
        var nextReport = 0.0
        var nextFire = 1.0
        print("time  " + "state")
        while elapsed < seconds {
            scene.simulateStep(dt: step)
            if exerciseWeapons, elapsed >= nextFire {
                nextFire += 0.5
                scene.simulateWeapons()
            }
            elapsed += step
            if elapsed >= nextReport {
                nextReport += 1.0
                print(String(format: "%5.1f  %@", elapsed, scene.debugSummary))
            }
        }
    }

    /// Dev helper: prints the generated track so bends and width changes can be
    /// checked without watching the game. Enabled by SPYHUNTER_ROADDUMP.
    private func dumpRoad() {
        let road = RoadManager(parent: SKNode())
        print("worldY  centreX  halfWidth  fork  terrain  weather")
        for step in stride(from: 0, through: 20000, by: 200) {
            let y = CGFloat(step)
            road.difficulty = min(1.4, y / 24_000)
            let shape = road.shape(y)
            let weather: String
            switch shape.weather {
            case .clear: weather = "clear"
            case .fog:   weather = "FOG"
            case .ice:   weather = "ICE"
            }
            let banks = "\(shape.bankLeft == .water ? "~" : ".")\(shape.bankRight == .water ? "~" : ".")"
            let terrain = shape.isWater ? "WATER" : "road "
            let geometry = String(format: "%6d  %7.1f  %6.1f  %4.2f",
                                  step, shape.centre, shape.halfWidth, Double(shape.fork))
            print("\(geometry)  \(terrain)  \(weather)  banks=\(banks)")
        }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Spy Hunter \(GameConfig.version)"
        alert.informativeText = """
            Developed by Tony Brice
            Technical support by Aaron Thorne.
            Testing by Triona Melhuish, AJ Brice and Nailesh Sheth.

            This game is free including the source code.
            All images belong to their respective creators.
            """
        alert.runModal()
    }
}
