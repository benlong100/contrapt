//
//  BackgroundCountTests.swift
//  HyperTalk
//
//  `the number of cards` scoped to a background — the multi-background Home
//  stack loops over its own section with `the number of cds in this bg`.
//  The scope used to be parsed and ignored (whole-stack total), which broke
//  those loops.
//

import Foundation
import Testing
@testable import HyperTalk

@Test func cardCountInThisBackground() async throws {
    let host = MockHost(fields: ["out": ""])
    host.cardCount = 9
    host.backgroundCardCounts["this"] = 3
    try await run("""
    on mouseUp
      put the number of cds in this bg into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "3")
}

@Test func cardCountInNamedNumberedAndIDBackgrounds() async throws {
    let host = MockHost(fields: ["out": ""])
    host.cardCount = 9
    host.backgroundCardCounts["Paths"] = 4
    host.backgroundCardCounts["#2"] = 5
    host.backgroundCardCounts["id 7"] = 6
    try await run("""
    on mouseUp
      put the number of cards of bg "Paths" into field "out"
      put the number of cds of bg 2 after field "out"
      put the number of cds in bg id 7 after field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "456")
}

@Test func unscopedCardCountStillCountsTheStack() async throws {
    let host = MockHost(fields: ["out": ""])
    host.cardCount = 9
    host.backgroundCardCounts["this"] = 3
    try await run("""
    on mouseUp
      put the number of cards into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "9")
}

@Test func cardScopedCountIsStillIgnored() async throws {
    // `number of cds of this cd` is meaningless; it reads as the whole stack
    // (unchanged behavior) rather than erroring.
    let host = MockHost(fields: ["out": ""])
    host.cardCount = 9
    try await run("""
    on mouseUp
      put the number of cds of this cd into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "9")
}
