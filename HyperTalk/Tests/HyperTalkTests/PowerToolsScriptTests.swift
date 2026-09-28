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

@Test func dynamicCountEvaluatesComputedNoun() async throws {
    // `the number of (item i of list & "s")` — the countable noun is built
    // at run time ("cd btn" & "s" → "cd btns"). Super Grouper's object scan.
    let host = MockHost(fields: ["out": ""])
    host.buttonCount = 3
    try await run("""
    on mouseUp
      put "cd btn" into obj
      put the number of (obj & "s") into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "3")
}

@Test func propertyOfParenthesizedObject() async throws {
    // `visible of (object && i)` — the object descriptor is built inline.
    let host = MockHost(fields: ["out": ""])
    host.properties["button OK.visible"] = "true"
    try await run("""
    on mouseUp
      put "button" into obj
      if visible of (obj && quote & "OK" & quote) then put "seen" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "seen")
}

@Test func longIDReadsTheIdDescriptor() async throws {
    // `the long id of this cd` — the descriptor form, like the long name.
    let host = MockHost(fields: ["out": ""])
    host.properties["this card.longid"] = "card id 42"
    try await run("""
    on mouseUp
      put the long id of this cd into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "card id 42")
}

@Test func menuTextReadsEmptyAndMenuSetsAreNoOps() async throws {
    // A menu read as text is its item list in HyperCard; Contrapt has no
    // menus, so chunks of it are empty and menuItem property sets no-op.
    let host = MockHost(fields: ["out": "x"])
    try await run("""
    on mouseUp
      put line 4 to 6 of menu "InUse" into field "out"
      set enabled of menuItem 2 of menu "InUse" to true
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "")
}

@Test func markedCardCountIsZero() async throws {
    // Card marking isn't modeled — no cards are marked.
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      put the number of marked cds into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "0")
}

@Test func knownExternalCommandsNoOp() async throws {
    // `GeneralPalette centerBtnName,left,top` — an XCMD in the stack's
    // resource fork. The import records its name; calling it is a no-op
    // instead of "Can't understand 'generalpalette'".
    let host = MockHost(fields: ["out": ""])
    host.externalNames = ["generalpalette", "showlist"]
    try await run("""
    on mouseUp
      GeneralPalette "List of Tools",100,200
      get showList("a,b","pick",true,false,"OK,Cancel",0)
      put "ran to the end, it is [" & it & "]" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "ran to the end, it is []")
}

@Test func hyperCardShippedExternalsNoOp() async throws {
    // `palette "Navigator"` — an XCMD HyperCard itself shipped, so it's
    // never in a stack's fork; a small built-in list covers those.
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      palette "Navigator"
      put "ok" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "ok")
}

@Test func unknownCommandsStillError() async throws {
    // Only *recorded* externals no-op — a genuinely unknown name (a typo in
    // the user's own script) still surfaces as an error.
    let host = MockHost(fields: [:])
    await #expect(throws: ScriptError.self) {
        _ = try await run("""
        on mouseUp
          bogusCommandNobodyHas 1,2
        end mouseUp
        """, host: host)
    }
}

@Test func powerToolsStackScriptWallsParse() async throws {
    // Condensed from the Power Tools stack script: every construct that
    // walled, in its original shape.
    let script = """
    on stopUsing
      put number of menuItems in menu "InUse" into numMenuItems
      put line 4 to (numMenuItems - 2) of menu "InUse" into menuItems
    end stopUsing

    on startGrouping
      put the long id of this cd into WhereTheGroupIs
    end startGrouping

    on withinRect selectRect
      put "cd btn,cd fld,bg btn,bg fld" into list
      repeat with i = 1 to 4
        put item i of list into object
        put the number of (item i of list & "s") into numberOfObjects
        repeat with i = numberOfObjects down to 1
          if IntersectRect(rect of (object && i),selectRect) then
            if visible of (object && i)
            then put (object && "id") && (the id of (object && i))¬
            & "," after ObjectList
          end if
        end repeat
      end repeat
    end withinRect

    on doBackground
      put the number of marked cds into numMarked
    end doBackground
    """
    _ = try Parser.parse(script)
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
