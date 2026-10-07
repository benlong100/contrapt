//
//  LockScreenTests.swift
//  HyperTalk
//
//  `lock screen` / `unlock screen` — the flicker-free-update commands. Contrapt
//  re-renders reactively, so they're accepted no-ops rather than "Can't
//  understand" errors (the classic openCard "Card N of M" idiom uses them).
//

import Foundation
import Testing
@testable import HyperTalk

@Test func lockAndUnlockScreenAreNoOps() async throws {
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      lock screen
      put "hi" into field "out"
      unlock screen
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "hi")
}

@Test func unlockScreenWithVisualEffectIsAccepted() async throws {
    // The trailing `with visual effect …` is swallowed, not mis-parsed.
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      lock screen
      unlock screen with visual effect wipe left
      put "done" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "done")
}

@Test func lockMessagesAndRecentAreNoOps() async throws {
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      lock messages
      lock recent
      put "ok" into field "out"
      unlock recent
      unlock messages
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "ok")
}

@Test func openCardNumberIdiomRuns() async throws {
    // The reported background handler, verbatim shape: lock screen, fill a
    // "Card Number" background field with "Card N of M", unlock screen.
    let host = MockHost(fields: ["background card number": ""])
    host.cardCount = 7
    host.properties["this card.number"] = "3"
    try await run("""
    on openCard
      lock screen
      put "Card" && number of this card && "of" && number of cards into background field "Card Number"
      unlock screen
    end openCard
    """, handler: "openCard", host: host)
    #expect(host.fields["background card number"] == "Card 3 of 7")
}
