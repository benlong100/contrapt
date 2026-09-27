//
//  HighlightColorTests.swift
//  HyperTalkEngine
//
//  The per-card highlightColor property is settable and readable via script.
//

import Foundation
import Testing
@testable import HyperTalkEngine

private let highlightJSON = """
{
  "formatVersion": 1, "id": "00000000-0000-0000-0000-0000000000EE",
  "name": "Highlight", "cardSize": { "width": 512, "height": 342 }, "script": "", "nextID": 100,
  "backgrounds": [ { "id": "00000000-0000-0000-0000-000000000001", "name": "BG", "script": "", "scriptID": 1, "parts": [] } ],
  "cards": [
    {
      "id": "00000000-0000-0000-0000-000000000010", "name": "Card 1",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 10,
      "parts": [
        {
          "id": "00000000-0000-0000-0000-000000000021", "name": "Set", "scriptID": 21,
          "frame": { "x": 10, "y": 10, "width": 80, "height": 30 },
          "script": "on mouseUp\\nset the highlightColor of this card to \\"#FF3B30\\"\\nput the highlightColor of this card\\nend mouseUp",
          "type": "button", "button": { "title": "Set" }
        }
      ]
    }
  ]
}
""".data(using: .utf8)!

@Test func highlightColorSetsAndReads() async throws {
    let engine = try StackEngine(stackJSON: highlightJSON)
    let effects = try await engine.dispatchMouseUp(partScriptID: 21)
    #expect(effects.contains(.message("#FF3B30")))
}
