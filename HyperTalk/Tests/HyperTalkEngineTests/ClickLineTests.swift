//
//  ClickLineTests.swift
//  HyperTalkEngine
//
//  The web player's field clicks carry line/word info; scripts navigate by
//  them — the Power Tools list-field idiom, end to end.
//

import Foundation
import Testing
@testable import HyperTalkEngine

/// A locked three-line list field whose script reports the click, plus
/// destination cards named for the lines.
private let listStackJSON = """
{
  "formatVersion": 1,
  "id": "00000000-0000-0000-0000-0000000000EE",
  "name": "List",
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
          "script": "on mouseUp\\nput word 2 of the clickLine && the value of the clickLine && the clickText into message\\ngo to card (the value of the clickLine)\\nend mouseUp",
          "field": { "format": { "align": "left", "fontDesign": "standard", "isBold": false,
                                  "isItalic": false, "isUnderline": false, "size": 17 },
                     "isMultiline": true, "kind": "plain", "lockText": true, "placeholder": "",
                     "showLines": false, "style": "rectangle", "text": "Alpha\\nBeta\\nGamma", "wideMargins": false }
        }
      ]
    },
    {
      "id": "00000000-0000-0000-0000-000000000011", "name": "Beta",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 11, "parts": [], "script": ""
    }
  ]
}
""".data(using: .utf8)!

@Test
func fieldClickNavigatesByClickLine() async throws {
    let engine = try StackEngine(stackJSON: listStackJSON)
    // The page reports a click on line 2 ("Beta"), word "Beta".
    let effects = try await engine.dispatchMouseUp(partScriptID: 20, clickLine: 2, clickText: "Beta")
    #expect(effects.contains(.message("2 Beta Beta")))
    // …and the script's `go to card (the value of the clickLine)` landed on Beta.
    #expect(engine.currentCardState().cardName == "Beta")
}
