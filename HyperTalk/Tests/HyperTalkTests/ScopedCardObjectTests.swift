//
//  ScopedCardObjectTests.swift
//  HyperTalk
//
//  The object-model rework: card objects carry a GoDestination, so a card can
//  be scoped to a background (`card "X" of bkgnd "Y"`, `card 2 of bg "Z"`).
//  These pin the parse + interpreter plumbing (the MockHost keys properties by
//  a readable path); real background resolution is covered end-to-end in the
//  engine's ScopedCardObjectTests against a multi-background stack.
//

import Foundation
import Testing
@testable import HyperTalk

@Test func numberOfCardNamedInBackground() async throws {
    // `the number of card "Color" of bkgnd "Content"` — New Features' idiom.
    let host = MockHost(fields: ["out": ""])
    host.properties["card Color of bg Content.number"] = "17"
    try await run("""
    on mouseUp
      put the number of card "Color" of bkgnd "Content" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "17")
}

@Test func propertyOfCardNumberInBackground() async throws {
    // `the short name of card 2 of bg "Paths"` — numeric card, scoped.
    let host = MockHost(fields: ["out": ""])
    host.properties["card 2 of bg Paths.name"] = "Trails"
    try await run("""
    on mouseUp
      put the short name of card 2 of bg "Paths" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "Trails")
}

@Test func unscopedCardObjectStillResolvesGlobally() async throws {
    // Regression: a bare card object (no `of bkgnd`) keys the same as before.
    let host = MockHost(fields: ["out": ""])
    host.properties["card 2.name"] = "Second"
    try await run("""
    on mouseUp
      put the name of card 2 into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "Second")
}

@Test func cardInBackgroundExistence() async throws {
    // `there is a card "X" of bkgnd "Y"` resolves through the scoped object.
    let host = MockHost(fields: ["out": ""])
    host.properties["card Color of bg Content.name"] = "Color"
    try await run("""
    on mouseUp
      if there is a card "Color" of bkgnd "Content" then put "yes" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "yes")
}
