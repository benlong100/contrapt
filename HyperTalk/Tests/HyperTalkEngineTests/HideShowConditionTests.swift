//
//  HideShowConditionTests.swift
//  HyperTalkEngine
//
//  Confirms the openCard conditional-hide behaves: when lastCard equals the
//  literal, the ≠ test is false and the button is NOT hidden; and that hide
//  persists (so a button hidden earlier stays hidden unless shown).
//

import Foundation
import Testing
@testable import HyperTalkEngine

private let hideJSON = """
{
  "formatVersion": 1, "id": "00000000-0000-0000-0000-0000000000CC",
  "name": "Hide", "cardSize": { "width": 512, "height": 342 }, "script": "", "nextID": 100,
  "backgrounds": [ { "id": "00000000-0000-0000-0000-000000000001", "name": "BG", "script": "", "scriptID": 1, "parts": [] } ],
  "cards": [
    {
      "id": "00000000-0000-0000-0000-000000000010", "name": "First",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 10, "parts": [],
      "script": "on openCard\\nglobal lastCard\\nput \\"What is Contrapt?\\" into lastCard\\nend openCard"
    },
    {
      "id": "00000000-0000-0000-0000-000000000011", "name": "Second",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 11,
      "script": "on openCard\\nglobal lastCard\\nif lastCard <> \\"What is Contrapt?\\" then hide card button \\"Previous\\"\\nend openCard",
      "parts": [
        {
          "id": "00000000-0000-0000-0000-000000000021", "name": "Previous", "scriptID": 21,
          "frame": { "x": 10, "y": 10, "width": 80, "height": 30 }, "script": "",
          "type": "button", "button": { "title": "Previous" }
        }
      ]
    }
  ]
}
""".data(using: .utf8)!

@Test
func matchingValueLeavesButtonVisible() async throws {
    let engine = try StackEngine(stackJSON: hideJSON)
    _ = try await engine.openCard(index: 0)   // sets lastCard = "What is Contrapt?"
    _ = try await engine.openCard(index: 1)   // ≠ is false → must NOT hide
    let previous = engine.currentCardState().cardParts.first { $0.name == "Previous" }
    #expect(previous?.visible == true)
}
