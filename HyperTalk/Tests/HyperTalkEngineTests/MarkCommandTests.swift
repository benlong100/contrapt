//
//  MarkCommandTests.swift
//  HyperTalkEngine
//
//  `mark`/`unmark` write commands against a real stack: `mark card N`, `mark
//  all cards`, `unmark all cards`, and `mark cards where <condition>` (the
//  condition evaluated per card). Notebook's note-navigation idiom:
//    unmark all cards
//    mark cards where field "note name" = …
//    go next marked card
//

import Foundation
import Testing
@testable import HyperTalkEngine

/// Three cards, each with a card field "note name" = "A", "B", "B".
private let notesJSON = """
{
  "formatVersion": 1, "id": "00000000-0000-0000-0000-0000000000MK",
  "name": "Notes", "cardSize": { "width": 512, "height": 342 }, "script": "", "nextID": 100,
  "backgrounds": [ { "id": "00000000-0000-0000-0000-000000000001", "name": "BG", "script": "", "scriptID": 1, "parts": [] } ],
  "cards": [
    \(noteCard(id: "10", name: "One", note: "A")),
    \(noteCard(id: "11", name: "Two", note: "B")),
    \(noteCard(id: "12", name: "Three", note: "B"))
  ]
}
"""

private func noteCard(id: String, name: String, note: String) -> String {
    """
    {
      "id": "00000000-0000-0000-0000-0000000000\(id)", "name": "\(name)",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": \(id), "script": "",
      "parts": [ { "id": "00000000-0000-0000-0000-0000000001\(id)", "name": "note name", "scriptID": 1\(id),
        "visible": true, "script": "", "type": "field", "frame": { "x": 10, "y": 10, "width": 100, "height": 20 },
        "field": { "format": { "align": "left", "fontDesign": "standard", "isBold": false, "isItalic": false, "isUnderline": false, "size": 12 },
          "isMultiline": false, "kind": "plain", "lockText": false, "placeholder": "", "showLines": false, "style": "transparent", "text": "\(note)", "wideMargins": false } } ]
    }
    """
}

private func engine() throws -> StackEngine { try StackEngine(stackJSON: Data(notesJSON.utf8)) }

@Test func markCardsWhereCondition() async throws {
    let e = try engine()
    _ = try await e.runMessage("mark cards where field \"note name\" = \"B\"")
    #expect(try await e.runMessage("the number of marked cards") == "2")
    // marked card 1 is the first "B" — card "Two"; go next marked from card 1.
    #expect(try await e.runMessage("the short name of marked card 1") == "Two")
}

@Test func unmarkAllThenMarkWhere() async throws {
    let e = try engine()
    _ = try await e.runMessage("mark all cards")
    #expect(try await e.runMessage("the number of marked cards") == "3")
    _ = try await e.runMessage("unmark all cards")
    #expect(try await e.runMessage("the number of marked cards") == "0")
    _ = try await e.runMessage("mark cards where field \"note name\" = \"A\"")
    #expect(try await e.runMessage("the number of marked cards") == "1")
}

@Test func markSingleCardByNumber() async throws {
    let e = try engine()
    _ = try await e.runMessage("mark card 3")
    #expect(try await e.runMessage("the number of marked cards") == "1")
    #expect(try await e.runMessage("the short name of marked card 1") == "Three")
    _ = try await e.runMessage("unmark card 3")
    #expect(try await e.runMessage("the number of marked cards") == "0")
}

@Test func markThisCard() async throws {
    let e = try engine()
    // Current card is card 1 ("One").
    _ = try await e.runMessage("mark this card")
    #expect(try await e.runMessage("the number of marked cards") == "1")
    #expect(try await e.runMessage("the short name of marked card 1") == "One")
}
