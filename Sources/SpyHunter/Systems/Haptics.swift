import CoreHaptics
import GameController

/// Controller rumble. DualSense and DualShock 4 both expose haptics through
/// GameController; anything else silently no-ops.
final class Haptics {
    static let shared = Haptics()

    private var engine: CHHapticEngine?
    private weak var boundController: GCController?

    private init() {}

    /// Rebinds the haptic engine when the active pad changes.
    func bind(to controller: GCController?) {
        guard controller !== boundController else { return }
        engine?.stop()
        engine = nil
        boundController = controller
        guard let controller,
              let created = controller.haptics?.createEngine(withLocality: .default) else { return }
        created.isAutoShutdownEnabled = true
        created.resetHandler = { [weak created] in try? created?.start() }
        do {
            try created.start()
            engine = created
        } catch {
            engine = nil
        }
    }

    func rumble(intensity: Float = 0.8, sharpness: Float = 0.5, duration: TimeInterval = 0.18) {
        guard let engine else { return }
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: 0,
            duration: duration)
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Rumble is cosmetic; ignore failures.
        }
    }
}
