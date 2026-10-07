//
//  PlayNotes.swift
//  HyperTalk
//
//  The `play` command's notes-string grammar, parsed to pitched notes the host
//  can render. HyperCard's format, one token per note:
//
//      <letter>[#|b][octave][duration]     e.g.  c  d#  e4  gw  c5e.  r q
//
//  - letter: a–g, or r for a rest.
//  - accidental: # sharp, b flat.
//  - octave: a digit run (middle C is c4); sticky — later notes keep the last
//    octave until one names another.
//  - duration: w h q e s t x (whole, half, quarter, eighth, 16th, 32nd, 64th),
//    optionally dotted (`.` = 1.5×) or triplet (`3` = 2/3); also sticky.
//    The default is a quarter note in octave 4.
//
//  Unrecognized tokens are skipped, as HyperCard ignored what it couldn't
//  read — a stray word can't halt the melody.
//

import Foundation

/// One parsed note: a MIDI pitch (middle C = 60; nil for a rest) and a length
/// in beats (a quarter note is 1 beat).
public struct PlayNote: Sendable, Equatable {
    public let midi: Int?
    public let beats: Double

    public init(midi: Int?, beats: Double) {
        self.midi = midi
        self.beats = beats
    }
}

public enum PlayNotes {
    /// Semitone of each letter within an octave (C = 0).
    private static let semitones: [Character: Int] = [
        "c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11,
    ]
    /// Beats per duration letter (quarter = 1).
    private static let durations: [Character: Double] = [
        "w": 4, "h": 2, "q": 1, "e": 0.5, "s": 0.25, "t": 0.125, "x": 0.0625,
    ]

    /// Parses a notes string into pitched notes. Octave and duration are
    /// sticky across notes, starting at octave 4 and quarter notes.
    public static func parse(_ text: String) -> [PlayNote] {
        var octave = 4
        var beats = 1.0
        var notes: [PlayNote] = []

        for token in text.lowercased().split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "," }) {
            var characters = Array(token)
            var index = 0

            // Pitch letter (or rest).
            guard index < characters.count else { continue }
            let letter = characters[index]
            let isRest = letter == "r"
            guard isRest || semitones[letter] != nil else { continue } // skip stray tokens
            index += 1

            // Accidental. `b` is only a flat when a pitch/duration can still
            // follow — a bare "b" already consumed the letter position.
            var accidental = 0
            if index < characters.count, characters[index] == "#" { accidental = 1; index += 1 }
            else if index < characters.count, characters[index] == "b" { accidental = -1; index += 1 }

            // Octave digits (sticky). A digit here — right after the pitch —
            // is always an octave; the triplet `3` only appears after a
            // duration letter, handled below.
            var digits = ""
            while index < characters.count, characters[index].isNumber {
                digits.append(characters[index])
                index += 1
            }
            if let value = Int(digits) { octave = value }

            // Duration letter (sticky), with optional . (dotted) or 3 (triplet).
            if index < characters.count, let base = durations[characters[index]] {
                var value = base
                index += 1
                if index < characters.count, characters[index] == "." { value *= 1.5; index += 1 }
                else if index < characters.count, characters[index] == "3" { value *= 2.0 / 3.0; index += 1 }
                beats = value
            }

            if isRest {
                notes.append(PlayNote(midi: nil, beats: beats))
            } else {
                let midi = 12 * (octave + 1) + semitones[letter]! + accidental
                notes.append(PlayNote(midi: midi, beats: beats))
            }
        }
        return notes
    }
}
