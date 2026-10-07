//
//  ScopedCardObjectTests.swift
//  HyperTalkEngine
//
//  End-to-end for background-scoped card OBJECTS against a real multi-background
//  stack — `the number of card "X" of bkgnd "Y"`, which picks the card named
//  "X" that lives on background "Y" (not the first "X" in stack order). This is
//  the object-model rework: card objects now carry a GoDestination and resolve
//  with the same logic as `go cd X of bkgnd "Y"`.
//

import Foundation
import Testing
@testable import HyperTalkEngine

/// Two backgrounds, with a card named "Shared" on EACH: "Shared" is card 2
/// (background "First") and card 3 (background "Second"). Unscoped,
/// `card "Shared"` finds card 2; scoped to "Second" it finds card 3.
private let dupNameJSON = """
{
  "formatVersion": 1,
  "id": "00000000-0000-0000-0000-0000000000DD",
  "name": "Scoped",
  "cardSize": { "width": 512, "height": 342 },
  "script": "", "nextID": 100,
  "backgrounds": [
    { "id": "00000000-0000-0000-0000-000000000001", "name": "First", "script": "", "scriptID": 1, "parts": [] },
    { "id": "00000000-0000-0000-0000-000000000002", "name": "Second", "script": "", "scriptID": 2, "parts": [] }
  ],
  "cards": [
    {
      "id": "00000000-0000-0000-0000-000000000010", "name": "Alpha",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 10, "parts": [],
      "script": "on report\\nput the number of card \\"Shared\\" of bkgnd \\"Second\\" & \\",\\" & the number of card \\"Shared\\" & \\",\\" & the short name of card 1 of bg \\"Second\\" into message\\nend report"
    },
    {
      "id": "00000000-0000-0000-0000-000000000011", "name": "Shared",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 11, "parts": [], "script": ""
    },
    {
      "id": "00000000-0000-0000-0000-000000000012", "name": "Shared",
      "backgroundID": "00000000-0000-0000-0000-000000000002", "scriptID": 12, "parts": [], "script": ""
    }
  ]
}
""".data(using: .utf8)!

@Test
func backgroundScopedCardNumberPicksTheRightCard() async throws {
    let engine = try StackEngine(stackJSON: dupNameJSON)
    _ = try await engine.runMessage("report")
    let effects = engine.drainEffects()
    // card "Shared" of bg "Second" = card 3; unscoped card "Shared" = card 2;
    // card 1 of bg "Second" is the only Second card, named "Shared".
    #expect(effects.contains(.message("3,2,Shared")))
}

@Test
func backgroundScopedCardThatDoesNotExistErrors() async throws {
    let engine = try StackEngine(stackJSON: dupNameJSON)
    // "Alpha" lives on "First", not "Second" — scoping to "Second" finds nothing.
    let json = String(data: dupNameJSON, encoding: .utf8)!
        .replacingOccurrences(of: "card \\\"Shared\\\" of bkgnd \\\"Second\\\"",
                              with: "card \\\"Alpha\\\" of bkgnd \\\"Second\\\"")
    let engine2 = try StackEngine(stackJSON: json.data(using: .utf8)!)
    _ = try? await engine2.runMessage("report")
    // The handler fails on the bad reference; nothing is put to the message box.
    #expect(!engine2.drainEffects().contains(where: { if case .message = $0 { return true }; return false }))
    _ = engine
}
