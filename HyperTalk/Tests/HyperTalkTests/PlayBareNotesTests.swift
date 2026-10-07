//
//  PlayBareNotesTests.swift
//  HyperTalk
//
//  `play <voice> [tempo N] <bare notes>` — the Manhole's sound buttons write
//  the note sequence unquoted (`play "Fiddle" tempo 370 b3 c#4 d e f# g`). The
//  notes are reconstructed from their tokens (so `#` and octave digits stay
//  attached) rather than parsed as an expression.
//

import Foundation
import Testing
@testable import HyperTalk

@Test func playBareNoteSequence() async throws {
    let host = try await run("""
    on mouseUp
      play "Fiddle" tempo 370 b3 c#4 d e f# g
    end mouseUp
    """)
    #expect(host.played.count == 1)
    #expect(host.played.first?.voice == "Fiddle")
    #expect(host.played.first?.tempo == 370)
    #expect(host.played.first?.notes.count == 6) // b3 c#4 d e f# g
}

@Test func playBareVoiceAndSingleNote() async throws {
    // `play drawer tempo 120 g4` — bare voice name + one note.
    let host = try await run("""
    on mouseUp
      play drawer tempo 120 g4
    end mouseUp
    """)
    #expect(host.played.first?.voice == "drawer")
    #expect(host.played.first?.notes.count == 1)
}

@Test func playQuotedNotesStillWorks() async throws {
    let host = try await run("""
    on mouseUp
      play "boing" "d e f a bw"
    end mouseUp
    """)
    #expect(host.played.first?.notes.count == 5)
}
