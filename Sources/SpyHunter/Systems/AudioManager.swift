import AVFoundation

enum SoundEffect: CaseIterable {
    case gunshot, missileLaunch, explosion, bigExplosion, ricochet, crash
    case smokeRelease, oilRelease, weaponPickup, skid, splash
    case blip, confirm, extraCar
}

/// The two supplied music tracks.
enum MusicTrack: String, CaseIterable {
    /// Plays over the title screen and attract cycle.
    case title = "TitleMusic"
    /// Plays during a game.
    case game = "Music"
}

/// Music playback plus the procedurally generated sound-effect bank.
final class AudioManager {
    static let shared = AudioManager()

    private let engine = AVAudioEngine()
    private var buffers: [SoundEffect: AVAudioPCMBuffer] = [:]

    /// Round-robin pool so overlapping effects do not cut each other off.
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private let voiceCount = 12

    /// Dedicated looping engine note, pitch-shifted with road speed.
    private let enginePlayer = AVAudioPlayerNode()
    private let engineSpeed = AVAudioUnitVarispeed()
    private var engineRunning = false

    private var players: [MusicTrack: AVAudioPlayer] = [:]
    /// The track the game wants playing; honoured whenever music is enabled, so
    /// toggling music back on resumes the right one for the current screen.
    private var desiredTrack: MusicTrack = .title
    private var currentTrack: MusicTrack?

    var sfxVolume: Float = 0.55 { didSet { sfxMixer.outputVolume = sfxVolume } }
    private let sfxMixer = AVAudioMixerNode()

    private init() {}

    // MARK: - Setup

    func prepare() {
        buildGraph()
        buildBuffers()
        prepareMusic()
    }

    private func buildGraph() {
        engine.attach(sfxMixer)
        engine.connect(sfxMixer, to: engine.mainMixerNode, format: nil)
        sfxMixer.outputVolume = sfxVolume

        let format = AVAudioFormat(standardFormatWithSampleRate: Synth.sampleRate, channels: 1)
        for _ in 0..<voiceCount {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: sfxMixer, format: format)
            voices.append(node)
        }

        engine.attach(enginePlayer)
        engine.attach(engineSpeed)
        engine.connect(enginePlayer, to: engineSpeed, format: format)
        engine.connect(engineSpeed, to: sfxMixer, format: format)

        do {
            try engine.start()
        } catch {
            NSLog("Spy Hunter: audio engine failed to start — \(error)")
        }
    }

    private func buildBuffers() {
        buffers[.gunshot] = Synth.gunshot
        buffers[.missileLaunch] = Synth.missileLaunch
        buffers[.explosion] = Synth.explosion
        buffers[.bigExplosion] = Synth.bigExplosion
        buffers[.ricochet] = Synth.ricochet
        buffers[.crash] = Synth.crash
        buffers[.smokeRelease] = Synth.smokeRelease
        buffers[.oilRelease] = Synth.oilRelease
        buffers[.weaponPickup] = Synth.weaponPickup
        buffers[.skid] = Synth.skid
        buffers[.splash] = Synth.splash
        buffers[.blip] = Synth.blip
        buffers[.confirm] = Synth.confirm
        buffers[.extraCar] = Synth.extraCar
    }

    // MARK: - Effects

    func play(_ effect: SoundEffect, volume: Float = 1.0) {
        guard Settings.soundOn, engine.isRunning, let buffer = buffers[effect] else { return }
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.volume = volume
        voice.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        voice.play()
    }

    // MARK: - Engine note

    func startEngineNote() {
        guard Settings.soundOn, engine.isRunning, !engineRunning else { return }
        enginePlayer.scheduleBuffer(Synth.engineLoop, at: nil, options: .loops, completionHandler: nil)
        enginePlayer.volume = 0.22
        enginePlayer.play()
        engineRunning = true
    }

    func stopEngineNote() {
        guard engineRunning else { return }
        enginePlayer.stop()
        engineRunning = false
    }

    /// `normalised` is 0 at minimum road speed, 1 at maximum.
    func setEngineSpeed(_ normalised: CGFloat) {
        let clamped = max(0, min(1, normalised))
        engineSpeed.rate = Float(0.85 + clamped * 1.15)
    }

    // MARK: - Music

    private func prepareMusic() {
        for track in MusicTrack.allCases {
            guard let url = GameResources.url(track.rawValue, "mp3") else {
                NSLog("Spy Hunter: \(track.rawValue).mp3 not found in bundle")
                continue
            }
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.numberOfLoops = -1
                player.volume = 0.5
                player.prepareToPlay()
                players[track] = player
            } catch {
                NSLog("Spy Hunter: could not load \(track.rawValue) — \(error)")
            }
        }
    }

    /// Requests a track. Switches immediately if a different one is playing.
    func playMusic(_ track: MusicTrack) {
        desiredTrack = track
        applyMusic()
    }

    /// Resumes whatever the current screen asked for — used when the player
    /// turns music back on from the options menu.
    func startMusic() {
        applyMusic()
    }

    private func applyMusic() {
        guard Settings.musicOn else {
            stopMusic()
            return
        }
        // Already playing the right thing.
        if currentTrack == desiredTrack, players[desiredTrack]?.isPlaying == true {
            return
        }
        stopMusic()
        // Fall back to the game track if the requested one failed to load.
        guard let player = players[desiredTrack] ?? players[.game] else { return }
        player.currentTime = 0
        player.play()
        currentTrack = desiredTrack
    }

    func stopMusic() {
        players.values.forEach { $0.stop() }
        currentTrack = nil
    }

    func setMusicVolume(_ v: Float) {
        players.values.forEach { $0.volume = v }
    }

    var isMusicPlaying: Bool { currentTrack != nil }
}
