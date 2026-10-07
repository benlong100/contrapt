//
//  SndSound.swift
//  Contrapt
//
//  Decoder for classic Mac `snd ` resources — the sampled sounds HyperCard's
//  `play` command names ("boing", "flute", "harpsichord", and any sound a
//  stack carries in its resource fork). The legacy importer decodes each to a
//  WAV asset; SoundPlayer renders them (pitch-shifted per note for melodies).
//
//  Format (Inside Macintosh: Sound): a format-1 resource opens with a list of
//  data types ('snd ' modifiers), format 2 with a reference count; both are
//  followed by sound commands. The samples live in a sound header pointed to
//  by a bufferCmd/soundCmd whose param2 is the header's offset:
//    standard header  (encode 0x00): 8-bit unsigned mono samples
//    extended header  (encode 0xFF): 8/16-bit, multi-channel
//    compressed header (encode 0xFE): MACE/IMA — not supported (rare in
//      HyperCard stacks; report nil and the importer skips the sound)
//
//  Pure Foundation, so it runs the same on macOS and iOS and can be exercised
//  by a standalone harness.
//

import Foundation

enum SndSound {
    /// Decoded PCM: mono float samples at `sampleRate`, plus the header's base
    /// MIDI note (60 = middle C — the pitch the sample plays as recorded).
    struct Decoded {
        var samples: [Float]
        var sampleRate: Double
        var baseNote: Int
    }

    /// Decodes a `snd ` resource's samples, or nil if the resource has no
    /// sampled data Contrapt can read (e.g. MACE-compressed).
    static func decode(_ data: Data) -> Decoded? {
        let d = [UInt8](data)
        func u16(_ o: Int) -> Int { o + 2 <= d.count ? Int((UInt16(d[o]) << 8) | UInt16(d[o+1])) : 0 }
        func u32(_ o: Int) -> Int { o + 4 <= d.count ? Int((UInt32(d[o]) << 24) | (UInt32(d[o+1]) << 16) | (UInt32(d[o+2]) << 8) | UInt32(d[o+3])) : 0 }
        guard d.count >= 6 else { return nil }

        // Header: format 1 lists data types (6 bytes each); format 2 has a
        // reference count. Both end with a command count + commands.
        let format = u16(0)
        var p: Int
        switch format {
        case 1:
            let typeCount = u16(2)
            p = 4 + typeCount * 6
        case 2:
            p = 4 // reference count
        default:
            return nil
        }
        let commandCount = u16(p)
        p += 2

        // Find the first bufferCmd/soundCmd; its param2 is the sound header's
        // offset within the resource. Bit 15 (dataOffsetFlag) marks the
        // param2-is-offset form, but some tools leave it clear — accept both.
        var headerOffset: Int?
        for index in 0..<commandCount {
            let base = p + index * 8
            let command = u16(base) & 0x7FFF
            if command == 0x8050 & 0x7FFF || command == 0x8051 & 0x7FFF || command == 80 || command == 81 {
                headerOffset = u32(base + 4)
                break
            }
        }
        guard let offset = headerOffset, offset + 22 <= d.count else { return nil }

        // SoundHeader: samplePtr(4) length(4) sampleRate(4, 16.16 fixed)
        // loopStart(4) loopEnd(4) encode(1) baseFrequency(1), then data.
        let rate = Double(u32(offset + 8)) / 65536.0
        guard rate > 0 else { return nil }
        let encode = Int(d[offset + 20])
        let baseNote = Int(d[offset + 21])

        switch encode {
        case 0x00:
            // Standard: `length` 8-bit unsigned mono samples follow.
            let length = u32(offset + 4)
            let start = offset + 22
            guard length > 0, start + length <= d.count else { return nil }
            let samples = d[start..<start + length].map { Float($0) / 127.5 - 1 }
            return Decoded(samples: samples, sampleRate: rate, baseNote: normalized(baseNote))
        case 0xFF:
            // Extended: numChannels(4, at +4) … numFrames(4, at +22), then a
            // 42-byte tail before the samples; sampleSize(2) sits at +48.
            guard offset + 64 <= d.count else { return nil }
            let channels = max(1, u32(offset + 4))
            let frames = u32(offset + 22)
            let bits = u16(offset + 48)
            let start = offset + 64
            let bytesPerSample = bits == 16 ? 2 : 1
            let total = frames * channels * bytesPerSample
            guard frames > 0, start + total <= d.count else { return nil }
            var samples = [Float](repeating: 0, count: frames)
            for frame in 0..<frames {
                // Average channels down to mono.
                var sum: Float = 0
                for channel in 0..<channels {
                    let s = start + (frame * channels + channel) * bytesPerSample
                    if bits == 16 {
                        let value = Int16(bitPattern: UInt16((UInt16(d[s]) << 8) | UInt16(d[s+1])))
                        sum += Float(value) / 32768
                    } else {
                        sum += Float(d[s]) / 127.5 - 1
                    }
                }
                samples[frame] = sum / Float(channels)
            }
            return Decoded(samples: samples, sampleRate: rate, baseNote: normalized(baseNote))
        default:
            return nil // compressed (MACE/IMA) — unsupported
        }
    }

    /// Base notes outside the plausible MIDI range read as middle C.
    private static func normalized(_ note: Int) -> Int {
        (1...127).contains(note) ? note : 60
    }

    /// Renders decoded samples as a 16-bit mono WAV file — the asset format
    /// sounds are stored in (self-describing, playable anywhere).
    static func wavData(_ decoded: Decoded) -> Data {
        let sampleRate = UInt32(decoded.sampleRate.rounded())
        let dataSize = UInt32(decoded.samples.count * 2)
        var out = Data()
        func le16(_ v: UInt16) { out.append(UInt8(v & 0xFF)); out.append(UInt8(v >> 8)) }
        func le32(_ v: UInt32) { for shift in [0, 8, 16, 24] { out.append(UInt8((v >> UInt32(shift)) & 0xFF)) } }
        out.append(contentsOf: Array("RIFF".utf8)); le32(36 + dataSize)
        out.append(contentsOf: Array("WAVE".utf8))
        out.append(contentsOf: Array("fmt ".utf8)); le32(16)
        le16(1) // PCM
        le16(1) // mono
        le32(sampleRate)
        le32(sampleRate * 2) // byte rate
        le16(2) // block align
        le16(16) // bits
        out.append(contentsOf: Array("data".utf8)); le32(dataSize)
        for sample in decoded.samples {
            let clamped = max(-1, min(1, sample))
            le16(UInt16(bitPattern: Int16(clamped * 32767)))
        }
        return out
    }

    /// Reads back a WAV this file wrote (16-bit PCM mono) into float samples —
    /// the playback path, so SoundPlayer needs no file-based AVAudioFile.
    static func samplesFromWAV(_ data: Data) -> (samples: [Float], sampleRate: Double)? {
        let d = [UInt8](data)
        guard d.count > 44,
              String(bytes: d[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: d[8..<12], encoding: .ascii) == "WAVE" else { return nil }
        func le16(_ o: Int) -> Int { Int(d[o]) | (Int(d[o+1]) << 8) }
        func le32(_ o: Int) -> Int { Int(d[o]) | (Int(d[o+1]) << 8) | (Int(d[o+2]) << 16) | (Int(d[o+3]) << 24) }
        // Walk chunks to find fmt and data (they're ours, but stay robust).
        var p = 12
        var sampleRate = 0.0
        var samples: [Float] = []
        while p + 8 <= d.count {
            let tag = String(bytes: d[p..<p+4], encoding: .ascii) ?? ""
            let size = le32(p + 4)
            let body = p + 8
            if tag == "fmt ", body + 16 <= d.count {
                sampleRate = Double(le32(body + 4))
            } else if tag == "data", body + size <= d.count {
                samples.reserveCapacity(size / 2)
                var s = body
                while s + 2 <= body + size {
                    samples.append(Float(Int16(bitPattern: UInt16(le16(s)))) / 32767)
                    s += 2
                }
            }
            p = body + size + (size & 1)
        }
        guard sampleRate > 0, !samples.isEmpty else { return nil }
        return (samples, sampleRate)
    }
}
