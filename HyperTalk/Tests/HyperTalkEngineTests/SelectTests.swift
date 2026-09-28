//
//  SelectTests.swift
//  HyperTalkEngine
//
//  `select` end to end in the web engine: the selection highlights in the
//  card state, the selected* readers serve descriptors, navigation clears.
//

import Foundation
import Testing
@testable import HyperTalkEngine

private let selectJSON = """
{
  "formatVersion": 1,
  "id": "00000000-0000-0000-0000-0000000000AC",
  "name": "Select",
  "cardSize": { "width": 512, "height": 342 },
  "script": "",
  "nextID": 100,
  "backgrounds": [
    { "id": "00000000-0000-0000-0000-000000000001", "name": "BG", "script": "", "scriptID": 1, "parts": [] }
  ],
  "cards": [
    {
      "id": "00000000-0000-0000-0000-000000000010", "name": "Index",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 10, "script": "",
      "parts": [
        {
          "id": "00000000-0000-0000-0000-000000000020", "name": "Topics", "scriptID": 20,
          "visible": true, "type": "field",
          "frame": { "x": 40, "y": 60, "width": 300, "height": 90 },
          "script": "on mouseUp\\nselect line 2 of field \\"Topics\\"\\nput the selectedLine & \\"|\\" & the selectedText & \\"|\\" & the selectedChunk into message\\nend mouseUp",
          "field": { "format": { "align": "left", "fontDesign": "standard", "isBold": false,
                                  "isItalic": false, "isUnderline": false, "size": 17 },
                     "isMultiline": true, "kind": "plain", "lockText": true, "placeholder": "",
                     "showLines": false, "style": "rectangle", "text": "Alpha\\nBeta\\nGamma", "wideMargins": false }
        }
      ]
    },
    {
      "id": "00000000-0000-0000-0000-000000000011", "name": "Two",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 11, "parts": [], "script": ""
    }
  ]
}
""".data(using: .utf8)!

@Test
func selectHighlightsReadsAndClearsOnNavigation() async throws {
    let engine = try StackEngine(stackJSON: selectJSON)
    let effects = try await engine.dispatchMouseUp(partScriptID: 20)
    #expect(effects.contains(.message("line 2 of card field id 20|Beta|char 7 to 10 of card field id 20")))

    // The selection rides the card state for the page to highlight.
    let field = engine.currentCardState().cardParts.first { $0.scriptID == 20 }
    #expect(field?.selStart == 6)
    #expect(field?.selEnd == 10)

    // Navigation clears it, as in HyperCard.
    _ = try await engine.openCard(index: 1)
    _ = try await engine.openCard(index: 0)
    let after = engine.currentCardState().cardParts.first { $0.scriptID == 20 }
    #expect(after?.selStart == nil)
    #expect(try await engine.runMessage("the selectedLine") == "")
}
