//
//  ParseGapsBatch3Tests.swift
//  HyperTalk
//
//  Regression tests for the third batch of corpus parse-gap fixes (2026-10-05):
//  bare-container `sort`, `number of … in this stack`, `[card|bg] parts`,
//  menuItem read as a value/object (with a leading ordinal), `select text of
//  the foundField`, `show marked cards`, `put … into last menuItem`, and
//  `of bg id N` scopes. These come from Apple's bundled dev stacks (Power
//  Tools, New Features, Art Bits, Audio Help, Background Art, Readymade*).
//

import Foundation
import Testing
@testable import HyperTalk

// MARK: - sort <container> without `by`

@Test func sortBareVariableContainer() async throws {
    // `sort it` / `sort list` — sort a variable's lines in place, no `by`.
    let host = try await run("""
    on mouseUp
      put "cherry" & return & "apple" & return & "banana" into list
      sort list
      put list into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "apple\nbanana\ncherry")
}

@Test func sortBareContainerDescendingNumeric() async throws {
    // `sort dataList descending numeric` — direction and style, still no `by`.
    let host = try await run("""
    on mouseUp
      put "3" & return & "20" & return & "1" into dataList
      sort dataList descending numeric
      put dataList into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "20\n3\n1")
}

// MARK: - number of … in this stack / [card|bg] parts

@Test func numberOfCardsInThisStack() async throws {
    let host = MockHost(fields: ["out": ""])
    host.cardCount = 7
    try await run("""
    on mouseUp
      put the number of cds in this stack into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "7")
}

@Test func numberOfBackgroundParts() async throws {
    // `the number of background parts` = buttons + fields of that layer.
    let host = MockHost(fields: ["a": "", "b": ""])
    host.buttonCount = 3
    try await run("""
    on mouseUp
      put the number of background parts into field "a"
    end mouseUp
    """, host: host)
    #expect(host.fields["a"] == "5") // 2 fields + 3 buttons
}

// MARK: - menuItem as a value / object (menus aren't modeled → empty)

@Test func menuItemReadsEmpty() async throws {
    // `last menuItem of menu 3` and `name of last menuItem of menu "X"` both
    // read empty, so the guarded branch simply doesn't fire.
    let host = try await run("""
    on mouseUp
      if last menuItem of menu 3 is "-" then put "dash" into field "out"
      get name of last menuItem of menu "Art Bits"
      if it is "Show Palette" then put "shown" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": "untouched"]))
    #expect(host.fields["out"] == "untouched")
}

@Test func putIntoLastMenuItemIsIgnored() async throws {
    // `put … into last menuItem of menu 3 with menuMsg …` — a menu populate,
    // accepted and ignored (the beep still runs, proving the line parsed).
    let host = try await run("""
    on mouseUp
      put "Hide Notes" into last menuItem of menu 3 with menuMsg APHideNotes
      beep
    end mouseUp
    """)
    #expect(host.beeps == 1)
}

// MARK: - select text of the foundField

@Test func selectTextOfFoundField() async throws {
    // `the foundField` yields a field descriptor; select its whole text.
    let host = MockHost(fields: ["Notes": "hello world"])
    host.foundValues[.field] = "field \"Notes\""
    try await run("""
    on mouseUp
      select text of the foundField
    end mouseUp
    """, host: host)
    #expect(host.selections.count == 1)
    #expect(host.selections.first?.start == 0)
    #expect(host.selections.first?.end == 11)
}

// MARK: - show marked cards

@Test func showMarkedCardsIsIgnored() async throws {
    let host = try await run("""
    on mouseUp
      show marked cards
      beep
    end mouseUp
    """)
    #expect(host.beeps == 1)
}

// MARK: - go to <unquoted multi-word stack name>

@Test func goToUnquotedMultiWordStackName() async throws {
    // `go to File Index` / `go to Clip Art` — Home's unquoted stack names.
    let host = try await run("""
    on mouseUp
      go to File Index
    end mouseUp
    """)
    #expect(host.destinations.count == 1)
    if case .stack(let name, _) = host.destinations.first {
        // Identifiers are case-folded by the tokenizer; stack-name resolution
        // is case-insensitive (as in HyperCard), so this still finds the stack.
        #expect(name == "file index")
    } else {
        Issue.record("Expected a stack destination, got \(String(describing: host.destinations.first))")
    }
}

@Test func goToSingleBareWordStaysAVariable() async throws {
    // A single bare word is a variable holding the destination, not a literal.
    let host = try await run("""
    on mouseUp
      put "Quotations" into whichStack
      go to whichStack
    end mouseUp
    """)
    #expect(host.destinations.count == 1)
}

// MARK: - ask file / ask password

@Test func askFileWithDefaultDegradesToAsk() async throws {
    // `ask file "prompt" with <default>` — no file dialog, so it parses as a
    // plain text ask (the prompt reaches the host; `it` is the host's reply).
    let host = MockHost(fields: ["out": ""])
    host.askResponse = "MyStack"
    try await run("""
    on mouseUp
      ask file "Name for your new stack?" with "Untitled"
      put it into field "out"
    end mouseUp
    """, host: host)
    #expect(host.askPrompts == ["Name for your new stack?"])
    #expect(host.fields["out"] == "MyStack")
}

// MARK: - start/stop using stack

@Test func startStopUsingStackAreIgnored() async throws {
    // `start using stack "X"` / `stop using stack "X"` — auxiliary-stack
    // message hierarchy, not modeled; accepted and ignored.
    let host = try await run("""
    on mouseUp
      start using stack "Audio Palette"
      beep
      stop using stack "Audio Palette"
    end mouseUp
    """)
    #expect(host.beeps == 1)
}

// MARK: - go card N of bg id N

@Test func goCardOfBackgroundByID() async throws {
    // `go card count of bg id 9036` parses (id matched as a name, best effort).
    let host = try await run("""
    on mouseUp
      put 2 into count
      go card count of bg id 9036
    end mouseUp
    """)
    #expect(host.destinations.count == 1)
}
