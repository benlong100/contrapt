//
//  PlayTests.swift
//  HyperTalk
//
//  `play <voice> [tempo <n>] [<notes>]` / `play stop` / `the sound`, and the
//  PlayNotes grammar (pitch, sharps/flats, sticky octave & duration, rests).
//

import Foundation
import Testing
@testable import HyperTalk

// MARK: - Notes grammar

@Test func notesParseWithDefaults() {
    // Default octave 4 (middle C = 60), default quarter note.
    let notes = PlayNotes.parse("c e g")
    #expect(notes == [
        PlayNote(midi: 60, beats: 1), PlayNote(midi: 64, beats: 1), PlayNote(midi: 67, beats: 1),
    ])
}

@Test func octaveAndDurationAreSticky() {
    // The Tour's arpeggio: "ce e g c5 ew" — eighth notes, then c in octave 5,
    // then a whole note e staying in octave 5.
    let notes = PlayNotes.parse("ce e g c5 ew")
    #expect(notes == [
        PlayNote(midi: 60, beats: 0.5),
        PlayNote(midi: 64, beats: 0.5),
        PlayNote(midi: 67, beats: 0.5),
        PlayNote(midi: 72, beats: 0.5),
        PlayNote(midi: 76, beats: 4),
    ])
}

@Test func sharpsFlatsRestsAndDots() {
    let notes = PlayNotes.parse("c#h db r bq.")
    #expect(notes == [
        PlayNote(midi: 61, beats: 2),      // c# half
        PlayNote(midi: 61, beats: 2),      // db (same pitch, sticky half)
        PlayNote(midi: nil, beats: 2),     // rest, sticky half
        PlayNote(midi: 71, beats: 1.5),    // b dotted quarter
    ])
}

@Test func tripletAndStrayTokensAreHandled() {
    let notes = PlayNotes.parse("cq3 zzz e")
    #expect(notes.count == 2) // "zzz" skipped
    #expect(notes[0] == PlayNote(midi: 60, beats: 2.0 / 3.0))
    #expect(notes[1].beats == 2.0 / 3.0) // triplet duration stays sticky
}

// MARK: - The command

@Test func playSendsVoiceTempoAndNotesToTheHost() async throws {
    let host = try await run("""
    on mouseUp
      play "harpsichord" tempo 600 "ce e g c5 ew"
    end mouseUp
    """)
    #expect(host.played.count == 1)
    #expect(host.played[0].voice == "harpsichord")
    #expect(host.played[0].tempo == 600)
    #expect(host.played[0].notes.count == 5)
}

@Test func playWithoutNotesOrTempo() async throws {
    let host = try await run("""
    on mouseUp
      play "boing"
    end mouseUp
    """)
    #expect(host.played.count == 1)
    #expect(host.played[0].voice == "boing")
    #expect(host.played[0].tempo == 120) // HyperCard default
    #expect(host.played[0].notes.isEmpty)
}

@Test func playStopReachesTheHost() async throws {
    let host = try await run("""
    on mouseUp
      play stop
    end mouseUp
    """)
    #expect(host.playStops == 1)
}

@Test func theSoundReadsTheHostsPlayingName() async throws {
    let host = MockHost(fields: ["out": ""])
    host.playingName = "boing"
    try await run("""
    on mouseUp
      put the sound into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "boing")
}

@Test func theSoundReadsDoneWhenIdle() async throws {
    let host = try await run("""
    on mouseUp
      put the sound into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "done")
}
