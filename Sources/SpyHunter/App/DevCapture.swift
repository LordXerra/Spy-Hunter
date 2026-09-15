import AppKit
import SpriteKit

/// Development helper: renders the live scene to a PNG so changes can be
/// checked without a windowed screenshot.
///
///   SPYHUNTER_SHOT=/tmp/shot.png          where to write
///   SPYHUNTER_SHOT_DELAY=3                seconds to wait first (default 2)
///   SPYHUNTER_SHOT_QUIT=1                 terminate after capturing
///
/// Has no effect unless SPYHUNTER_SHOT is set, so shipping builds are unaffected.
enum DevCapture {

    static var isEnabled: Bool { path != nil }

    private static var path: String? {
        ProcessInfo.processInfo.environment["SPYHUNTER_SHOT"]
    }

    private static var delay: TimeInterval {
        TimeInterval(ProcessInfo.processInfo.environment["SPYHUNTER_SHOT_DELAY"] ?? "") ?? 2
    }

    private static var shouldQuit: Bool {
        ProcessInfo.processInfo.environment["SPYHUNTER_SHOT_QUIT"] != nil
    }

    /// SPYHUNTER_SCENE=game jumps straight into gameplay; SPYHUNTER_PAGE
    /// (title | scores | credits) picks the attract page to open on.
    static var forcedScene: String? {
        ProcessInfo.processInfo.environment["SPYHUNTER_SCENE"]
    }

    static var forcedPage: String? {
        ProcessInfo.processInfo.environment["SPYHUNTER_PAGE"]
    }

    static func scheduleIfRequested(view: SKView) {
        guard let path else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            capture(view: view, to: path)
            if shouldQuit { NSApp.terminate(nil) }
        }
    }

    static func capture(view: SKView, to path: String) {
        guard let scene = view.scene,
              let texture = view.texture(from: scene),
              let cg = texture.cgImage() as CGImage? else {
            NSLog("Spy Hunter: capture failed")
            return
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            NSLog("Spy Hunter: captured \(cg.width)x\(cg.height) -> \(path)")
        } catch {
            NSLog("Spy Hunter: capture write failed — \(error)")
        }
    }
}
