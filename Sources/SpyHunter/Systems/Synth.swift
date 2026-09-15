import AVFoundation
import Foundation

/// Procedural sound-effect synthesis. Every effect in the game is generated
/// here at launch — no sampled audio besides the music track.
enum Synth {

    static let sampleRate: Double = 44_100

    /// Deterministic white noise so builds sound identical run to run.
    private struct Noise {
        private var state: UInt64
        init(seed: UInt64) { state = seed | 1 }
        mutating func next() -> Float {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Float(Int64(bitPattern: state &>> 11)) / Float(1 << 52) - 1
        }
    }

    /// Builds a mono buffer. `body(t, p, noise)` returns a sample in -1...1,
    /// where `t` is seconds and `p` is progress 0...1.
    static func make(_ seconds: Double,
                     seed: UInt64 = 0x5EED,
                     _ body: (Double, Double, inout Float) -> Float) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let out = buffer.floatChannelData![0]
        var noise = Noise(seed: seed)
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            let p = Double(i) / Double(frames)
            var n = noise.next()
            var s = body(t, p, &n)
            s = max(-1, min(1, s))
            out[i] = s
        }
        return buffer
    }

    // MARK: - Effects

    /// Machine-gun round: a bright click with a short noise tail.
    static var gunshot: AVAudioPCMBuffer {
        make(0.075, seed: 0xA11CE) { t, p, n in
            let env = Float(exp(-t * 55))
            let click = Float(sin(2 * .pi * 1_400 * t)) * Float(exp(-t * 180)) * 0.5
            return (n * 0.55 + click) * env
        }
    }

    /// Missile launch: rising whoosh with a rocket hiss.
    static var missileLaunch: AVAudioPCMBuffer {
        make(0.5, seed: 0x1337) { t, p, n in
            let sweep = 220.0 + 900.0 * t
            let body = Float(sin(2 * .pi * sweep * t)) * 0.4
            let hiss = n * 0.5 * Float(1 - p * 0.4)
            let env = Float(min(1, t * 30) * exp(-t * 4))
            return (body + hiss) * env
        }
    }

    /// Vehicle destruction: low thump under a decaying noise cloud.
    static var explosion: AVAudioPCMBuffer {
        make(0.9, seed: 0xB0075) { t, p, n in
            let thumpFreq = 90.0 * exp(-t * 3.2)
            let thump = Float(sin(2 * .pi * thumpFreq * t)) * Float(exp(-t * 4.5)) * 0.85
            let cloud = n * Float(exp(-t * 3.0)) * 0.7
            let crack = n * Float(exp(-t * 40)) * 0.6
            return thump + cloud + crack
        }
    }

    /// Bigger, longer blast for the player's car being destroyed.
    static var bigExplosion: AVAudioPCMBuffer {
        make(1.4, seed: 0xDEAD) { t, p, n in
            let thumpFreq = 70.0 * exp(-t * 2.2)
            let thump = Float(sin(2 * .pi * thumpFreq * t)) * Float(exp(-t * 3.0)) * 0.95
            let sub = Float(sin(2 * .pi * 38 * t)) * Float(exp(-t * 2.0)) * 0.5
            let cloud = n * Float(exp(-t * 2.0)) * 0.75
            return thump + sub + cloud
        }
    }

    /// Vehicle-on-vehicle impact: a low crunch with torn metal over it. Much
    /// weightier than the ricochet used for bullets glancing off armour.
    static var crash: AVAudioPCMBuffer {
        make(0.45, seed: 0xC7A5) { t, p, n in
            // Body blow.
            let thump = Float(sin(2 * .pi * (120 - 70 * t) * t)) * Float(exp(-t * 11)) * 0.9
            // Crumpling panels: noise shaped by a fast decay and a rattle.
            let rattle = Float(1 + 0.5 * sin(2 * .pi * 42 * t))
            let crunch = n * Float(exp(-t * 16)) * 0.85 * rattle
            // A brief metallic ring on top.
            let ring = Float(sin(2 * .pi * 900 * t)) * Float(exp(-t * 26)) * 0.25
            return thump + crunch + ring
        }
    }

    /// Small metallic hit when bullets strike armour.
    static var ricochet: AVAudioPCMBuffer {
        make(0.18, seed: 0x2EED) { t, p, n in
            let f = 2_600.0 * exp(-t * 8)
            let ping = Float(sin(2 * .pi * f * t)) * 0.5
            return (ping + n * 0.25) * Float(exp(-t * 22))
        }
    }

    /// Deploying the smoke screen — a pressurised hiss.
    static var smokeRelease: AVAudioPCMBuffer {
        make(0.65, seed: 0x5A0C) { t, p, n in
            let env = Float(min(1, t * 40) * exp(-t * 3.4))
            // Gentle band-limiting by averaging with a delayed copy is not
            // possible sample-by-sample here, so shape with a soft tone instead.
            let air = Float(sin(2 * .pi * 320 * t)) * 0.12
            return (n * 0.8 + air) * env
        }
    }

    /// Dropping the oil slick — a wet, lower splatter.
    static var oilRelease: AVAudioPCMBuffer {
        make(0.5, seed: 0x0117A) { t, p, n in
            let env = Float(min(1, t * 25) * exp(-t * 5))
            let glug = Float(sin(2 * .pi * (150 - 60 * t) * t)) * 0.45
            return (n * 0.4 + glug) * env
        }
    }

    /// Re-arming inside the weapons van: a rising confirmation arpeggio.
    static var weaponPickup: AVAudioPCMBuffer {
        make(0.55) { t, p, _ in
            let steps: [Double] = [523.25, 659.25, 783.99, 1046.50]
            let i = min(steps.count - 1, Int(t / 0.12))
            let local = t - Double(i) * 0.12
            let env = Float(exp(-local * 9)) * Float(1 - p * 0.3)
            return Float(sin(2 * .pi * steps[i] * t)) * env * 0.55
        }
    }

    /// Tyres losing grip.
    static var skid: AVAudioPCMBuffer {
        make(0.7, seed: 0x5C1D) { t, p, n in
            let env = Float(min(1, t * 12) * exp(-t * 2.6))
            let squeal = Float(sin(2 * .pi * (900 + 250 * sin(2 * .pi * 7 * t)) * t)) * 0.35
            return (squeal + n * 0.25) * env
        }
    }

    /// Hitting water / boat wake.
    static var splash: AVAudioPCMBuffer {
        make(0.6, seed: 0x5915) { t, p, n in
            let env = Float(min(1, t * 60) * exp(-t * 5.5))
            let body = Float(sin(2 * .pi * 180 * t)) * 0.3 * Float(exp(-t * 8))
            return (n * 0.7 + body) * env
        }
    }

    /// Menu / attract-mode blip.
    static var blip: AVAudioPCMBuffer {
        make(0.09) { t, p, _ in
            Float(sin(2 * .pi * 880 * t)) * Float(exp(-t * 26)) * 0.5
        }
    }

    /// Confirmation when entering initials.
    static var confirm: AVAudioPCMBuffer {
        make(0.3) { t, p, _ in
            let f: Double = t < 0.1 ? 660 : 990
            return Float(sin(2 * .pi * f * t)) * Float(exp(-t * 7)) * 0.5
        }
    }

    /// Extra-car award.
    static var extraCar: AVAudioPCMBuffer {
        make(0.8) { t, p, _ in
            let steps: [Double] = [659.25, 783.99, 1046.50, 1318.51]
            let i = min(steps.count - 1, Int(t / 0.16))
            let local = t - Double(i) * 0.16
            return Float(sin(2 * .pi * steps[i] * t)) * Float(exp(-local * 7)) * 0.5
        }
    }

    /// One second of engine tone, designed to loop seamlessly. Pitch is shifted
    /// at playback time to track road speed.
    static var engineLoop: AVAudioPCMBuffer {
        // Use an exact number of cycles of the base frequency so the loop joins
        // without a click.
        let base: Double = 55
        return make(1.0, seed: 0x3E691) { t, _, n in
            var s: Float = 0
            // Stacked harmonics give the engine a buzzy, mechanical character.
            for (h, amp) in [(1.0, 0.50), (2.0, 0.28), (3.0, 0.16), (5.0, 0.09)] {
                s += Float(sin(2 * .pi * base * h * t)) * Float(amp)
            }
            return s * 0.5 + n * 0.06
        }
    }
}
