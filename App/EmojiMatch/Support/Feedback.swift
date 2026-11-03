import AVFoundation
import EmojiMatchCore
import UIKit

/// Everything the player feels and hears, gated by their settings.
@MainActor
protocol GameFeedback: AnyObject {
    func tileSelected(index: Int)
    func matched()
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

    func tileSelected(index: Int) {
        if hapticsOn {
            selectHaptic.impactOccurred()
            selectHaptic.prepare()
        }
        if soundOn { synth.play(index == 0 ? .selectFirst : .selectSecond) }
    }

    func matched() {
        if hapticsOn {
            matchHaptic.impactOccurred()
            matchHaptic.prepare()
        }
        if soundOn { synth.play(.pop) }
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
    enum Sound: CaseIterable {
        case selectFirst, selectSecond, pop, tick, timeUp, fanfare
    }

    private static let sampleRate = 44_100.0
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: SoundSynth.sampleRate, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
        for _ in 0..<6 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        engine.mainMixerNode.outputVolume = 0.7
        for sound in Sound.allCases { buffers[sound] = Self.makeBuffer(sound, format: format) }
    }

    func play(_ sound: Sound) {
        guard let buffer = buffers[sound] else { return }
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

    private struct Note {
        let start: Double
        let frequency: Double
        let endFrequency: Double?
        let duration: Double
        let gain: Double

        init(_ start: Double, _ frequency: Double, to endFrequency: Double? = nil, duration: Double, gain: Double) {
            self.start = start
            self.frequency = frequency
            self.endFrequency = endFrequency
            self.duration = duration
            self.gain = gain
        }
    }

    private static func notes(for sound: Sound) -> [Note] {
        switch sound {
        case .selectFirst:
            return [Note(0, 660, duration: 0.07, gain: 0.3)]
        case .selectSecond:
            return [Note(0, 880, duration: 0.07, gain: 0.32)]
        case .pop:
            return [
                Note(0, 900, to: 240, duration: 0.09, gain: 0.5),
                Note(0.05, 1319, duration: 0.14, gain: 0.25),
                Note(0.09, 1760, duration: 0.18, gain: 0.2),
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

    private static func makeBuffer(_ sound: Sound, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let notes = notes(for: sound)
        let length = (notes.map { $0.start + $0.duration }.max() ?? 0) + 0.01
        let frames = AVAudioFrameCount(length * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for frame in 0..<Int(frames) { samples[frame] = 0 }
        for note in notes {
            var phase = 0.0
            let first = Int(note.start * sampleRate)
            let count = Int(note.duration * sampleRate)
            for index in 0..<count where first + index < Int(frames) {
                let t = Double(index) / Double(count)
                let frequency = note.frequency + ((note.endFrequency ?? note.frequency) - note.frequency) * t
                phase += 2 * .pi * frequency / sampleRate
                // Short attack, exponential decay, and a touch of octave for a rounder bell tone.
                let envelope = min(1, t * 40) * pow(1 - t, 2.5)
                let value = (sin(phase) + 0.25 * sin(2 * phase)) * envelope * note.gain
                samples[first + index] += Float(value)
            }
        }
        return buffer
    }
}
