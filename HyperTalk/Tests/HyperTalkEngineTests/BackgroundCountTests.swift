//
//  BackgroundCountTests.swift
//  HyperTalkEngine
//
//  End-to-end per-background card counts against a real two-background
//  stack — the Home pattern: a section loops over `the number of cds in
//  this bg`, not the whole stack.
//

import Foundation
import Testing
@testable import HyperTalkEngine

/// Three cards: two on background "Guide" (scriptID 1), one on "Extras"
/// (scriptID 2). The first card reports its background's card count.
private let twoBackgroundJSON = """
{
  "formatVersion": 1,
  "id": "00000000-0000-0000-0000-0000000000CC",
  "name": "Sections",
  "cardSize": { "width": 512, "height": 342 },
  "script": "",
  "nextID": 100,
  "backgrounds": [
    { "id": "00000000-0000-0000-0000-000000000001", "name": "Guide", "script": "", "scriptID": 1, "parts": [] },
    { "id": "00000000-0000-0000-0000-000000000002", "name": "Extras", "script": "", "scriptID": 2, "parts": [] }
  ],
  "cards": [
    {
      "id": "00000000-0000-0000-0000-000000000010", "name": "G1",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 10, "parts": [],
      "script": "on report\\nput the number of cds in this bg && the number of cards of bg \\"Extras\\" && the number of cards into message\\nend report"
    },
    {
      "id": "00000000-0000-0000-0000-000000000011", "name": "G2",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 11, "parts": [], "script": ""
    },
    {
      "id": "00000000-0000-0000-0000-000000000012", "name": "X1",
      "backgroundID": "00000000-0000-0000-0000-000000000002", "scriptID": 12, "parts": [], "script": ""
    }
  ]
}
""".data(using: .utf8)!

@Test
func perBackgroundCardCountsAgainstARealStack() async throws {
    let engine = try StackEngine(stackJSON: twoBackgroundJSON)
    // On card G1 (background "Guide", 2 cards): this bg = 2, "Extras" = 1,
    // whole stack = 3.
    _ = try await engine.runMessage("report")
    let effects = engine.drainEffects()
    #expect(effects.contains(.message("2 1 3")))
}
