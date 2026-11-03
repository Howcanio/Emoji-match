import AVFoundation
import EmojiMatchCore
import UIKit

/// Everything the player feels and hears, gated by their settings.
@MainActor
protocol GameFeedback: AnyObject {
    func tileSelected(type: Int, index: Int)
    func matched(type: Int, count: Int)
    func multiplierRaised()
    func timerTick()
    func roundEnded(newBest: Bool)
}

@MainActor
final class SystemFeedback: GameFeedback {
    private let defaults: UserDefaults
    private let synth = SoundSynth()
    private let selectHaptic = UIImpactFeedbackGenerator(style: .light)
    private let matchHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private let endHaptic = UINotificationFeedbackGenerator()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [SettingsKeys.sound: true, SettingsKeys.haptics: true])
        selectHaptic.prepare()
        matchHaptic.prepare()
    }

    private var soundOn: Bool { defaults.bool(forKey: SettingsKeys.sound) }
    private var hapticsOn: Bool { defaults.bool(forKey: SettingsKeys.haptics) }

    func tileSelected(type: Int, index: Int) {
        if hapticsOn {
            selectHaptic.impactOccurred()
            selectHaptic.prepare()
        }
        if soundOn { synth.play(.emojiTap(type: type % SoundSynth.voices, step: min(index, SoundSynth.tapSteps - 1))) }
    }

    func matched(type: Int, count: Int) {
        if hapticsOn {
            matchHaptic.impactOccurred()
            matchHaptic.prepare()
        }
        guard soundOn else { return }
        synth.play(.emojiPop(type: type % SoundSynth.voices))
        let tier = ComboTier(grabSize: count)
        if tier != .none { synth.play(.combo(tier: tier.rawValue)) }
    }

    func multiplierRaised() {
        if hapticsOn { endHaptic.notificationOccurred(.success) }
        if soundOn { synth.play(.levelUp) }
    }

    func timerTick() {
        if soundOn { synth.play(.tick) }
    }

    func roundEnded(newBest: Bool) {
        if hapticsOn { endHaptic.notificationOccurred(newBest ? .success : .warning) }
        if soundOn { synth.play(newBest ? .fanfare : .timeUp) }
    }
}

/// Generates all sounds in code, so there are no audio assets to license or bundle.
/// Uses the ambient category: it mixes with the player's music and obeys the silent switch.
@MainActor
final class SoundSynth {
    enum Sound: Hashable {
        /// A short note in the emoji's voice, climbing a step with each tile in the chain.
        case emojiTap(type: Int, step: Int)
        /// The emoji's full signature sound, played when it pops.
        case emojiPop(type: Int)
        case combo(tier: Int)
        case levelUp, tick, timeUp, fanfare
    }

    /// One voice per tile type, in `EmojiCatalog` order.
    static let voices = 8
    static let tapSteps = 6

    static let allSounds: [Sound] = (0..<voices).flatMap { type in
        (0..<tapSteps).map { Sound.emojiTap(type: type, step: $0) } + [.emojiPop(type: type)]
    } + (1...4).map { Sound.combo(tier: $0) } + [.levelUp, .tick, .timeUp, .fanfare]

    private static let sampleRate = 44_100.0
    private static let sharedFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    /// Rendered once per launch; every round's synth plays from the same buffers.
    private static let sharedBuffers: [Sound: AVAudioPCMBuffer] = Dictionary(
        uniqueKeysWithValues: allSounds.compactMap { sound in
            makeBuffer(sound, format: sharedFormat).map { (sound, $0) }
        }
    )
    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
        for _ in 0..<8 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: Self.sharedFormat)
            players.append(player)
        }
        engine.mainMixerNode.outputVolume = 0.7
    }

    func play(_ sound: Sound) {
        guard let buffer = Self.sharedBuffers[sound] else { return }
        if !engine.isRunning {
            try? AVAudioSession.sharedInstance().setActive(true)
            try? engine.start()
        }
        guard engine.isRunning else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    private enum Wave {
        /// Rounded bell tone with a quick decay.
        case bell
        /// Pure tone that swells and fades, for long glides.
        case swell
        /// Buzzy square-ish tone with a flutter, for the frog's croak.
        case croak
        /// Short, bright plucked string.
        case pluck
        /// Hollow knock with an inharmonic overtone, like bamboo.
        case wood
        /// Hiss with the low end removed, for the citrus spray.
        case spray
    }

    private struct Note {
        let start: Double
        let frequency: Double
        let endFrequency: Double?
        let duration: Double
        let gain: Double
        let wave: Wave

        init(_ start: Double, _ frequency: Double, to endFrequency: Double? = nil, duration: Double, gain: Double, wave: Wave = .bell) {
            self.start = start
            self.frequency = frequency
            self.endFrequency = endFrequency
            self.duration = duration
            self.gain = gain
            self.wave = wave
        }
    }

    private static func notes(for sound: Sound) -> [Note] {
        switch sound {
        case .emojiTap(let type, let step):
            return [tapNote(type: type, pitch: pow(2, tapSemitones[step] / 12))]
        case .emojiPop(let type):
            return [Note(0, 900, to: 240, duration: 0.06, gain: 0.3)] + signature(type: type)
        case .combo(let tier):
            // A rising C major run that climbs higher for bigger combos, entering after the pop.
            let run: [Double] = [523, 659, 784, 1047, 1319, 1568]
            return run.prefix(tier + 2).enumerated().map { index, frequency in
                Note(0.1 + Double(index) * 0.06, frequency, duration: 0.14, gain: 0.2)
            }
        case .levelUp:
            // A high C major sparkle on top of the combo run.
            return [
                Note(0.42, 1568, duration: 0.12, gain: 0.2), Note(0.5, 2093, duration: 0.28, gain: 0.22),
            ]
        case .tick:
            return [Note(0, 1200, duration: 0.04, gain: 0.2)]
        case .timeUp:
            return [Note(0, 659, duration: 0.16, gain: 0.3), Note(0.14, 523, duration: 0.28, gain: 0.3)]
        case .fanfare:
            return [
                Note(0, 523, duration: 0.14, gain: 0.3), Note(0.12, 659, duration: 0.14, gain: 0.3),
                Note(0.24, 784, duration: 0.14, gain: 0.3), Note(0.36, 1047, duration: 0.36, gain: 0.32),
            ]
        }
    }

    /// A pentatonic climb, so any chain length sounds like a tune.
    private static let tapSemitones: [Double] = [0, 2, 4, 7, 9, 12]

    private static func tapNote(type: Int, pitch: Double) -> Note {
        switch type {
        case 0: return Note(0, 784 * pitch, to: 988 * pitch, duration: 0.07, gain: 0.28)
        case 1: return Note(0, 165 * pitch, to: 196 * pitch, duration: 0.08, gain: 0.22, wave: .croak)
        case 2: return Note(0, 440 * pitch, to: 784 * pitch, duration: 0.08, gain: 0.32, wave: .swell)
        case 3: return Note(0, 262 * pitch, to: 330 * pitch, duration: 0.11, gain: 0.4, wave: .swell)
        case 4: return Note(0, 1047 * pitch, duration: 0.06, gain: 0.26, wave: .pluck)
        case 5: return Note(0, 587 * pitch, to: 523 * pitch, duration: 0.07, gain: 0.3, wave: .pluck)
        case 6: return Note(0, 1319 * pitch, duration: 0.1, gain: 0.22)
        default: return Note(0, 330 * pitch, duration: 0.06, gain: 0.42, wave: .wood)
        }
    }

    private static func signature(type: Int) -> [Note] {
        switch type {
        case 0: // 😀 A three-note giggle.
            return [
                Note(0.03, 880, to: 1175, duration: 0.08, gain: 0.3),
                Note(0.12, 988, to: 1319, duration: 0.08, gain: 0.3),
                Note(0.21, 1109, to: 1480, duration: 0.1, gain: 0.3),
            ]
        case 1: // 🐸 Ribbit.
            return [
                Note(0.03, 180, to: 290, duration: 0.1, gain: 0.3, wave: .croak),
                Note(0.17, 200, to: 340, duration: 0.15, gain: 0.32, wave: .croak),
            ]
        case 2: // 🍓 A juicy bloop and a drip.
            return [
                Note(0.03, 300, to: 1100, duration: 0.13, gain: 0.45, wave: .swell),
                Note(0.17, 1500, to: 900, duration: 0.09, gain: 0.25, wave: .swell),
            ]
        case 3: // 🐳 A short whale song.
            return [
                Note(0.03, 170, to: 330, duration: 0.3, gain: 0.5, wave: .swell),
                Note(0.27, 330, to: 208, duration: 0.34, gain: 0.45, wave: .swell),
            ]
        case 4: // 🍊 A citrus spritz.
            return [
                Note(0.02, 0, duration: 0.18, gain: 0.3, wave: .spray),
                Note(0.03, 1568, to: 2093, duration: 0.13, gain: 0.2),
            ]
        case 5: // 🍇 Grapes bouncing away.
            return [
                Note(0.03, 784, duration: 0.07, gain: 0.32, wave: .pluck),
                Note(0.11, 659, duration: 0.07, gain: 0.3, wave: .pluck),
                Note(0.18, 587, duration: 0.07, gain: 0.28, wave: .pluck),
                Note(0.24, 523, duration: 0.09, gain: 0.26, wave: .pluck),
            ]
        case 6: // 🌸 Wind chimes.
            return [
                Note(0.03, 1568, duration: 0.3, gain: 0.18), Note(0.09, 1976, duration: 0.3, gain: 0.18),
                Note(0.15, 2349, duration: 0.3, gain: 0.16), Note(0.21, 3136, duration: 0.34, gain: 0.14),
            ]
        default: // 🐼 Bamboo knocks.
            return [
                Note(0.03, 392, duration: 0.08, gain: 0.5, wave: .wood),
                Note(0.13, 523, duration: 0.08, gain: 0.5, wave: .wood),
                Note(0.22, 294, duration: 0.11, gain: 0.5, wave: .wood),
            ]
        }
    }

    private static func sample(_ wave: Wave, phase: Double, t: Double, seconds: Double, previousNoise: inout Double) -> Double {
        let attack = min(1, t * 40)
        switch wave {
        case .bell:
            return (sin(phase) + 0.25 * sin(2 * phase)) * attack * pow(1 - t, 2.5)
        case .swell:
            return sin(phase) * sin(.pi * t)
        case .croak:
            let flutter = 0.6 + 0.4 * sin(2 * .pi * 34 * seconds)
            return (0.6 * (sin(phase) >= 0 ? 1 : -1) + 0.4 * sin(phase)) * flutter * attack * pow(1 - t, 1.2)
        case .pluck:
            return (sin(phase) + 0.4 * sin(3 * phase)) * attack * pow(1 - t, 4)
        case .wood:
            return (sin(phase) + 0.5 * sin(2.76 * phase)) * attack * pow(1 - t, 6)
        case .spray:
            let noise = Double.random(in: -1...1)
            defer { previousNoise = noise }
            return (noise - previousNoise) * 0.5 * attack * pow(1 - t, 2)
        }
    }

    /// The finished waveform, limited to full scale so overlapping notes can't clip.
    static func samples(for sound: Sound) -> [Float] {
        let notes = notes(for: sound)
        let length = (notes.map { $0.start + $0.duration }.max() ?? 0) + 0.01
        var samples = [Float](repeating: 0, count: Int(length * sampleRate))
        for note in notes {
            var phase = 0.0
            var previousNoise = 0.0
            let first = Int(note.start * sampleRate)
            let count = Int(note.duration * sampleRate)
            for index in 0..<count where first + index < samples.count {
                let t = Double(index) / Double(count)
                let frequency = note.frequency + ((note.endFrequency ?? note.frequency) - note.frequency) * t
                phase += 2 * .pi * frequency / sampleRate
                let seconds = Double(index) / sampleRate
                let value = sample(note.wave, phase: phase, t: t, seconds: seconds, previousNoise: &previousNoise)
                samples[first + index] += Float(value * note.gain)
            }
        }
        return samples.map { max(-1, min(1, $0)) }
    }

    private static func makeBuffer(_ sound: Sound, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let samples = samples(for: sound)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (index, value) in samples.enumerated() { channel[index] = value }
        return buffer
    }
}
