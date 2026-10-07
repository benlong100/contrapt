//
//  MarkedCardTests.swift
//  HyperTalkEngine
//
//  `marked card N` — the Nth card whose `marked` property is true, in stack
//  order — as a navigation target, a card object, a field scope, and a count.
//  Background Art's renumber loop: `put X into bg field "Card Num" of marked
//  card CardCount`, `repeat with CardCount = 1 to the number of marked cards`.
//

import Foundation
import Testing
@testable import HyperTalkEngine

/// Three cards; "Alpha" (card 1) and "Gamma" (card 3) are marked, "Beta"
/// (card 2) is not. Each card has a card field "Note".
private let markedJSON = """
{
  "formatVersion": 1, "id": "00000000-0000-0000-0000-0000000000BB",
  "name": "Marked", "cardSize": { "width": 512, "height": 342 }, "script": "", "nextID": 100,
  "backgrounds": [ { "id": "00000000-0000-0000-0000-000000000001", "name": "BG", "script": "", "scriptID": 1, "parts": [] } ],
  "cards": [
    {
      "id": "00000000-0000-0000-0000-000000000010", "name": "Alpha", "isMarked": true,
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 10, "script": "",
      "parts": [ { "id": "00000000-0000-0000-0000-000000000020", "name": "Note", "scriptID": 20,
        "visible": true, "script": "", "type": "field", "frame": { "x": 10, "y": 10, "width": 100, "height": 30 },
        "field": { "format": { "align": "left", "fontDesign": "standard", "isBold": false, "isItalic": false, "isUnderline": false, "size": 12 },
          "isMultiline": true, "kind": "plain", "lockText": false, "placeholder": "", "showLines": false, "style": "transparent", "text": "first", "wideMargins": false } } ]
    },
    {
      "id": "00000000-0000-0000-0000-000000000011", "name": "Beta", "isMarked": false,
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 11, "script": "", "parts": []
    },
    {
      "id": "00000000-0000-0000-0000-000000000012", "name": "Gamma", "isMarked": true,
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 12, "script": "",
      "parts": [ { "id": "00000000-0000-0000-0000-000000000022", "name": "Note", "scriptID": 22,
        "visible": true, "script": "", "type": "field", "frame": { "x": 10, "y": 10, "width": 100, "height": 30 },
        "field": { "format": { "align": "left", "fontDesign": "standard", "isBold": false, "isItalic": false, "isUnderline": false, "size": 12 },
          "isMultiline": true, "kind": "plain", "lockText": false, "placeholder": "", "showLines": false, "style": "transparent", "text": "third", "wideMargins": false } } ]
    }
  ]
}
""".data(using: .utf8)!

@Test func numberOfMarkedCards() async throws {
    let engine = try StackEngine(stackJSON: markedJSON)
    #expect(try await engine.runMessage("the number of marked cards") == "2")
}

@Test func markedCardAsObjectPicksNthMarked() async throws {
    let engine = try StackEngine(stackJSON: markedJSON)
    // marked card 1 = Alpha (card 1), marked card 2 = Gamma (card 3).
    #expect(try await engine.runMessage("the short name of marked card 1") == "Alpha")
    #expect(try await engine.runMessage("the short name of marked card 2") == "Gamma")
    #expect(try await engine.runMessage("the number of marked card 2") == "3")
}

@Test func fieldScopedToMarkedCard() async throws {
    let engine = try StackEngine(stackJSON: markedJSON)
    // Background Art's idiom: a field read/written on `marked card N`.
    #expect(try await engine.runMessage("the text of card field \"Note\" of marked card 2") == "third")
}

@Test func goToMarkedCard() async throws {
    let engine = try StackEngine(stackJSON: markedJSON)
    _ = try await engine.runMessage("go marked card 2")
    // Gamma is card index 2.
    #expect(engine.drainEffects().contains(where: { if case .navigate(let i, _) = $0 { return i == 2 }; return false }))
}
