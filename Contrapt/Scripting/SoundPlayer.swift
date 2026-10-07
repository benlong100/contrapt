//
//  SoundPlayer.swift
//  Contrapt
//
//  Plays the `play` command's sounds: a stack's imported `snd ` samples (WAV
//  assets), pitch-shifted per note for melodies, with a synthesized tone as
//  the fallback voice when a stack has no sound by the scripted name. One
//  sound plays at a time, as in HyperCard — a new `play` replaces the current
//  one, `play stop` silences it, and `the sound` reports the playing voice's
//  name ("done" when idle).
//

import AVFoundation
import HyperTalk

@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat?
    /// The voice name `the sound` reports; "done" when idle. A generation
    /// counter guards the async completion so a newer play isn't cleared by
    /// an older one finishing.
    private(set) var playingName = "done"
    private var generation = 0

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    /// Starts the voice (WAV bytes, or nil for the synthesized tone),
    /// rendering `notes` as a melody at `tempo` quarter-notes per minute.
    /// `baseNote` is the MIDI pitch the sample plays as recorded — notes are
    /// shifted relative to it (Harpsichord is 67, not middle C). Playback is
    /// asynchronous — the caller (a running script) continues.
    func play(name: String, wav: Data?, baseNote: Int = 60, tempo: Double, notes: [PlayNote]) {
        guard let format else { return }
        let source = wav.flatMap(SndSound.samplesFromWAV)
        // A voice that can't render (undecodable sample, empty melody) still
        // ends the current sound, so `the sound` reads "done" and a
        // `wait until the sound is "done"` doesn't hang on a stale name.
        guard let buffer = Self.renderBuffer(source: source, baseNote: baseNote, tempo: tempo, notes: notes, format: format) else {
            stop()
            return
        }
        stop()
        do {
            #if os(iOS)
            // Media playback: audible past the silent switch, mixing rather
            // than interrupting. macOS has no session — the engine just plays.
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
            #endif
            if !engine.isRunning { try engine.start() }
        } catch { return }
        playingName = name
        generation += 1
        let thisGeneration = generation
        player.scheduleBuffer(buffer, at: nil)
        player.play()
        // Report "done" after the buffer's own duration rather than relying on
        // AVAudioPlayerNode's completion callback, which can be delayed or (on a
        // stopped engine) not fire at all — which would hang the classic
        // `wait until the sound is "done"` poll forever. The generation guard
        // keeps a newer play/stop from being cleared by this one finishing.
        let seconds = Double(buffer.frameLength) / format.sampleRate + 0.05
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, self.generation == thisGeneration else { return }
            self.playingName = "done"
        }
    }

    /// `play stop` — silence and read as done.
    func stop() {
        generation += 1
        if player.isPlaying { player.stop() }
        playingName = "done"
    }

    // MARK: - Rendering

    /// The whole utterance as one buffer at the output format: the plain
    /// sample when there are no notes, else each note's pitched rendering laid
    /// end to end. One buffer keeps scheduling (and `play stop`) trivial.
    private static func renderBuffer(source: (samples: [Float], sampleRate: Double)?,
                                     baseNote: Int, tempo: Double, notes: [PlayNote],
                                     format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let outRate = format.sampleRate
        var rendered: [Float]
        if notes.isEmpty {
            if let source {
                rendered = resample(source.samples, by: source.sampleRate / outRate)
            } else {
                rendered = tone(midi: 60, seconds: 0.3, sampleRate: outRate)
            }
        } else {
            rendered = []
            let secondsPerBeat = 60.0 / tempo
            for note in notes {
                let seconds = note.beats * secondsPerBeat
                let frames = Int(seconds * outRate)
                guard let midi = note.midi else {
                    rendered.append(contentsOf: [Float](repeating: 0, count: frames))
                    continue
                }
                if let source {
                    // Pitch by resampling: rate 2^(semitones/12) from the
                    // sample's own recorded pitch (its snd base note).
                    // Truncate to the note's length; pad if it rings short.
                    let rate = pow(2.0, Double(midi - baseNote) / 12.0) * (source.sampleRate / outRate)
                    var noteSamples = resample(source.samples, by: rate)
                    if noteSamples.count > frames {
                        noteSamples.removeLast(noteSamples.count - frames)
                        // A 5 ms fade-out at the cut avoids a click.
                        let fade = min(noteSamples.count, Int(outRate * 0.005))
                        for i in 0..<fade {
                            noteSamples[noteSamples.count - fade + i] *= Float(fade - i) / Float(fade)
                        }
                    } else {
                        noteSamples.append(contentsOf: [Float](repeating: 0, count: frames - noteSamples.count))
                    }
                    rendered.append(contentsOf: noteSamples)
                } else {
                    rendered.append(contentsOf: tone(midi: midi, seconds: seconds, sampleRate: outRate))
                }
            }
        }
        guard !rendered.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rendered.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(rendered.count)
        for (index, sample) in rendered.enumerated() { channel[index] = sample }
        return buffer
    }

    /// Linear-interpolation resampling: `rate` > 1 reads the source faster
    /// (higher pitch, shorter result).
    private static func resample(_ samples: [Float], by rate: Double) -> [Float] {
        guard rate > 0, samples.count > 1 else { return samples }
        let outCount = max(1, Int(Double(samples.count) / rate))
        var out = [Float](repeating: 0, count: outCount)
        for i in 0..<outCount {
            let position = Double(i) * rate
            let index = Int(position)
            guard index + 1 < samples.count else {
                out[i] = samples[min(index, samples.count - 1)]
                break
            }
            let fraction = Float(position - Double(index))
            out[i] = samples[index] * (1 - fraction) + samples[index + 1] * fraction
        }
        return out
    }

    /// The fallback voice: a soft square-ish tone at the note's frequency with
    /// a click-free envelope (same family as Beeper's beep).
    private static func tone(midi: Int, seconds: Double, sampleRate: Double) -> [Float] {
        let frames = Int(seconds * sampleRate)
        guard frames > 0 else { return [] }
        let frequency = 440.0 * pow(2.0, Double(midi - 69) / 12.0)
        let attack = 0.005
        let release = min(0.05, seconds * 0.2)
        var out = [Float](repeating: 0, count: frames)
        for frame in 0..<frames {
            let time = Double(frame) / sampleRate
            let envelope: Double = if time < attack {
                time / attack
            } else if time > seconds - release {
                max(0, (seconds - time) / release)
            } else {
                1
            }
            // A sine plus a quieter octave harmonic reads less like a test tone.
            let value = sin(2 * .pi * frequency * time) * 0.35 + sin(4 * .pi * frequency * time) * 0.1
            out[frame] = Float(value * envelope)
        }
        return out
    }
}
