//
//  ParamAndMiscTests.swift
//  HyperTalk
//
//  More 2nd-batch gaps: `the param of N` / `the paramCount` / `the params`
//  (positional handler arguments — Summarizer, HyperX, Biorhythms), `show N
//  cards` (flip-through animation, no-op), and `the <fn> of X` for the full
//  function-with-of set (`the charToNum of X`).
//

import Foundation
import Testing
@testable import HyperTalk

@Test func paramAndParamCount() async throws {
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      demo "a","b","c"
    end mouseUp
    on demo
      put (the param of 2) & "/" & the paramCount into field "out"
    end demo
    """, host: host)
    #expect(host.fields["out"] == "b/3")
}

@Test func paramCallFormAndParams() async throws {
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      demo "x","y"
    end mouseUp
    on demo
      put param(1) & "," & the params into field "out"
    end demo
    """, host: host)
    #expect(host.fields["out"] == "x,x,y")
}

@Test func paramOutOfRangeIsEmpty() async throws {
    let host = MockHost(fields: ["out": "z"])
    try await run("""
    on mouseUp
      demo "only"
    end mouseUp
    on demo
      put the param of 5 into field "out"
    end demo
    """, host: host)
    #expect(host.fields["out"] == "")
}

@Test func showNCardsIsIgnored() async throws {
    let host = try await run("""
    on mouseUp
      show 10 cards
      beep
    end mouseUp
    """)
    #expect(host.beeps == 1)
}

@Test func theCharToNumOfValue() async throws {
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      put the charToNum of "A" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "65")
}
