//
//  GlobalsAcrossCardsTests.swift
//  HyperTalkEngine
//
//  Reproduces the Home-stack pattern: one card sets a global in openCard, a
//  later card reads it in openCard and puts it in the message box.
//

import Foundation
import Testing
@testable import HyperTalkEngine

private let twoCardGlobalsJSON = """
{
  "formatVersion": 1,
  "id": "00000000-0000-0000-0000-0000000000BB",
  "name": "Globals",
  "cardSize": { "width": 512, "height": 342 },
  "script": "",
  "nextID": 100,
  "backgrounds": [
    { "id": "00000000-0000-0000-0000-000000000001", "name": "BG", "script": "", "scriptID": 1, "parts": [] }
  ],
  "cards": [
    {
      "id": "00000000-0000-0000-0000-000000000010", "name": "First",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 10, "parts": [],
      "script": "on openCard\\nglobal lastCard\\nput \\"What is Contrapt?\\" into lastCard\\nend openCard"
    },
    {
      "id": "00000000-0000-0000-0000-000000000011", "name": "Second",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 11, "parts": [],
      "script": "on openCard\\nglobal lastCard\\nput lastCard into message\\nend openCard"
    }
  ]
}
""".data(using: .utf8)!

@Test
func globalSetInOneCardOpenCardIsReadByAnother() async throws {
    let engine = try StackEngine(stackJSON: twoCardGlobalsJSON)
    // Land on the first card (its openCard sets the global)…
    _ = try await engine.openCard(index: 0)
    // …then the second card's openCard reads it into the message box.
    let effects = try await engine.openCard(index: 1)
    #expect(effects.contains(.message("What is Contrapt?")))
}
