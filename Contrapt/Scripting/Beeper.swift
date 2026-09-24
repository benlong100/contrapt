//
//  Beeper.swift
//  Contrapt
//

import AVFoundation

/// Plays the `beep` command's sound: a synthesized tone, so there's no
/// asset to bundle and no reliance on undocumented system sound IDs
/// (which vary by device and fall silent in silent mode). Scheduled
/// buffers queue, so `beep 3` produces three distinct sequential beeps.
@MainActor
final class Beeper {
    static let shared = Beeper()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let buffer: AVAudioPCMBuffer?

    private init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        buffer = format.flatMap(Self.makeBeepBuffer)
    }

    func beep() {
        guard let buffer else { return }
        do {
            #if os(iOS)
            // Media playback so the beep is audible regardless of the
            // silent switch; mixes rather than interrupting other audio.
            // macOS has no audio session — the engine plays directly.
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
            #endif
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            return
        }
        player.scheduleBuffer(buffer, at: nil, options: [])
        if !player.isPlaying {
            player.play()
        }
    }

    /// An 880 Hz tone with a click-free envelope, padded with a short
    /// silence so queued beeps stay distinct.
    private static func makeBeepBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let toneDuration = 0.18
        let totalDuration = 0.26
        let frames = AVAudioFrameCount(totalDuration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames

        let frequency = 880.0
        let attack = 0.005
        let release = 0.05
        for frame in 0..<Int(frames) {
            let time = Double(frame) / sampleRate
            guard time < toneDuration else {
                channel[frame] = 0
                continue
            }
            let envelope: Double = if time < attack {
                time / attack
            } else if time > toneDuration - release {
                max(0, (toneDuration - time) / release)
            } else {
                1
            }
            channel[frame] = Float(sin(2 * .pi * frequency * time) * envelope * 0.4)
        }
        return buffer
    }
}
