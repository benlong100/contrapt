//
//  MakeCardTests.swift
//  HyperTalkEngine
//
//  `make a card [using background <ref>]` and the data→cards merge
//  `make a card for each element of <array>` (Contrapt web gathering):
//  cards append at the end without navigating; each element's keys fill
//  same-named fields; `it` reports the card number / the count.
//

import Foundation
import Testing
@testable import HyperTalkEngine

/// Two backgrounds: "Menu" (empty) and "Entry" with fields "Title" and
/// "Notes". One card on each, current card on the Menu background.
private let mergeJSON = """
{
  "formatVersion": 1,
  "id": "00000000-0000-0000-0000-0000000000CD",
  "name": "Merge",
  "cardSize": { "width": 512, "height": 342 },
  "script": "",
  "nextID": 100,
  "backgrounds": [
    { "id": "00000000-0000-0000-0000-000000000001", "name": "Menu", "script": "", "scriptID": 1, "parts": [] },
    { "id": "00000000-0000-0000-0000-000000000002", "name": "Entry", "script": "", "scriptID": 2,
      "parts": [
        {
          "id": "00000000-0000-0000-0000-000000000021", "name": "Title", "scriptID": 21,
          "visible": true, "type": "field",
          "frame": { "x": 20, "y": 20, "width": 300, "height": 30 }, "script": "",
          "field": { "format": { "align": "left", "fontDesign": "standard", "isBold": false,
                                  "isItalic": false, "isUnderline": false, "size": 17 },
                     "isMultiline": false, "kind": "plain", "lockText": false, "placeholder": "",
                     "showLines": false, "style": "rectangle", "text": "", "wideMargins": false }
        },
        {
          "id": "00000000-0000-0000-0000-000000000022", "name": "Notes", "scriptID": 22,
          "visible": true, "type": "field",
          "frame": { "x": 20, "y": 60, "width": 300, "height": 120 }, "script": "",
          "field": { "format": { "align": "left", "fontDesign": "standard", "isBold": false,
                                  "isItalic": false, "isUnderline": false, "size": 17 },
                     "isMultiline": true, "kind": "plain", "lockText": false, "placeholder": "",
                     "showLines": false, "style": "rectangle", "text": "", "wideMargins": false }
        }
      ] }
  ],
  "cards": [
    { "id": "00000000-0000-0000-0000-000000000010", "name": "Home",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 10, "script": "", "parts": [] },
    { "id": "00000000-0000-0000-0000-000000000011", "name": "Sample",
      "backgroundID": "00000000-0000-0000-0000-000000000002", "scriptID": 11, "script": "", "parts": [] }
  ]
}
""".data(using: .utf8)!

@Test func makeACardAppendsWithoutNavigating() async throws {
    let engine = try StackEngine(stackJSON: mergeJSON)
    _ = try await engine.runMessage("make a card")
    #expect(engine.cardCount == 3)
    // Still on the first card; the new card shares its background.
    #expect(try await engine.runMessage("the name of this card") == "Home")
    #expect(try await engine.runMessage("the number of cards of background \"Menu\"") == "2")
}

@Test func makeACardReportsItsNumberInIt() async throws {
    let engine = try StackEngine(stackJSON: mergeJSON)
    _ = try await engine.runMessage("make a card\nput it into msg")
    #expect(engine.drainEffects().contains(.message("3")))
}

@Test func makeACardUsingBackgroundByName() async throws {
    let engine = try StackEngine(stackJSON: mergeJSON)
    _ = try await engine.runMessage("make a card using background \"Entry\"")
    #expect(try await engine.runMessage("the number of cards of background \"Entry\"") == "2")
}

@Test func makeACardUsingMissingBackgroundErrors() async throws {
    let engine = try StackEngine(stackJSON: mergeJSON)
    await #expect(throws: (any Error).self) {
        _ = try await engine.runMessage("make a card using background \"Nowhere\"")
    }
    #expect(engine.cardCount == 2)
}

@Test func makeACardForEachElementFillsFieldsByKey() async throws {
    let engine = try StackEngine(stackJSON: mergeJSON)
    let script = """
    put "First" into stories[1]["Title"]
    put "one note" into stories[1]["Notes"]
    put "Second" into stories[2]["Title"]
    put "ignored" into stories[2]["Author"]
    make a card for each element of stories using background "Entry"
    put it into msg
    """
    _ = try await engine.runMessage(script)
    #expect(engine.drainEffects().contains(.message("2")))
    #expect(engine.cardCount == 4)
    // Background fields carry per-card content: each new card has its own.
    #expect(try await engine.runMessage("field \"Title\" of card 3") == "First")
    #expect(try await engine.runMessage("field \"Notes\" of card 3") == "one note")
    #expect(try await engine.runMessage("field \"Title\" of card 4") == "Second")
    // The unmatched "Author" key was ignored, and Notes stayed empty.
    #expect(try await engine.runMessage("field \"Notes\" of card 4") == "")
}

@Test func makeACardForEachScalarElementMakesEmptyCards() async throws {
    let engine = try StackEngine(stackJSON: mergeJSON)
    let script = """
    put "alpha" into things[1]
    put "beta" into things[2]
    make a card for each element of things using background "Entry"
    """
    _ = try await engine.runMessage(script)
    #expect(engine.cardCount == 4)
    #expect(try await engine.runMessage("field \"Title\" of card 3") == "")
}

@Test func makeACardForEachNeedsAnArray() async throws {
    let engine = try StackEngine(stackJSON: mergeJSON)
    await #expect(throws: (any Error).self) {
        _ = try await engine.runMessage("make a card for each element of \"plain text\"")
    }
}

@Test func mergeIntoBlankBackgroundScaffoldsItsFields() async throws {
    // The "Menu" background has no fields: the merge creates one per key
    // (named by the key, "text" getting the tall multiline slot) and fills
    // them — a blank template never means blank cards.
    let engine = try StackEngine(stackJSON: mergeJSON)
    _ = try await engine.runMessage("""
    put "Hello" into stories[1]["title"]
    put "the body" into stories[1]["text"]
    make a card for each element of stories using background "Menu"
    """)
    #expect(try await engine.runMessage("the number of background fields of background \"Menu\"") == "2")
    #expect(try await engine.runMessage("field \"title\" of card 3") == "Hello")
    #expect(try await engine.runMessage("field \"text\" of card 3") == "the body")
}

@Test func mergeIntoDesignedBackgroundAddsNoFields() async throws {
    // "Entry" already has Title/Notes: the design wins — unmatched keys are
    // ignored and no fields are added.
    let engine = try StackEngine(stackJSON: mergeJSON)
    _ = try await engine.runMessage("""
    put "Hello" into stories[1]["Title"]
    put "stray" into stories[1]["Author"]
    make a card for each element of stories using background "Entry"
    """)
    _ = try await engine.runMessage("go to card 3")
    #expect(try await engine.runMessage("the number of background fields") == "2")
    #expect(try await engine.runMessage("field \"Title\"") == "Hello")
}

@Test func gatherDemoFeedBecomesADeck() async throws {
    // The thesis demo end-to-end: fetch JSON from the web, make a card per
    // entry, fields filled by key name — a browsable deck in three lines.
    let feed = """
    [ {"Title": "HyperCard Returns", "Notes": "it opens the shoebox"},
      {"Title": "Stacks on the Web", "Notes": "the real engine in a page"} ]
    """
    let interaction = EngineInteraction(httpRequest: { _, _, _, _, _ in (feed, 200, [:], nil) })
    let engine = try StackEngine(stackJSON: mergeJSON, interaction: interaction)
    _ = try await engine.runMessage("""
    put JSONDecode(url "https://example.com/feed.json") into stories
    make a card for each element of stories using background "Entry"
    """)
    #expect(engine.cardCount == 4)
    #expect(try await engine.runMessage("field \"Title\" of card 3") == "HyperCard Returns")
    #expect(try await engine.runMessage("field \"Notes\" of card 4") == "the real engine in a page")
    // The page navigates by the LIVE count (scripts make/delete cards).
    #expect(engine.currentCardState().cardCount == 4)
}

@Test func putArrayIntoThisCardFillsItsFields() async throws {
    // `put <array> into this card` — the merge's fill for one card: keys
    // land in same-named fields, unmatched keys are ignored.
    let engine = try StackEngine(stackJSON: mergeJSON)
    _ = try await engine.runMessage("go to card 2")
    _ = try await engine.runMessage("""
    put "Fresh" into story["Title"]
    put "stray" into story["Author"]
    put story into this card
    """)
    #expect(try await engine.runMessage("field \"Title\"") == "Fresh")
    #expect(engine.cardCount == 2)
}

@Test func putArrayIntoAnotherCardByNumber() async throws {
    let engine = try StackEngine(stackJSON: mergeJSON)
    _ = try await engine.runMessage("""
    put "From afar" into story["Notes"]
    put story into card 2
    """)
    #expect(try await engine.runMessage("field \"Notes\" of card 2") == "From afar")
    // Still on card 1 — filling doesn't navigate.
    #expect(try await engine.runMessage("the name of this card") == "Home")
}

@Test func putNonArrayIntoCardErrors() async throws {
    let engine = try StackEngine(stackJSON: mergeJSON)
    await #expect(throws: (any Error).self) {
        _ = try await engine.runMessage("put \"plain text\" into this card")
    }
}

@Test func putIntoCardFieldStaysAFieldWrite() async throws {
    // The card target only claims a BARE card ref ending the line —
    // `put … into card field …` keeps its part meaning.
    let engine = try StackEngine(stackJSON: mergeJSON)
    _ = try await engine.runMessage("go to card 2")
    _ = try await engine.runMessage("put \"direct\" into field \"Notes\"")
    #expect(try await engine.runMessage("field \"Notes\"") == "direct")
}

private let makeHandlerJSON = """
{
  "formatVersion": 1,
  "id": "00000000-0000-0000-0000-0000000000CE",
  "name": "Maker",
  "cardSize": { "width": 512, "height": 342 },
  "script": "on make what\\nput what && \\"made\\" into msg\\nend make",
  "nextID": 100,
  "backgrounds": [
    { "id": "00000000-0000-0000-0000-000000000001", "name": "BG", "script": "", "scriptID": 1, "parts": [] }
  ],
  "cards": [
    { "id": "00000000-0000-0000-0000-000000000010", "name": "Home",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 10, "script": "", "parts": [] }
  ]
}
""".data(using: .utf8)!

@Test func customMakeHandlerStillWorks() async throws {
    // `make` only becomes a command before `[a] card(s)`; a stack's own
    // `make` handler keeps receiving every other form.
    let engine = try StackEngine(stackJSON: makeHandlerJSON)
    _ = try await engine.runMessage("make 7")
    #expect(engine.drainEffects().contains(.message("7 made")))
    #expect(engine.cardCount == 1)
}
