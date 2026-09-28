//
//  PowerToolsScriptTests.swift
//  HyperTalk
//
//  Walls from Apple's Power Tools stack — its list-navigation card script
//  drags a selection across a field's lines, then goes to the chosen card
//  or background by the variable `it`.
//

import Foundation
import Testing
@testable import HyperTalk

@Test func goBackgroundByVariable() async throws {
    // `go bg it` — the first card of that background. The wall: `go` had no
    // background destination, so `it` after `bg` failed to parse.
    let host = MockHost(fields: [:])
    try await run("""
    on mouseUp
      put "Index" into it
      go bg it
    end mouseUp
    """, host: host)
    #expect(host.destinations == [.inBackground(.first, background: "Index")])
}

@Test func goBackgroundInsideSingleLineIf() async throws {
    // The Power Tools shape, verbatim: existence test, then a single-line
    // if/else choosing between a background and a card destination.
    let host = MockHost(fields: [:])
    try await run("""
    on mouseUp
      put "Sorting" into it
      if there is not a cd it then go bg it
      else go cd it
    end mouseUp
    """, host: host)
    #expect(host.destinations == [.inBackground(.first, background: "Sorting")])
}

@Test func bareNumberOfCharsInParenthesizedChunk() async throws {
    // `number of chars in (…)` without the leading `the` — Power Tools'
    // currentLine handler counts a line's characters this way.
    let host = MockHost(fields: ["src": "one\ntwelve chars\nthree"])
    try await run("""
    on mouseUp
      put (number of chars in (line 2 of field "src")) + 1 into field "src"
    end mouseUp
    """, host: host)
    #expect(host.fields["src"] == "13")
}

@Test func powerToolsCardScriptParses() async throws {
    // The full card script (goCard/currentLine/openCard), verbatim walls and
    // all: select with computed chunk ranges, `the mouse is up`, `is within
    // the rect of target`, `the value of the selectedLine`, `go bg it`.
    let script = """
    on goCard
      currentLine
      put the ticks into theTicks
      repeat until the mouse is up
        if the mouseloc is within the rect of target then
          currentLine
          put the ticks into theTicks
        else select empty
      end repeat
      if (the ticks - theTicks) < 10 then
        get the value of the selectedLine
        if it is empty then exit goCard
        visual effect iris open
        if there is not a cd it then go bg it
        else go cd it
      end if
      select empty
    end goCard

    on currentLine
      put ((the mouseV - top of target) - 4) ¬
      div (textHeight of target) + 1 into theLine
      select char 1 to ((number of chars in (line theLine of target)) + 1)¬
      of line theLine to (theLine + 1) of target
    end currentLine

    on openCard
      sn
    end openCard
    """
    _ = try Parser.parse(script)
}
