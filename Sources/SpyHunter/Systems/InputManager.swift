import AppKit
import GameController

/// Logical game actions, so scenes never care whether input came from the
/// keyboard or a DualShock 4 / DualSense pad.
enum GameAction: CaseIterable {
    case up, down, left, right
    case fire        // machine guns / missiles  — Left Shift, R2
    case weapon      // rear weapon: smoke / oil — Space, L2 or Square
    case start       // Return, Space, Cross, Options
    case back        // Escape, Circle
    case pause       // P, Options
}

/// Polled input. `update()` must be called once per frame (GameScene does it)
/// so that `wasPressed` edge detection works.
final class InputManager {
    static let shared = InputManager()

    private var held: Set<GameAction> = []
    private var previous: Set<GameAction> = []

    /// Keys currently down, by macOS key code.
    private var keysDown: Set<UInt16> = []
    private var leftShiftDown = false
    private var rightShiftDown = false

    private var monitors: [Any] = []
    private(set) var pad: GCExtendedGamepad?

    private init() {}

    // MARK: - Lifecycle

    func start() {
        installKeyboardMonitors()
        observeControllers()
    }

    // MARK: - Frame

    /// Snapshot state for edge detection. Call once per frame.
    func update() {
        previous = held
        held = currentState()
    }

    func isHeld(_ a: GameAction) -> Bool { held.contains(a) }
    func wasPressed(_ a: GameAction) -> Bool { held.contains(a) && !previous.contains(a) }
    func wasReleased(_ a: GameAction) -> Bool { !held.contains(a) && previous.contains(a) }

    /// True if any button that should dismiss an attract screen was pressed.
    var anyStartPressed: Bool {
        wasPressed(.start) || wasPressed(.fire) || wasPressed(.weapon)
    }

    // MARK: - Analogue

    /// -1 (full left) ... +1 (full right).
    var steerAxis: CGFloat {
        if let pad {
            let x = CGFloat(pad.leftThumbstick.xAxis.value)
            if abs(x) > 0.15 { return max(-1, min(1, x)) }
            if pad.dpad.left.isPressed { return -1 }
            if pad.dpad.right.isPressed { return 1 }
        }
        var v: CGFloat = 0
        if isHeld(.left) { v -= 1 }
        if isHeld(.right) { v += 1 }
        return v
    }

    /// +1 accelerate ... -1 brake.
    var throttleAxis: CGFloat {
        if let pad {
            let y = CGFloat(pad.leftThumbstick.yAxis.value)
            if abs(y) > 0.15 { return max(-1, min(1, y)) }
            if pad.dpad.up.isPressed { return 1 }
            if pad.dpad.down.isPressed { return -1 }
        }
        var v: CGFloat = 0
        if isHeld(.up) { v += 1 }
        if isHeld(.down) { v -= 1 }
        return v
    }

    // MARK: - State assembly

    private func currentState() -> Set<GameAction> {
        var s: Set<GameAction> = []

        // Keyboard
        if keysDown.contains(13) || keysDown.contains(126) { s.insert(.up) }     // W / Up
        if keysDown.contains(1)  || keysDown.contains(125) { s.insert(.down) }   // S / Down
        if keysDown.contains(0)  || keysDown.contains(123) { s.insert(.left) }   // A / Left
        if keysDown.contains(2)  || keysDown.contains(124) { s.insert(.right) }  // D / Right
        if leftShiftDown || rightShiftDown { s.insert(.fire) }                   // Left Shift
        if keysDown.contains(49) { s.insert(.weapon); s.insert(.start) }         // Space
        if keysDown.contains(36) { s.insert(.start) }                            // Return
        if keysDown.contains(53) { s.insert(.back) }                             // Escape
        if keysDown.contains(35) { s.insert(.pause) }                            // P

        // Controller
        if let pad {
            if pad.rightTrigger.isPressed || pad.rightShoulder.isPressed { s.insert(.fire) }
            if pad.leftTrigger.isPressed || pad.leftShoulder.isPressed
                || pad.buttonX.isPressed { s.insert(.weapon) }                   // L2 / L1 / Square
            if pad.buttonA.isPressed { s.insert(.start) }                        // Cross
            if pad.buttonB.isPressed { s.insert(.back) }                         // Circle
            if pad.buttonMenu.isPressed { s.insert(.pause); s.insert(.start) }   // Options
            if pad.dpad.up.isPressed { s.insert(.up) }
            if pad.dpad.down.isPressed { s.insert(.down) }
            if pad.dpad.left.isPressed { s.insert(.left) }
            if pad.dpad.right.isPressed { s.insert(.right) }
        }
        return s
    }

    // MARK: - Keyboard

    private func installKeyboardMonitors() {
        let down = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            if e.keyCode == 122 { return e }        // F1 handled by AppDelegate
            self.keysDown.insert(e.keyCode)
            // Swallow game keys so macOS does not beep at unhandled input.
            return self.isGameKey(e.keyCode) ? nil : e
        }
        let up = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] e in
            guard let self else { return e }
            self.keysDown.remove(e.keyCode)
            return self.isGameKey(e.keyCode) ? nil : e
        }
        let flags = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            guard let self else { return e }
            let shift = e.modifierFlags.contains(.shift)
            if e.keyCode == 56 { self.leftShiftDown = shift }
            if e.keyCode == 60 { self.rightShiftDown = shift }
            if !shift { self.leftShiftDown = false; self.rightShiftDown = false }
            return e
        }
        monitors = [down, up, flags].compactMap { $0 }
    }

    private func isGameKey(_ code: UInt16) -> Bool {
        // WASD, arrows, space, return, escape, P
        [0, 1, 2, 13, 35, 36, 49, 53, 123, 124, 125, 126].contains(code)
    }

    /// Called when a scene loses focus so keys do not stick down.
    func clearKeyboard() {
        keysDown.removeAll()
        leftShiftDown = false
        rightShiftDown = false
    }

    // MARK: - Controllers

    private func observeControllers() {
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] n in
                if let c = n.object as? GCController { self?.adopt(c) }
            }
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
                self?.pad = GCController.controllers().first?.extendedGamepad
            }
        GCController.controllers().forEach { adopt($0) }
        GCController.startWirelessControllerDiscovery {}
    }

    private func adopt(_ controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }
        pad = gamepad
        controller.playerIndex = .index1
        Haptics.shared.bind(to: controller)
    }

    /// Short rumble on impacts. Silently does nothing on pads without haptics.
    func rumble(intensity: Float = 0.8, duration: TimeInterval = 0.18) {
        Haptics.shared.rumble(intensity: intensity, duration: duration)
    }
}
