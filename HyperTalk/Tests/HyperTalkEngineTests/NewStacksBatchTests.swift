//
//  NewStacksBatchTests.swift
//  HyperTalkEngine
//
//  Gaps surfaced by the Oct-5 batch of real stacks: `the random of N` (the
//  Manhole), `go next/previous marked card` (Notebook), and duplicate-handler
//  tolerance (Cultural Almanac ships two `closeCard` handlers).
//

import Foundation
import Testing
@testable import HyperTalkEngine

@Test func theRandomOfNParses() async throws {
    // `the random of N` and `random of N` both work (value in 1...N).
    let engine = try StackEngine(stackJSON: miniStackJSON)
    let v = try await engine.runMessage("the random of 1")
    #expect(v == "1")
    let v2 = try await engine.runMessage("random of 1")
    #expect(v2 == "1")
}

/// Two cards, both marked, to exercise `go next/previous marked card`.
private let markedNavJSON = """
{
  "formatVersion": 1, "id": "00000000-0000-0000-0000-0000000000CA",
  "name": "MarkedNav", "cardSize": { "width": 512, "height": 342 }, "script": "", "nextID": 100,
  "backgrounds": [ { "id": "00000000-0000-0000-0000-000000000001", "name": "BG", "script": "", "scriptID": 1, "parts": [] } ],
  "cards": [
    { "id": "00000000-0000-0000-0000-000000000010", "name": "One", "isMarked": true,
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 10, "script": "", "parts": [] },
    { "id": "00000000-0000-0000-0000-000000000011", "name": "Two", "isMarked": false,
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 11, "script": "", "parts": [] },
    { "id": "00000000-0000-0000-0000-000000000012", "name": "Three", "isMarked": true,
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 12, "script": "", "parts": [] }
  ]
}
""".data(using: .utf8)!

@Test func goNextMarkedCard() async throws {
    let engine = try StackEngine(stackJSON: markedNavJSON)
    // From card 1 (index 0), the next marked card is card 3 (index 2).
    _ = try await engine.runMessage("go next marked card")
    #expect(engine.drainEffects().contains(where: { if case .navigate(let i, _) = $0 { return i == 2 }; return false }))
}

@Test func goFirstAndLastMarkedCard() async throws {
    // The Library's `go first marked cd`. Marked cards are One (index 0) and
    // Three (index 2); first → 0, last → 2.
    let engine = try StackEngine(stackJSON: markedNavJSON)
    _ = try await engine.runMessage("go last marked card")
    #expect(engine.drainEffects().contains(where: { if case .navigate(let i, _) = $0 { return i == 2 }; return false }))
    _ = try await engine.runMessage("go first marked card")
    #expect(engine.drainEffects().contains(where: { if case .navigate(let i, _) = $0 { return i == 0 }; return false }))
}

/// A card button whose script defines `closeCard` TWICE — the first wins.
private let dupHandlerJSON = """
{
  "formatVersion": 1, "id": "00000000-0000-0000-0000-0000000000DH",
  "name": "Dup", "cardSize": { "width": 512, "height": 342 }, "script": "", "nextID": 100,
  "backgrounds": [ { "id": "00000000-0000-0000-0000-000000000001", "name": "BG", "script": "", "scriptID": 1, "parts": [] } ],
  "cards": [
    {
      "id": "00000000-0000-0000-0000-000000000010", "name": "Card 1",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 10, "parts": [],
      "script": "on report\\nput \\"first\\" into message\\nend report\\n\\non report\\nput \\"second\\" into message\\nend report"
    }
  ]
}
""".data(using: .utf8)!

@Test func duplicateHandlerUsesTheFirst() async throws {
    // A script with two `report` handlers parses (no error) and runs the first.
    let engine = try StackEngine(stackJSON: dupHandlerJSON)
    _ = try await engine.runMessage("report")
    #expect(engine.drainEffects().contains(.message("first")))
}

/// Minimal one-card stack for expression smoke tests.
private let miniStackJSON = """
{
  "formatVersion": 1, "id": "00000000-0000-0000-0000-0000000000MN",
  "name": "Mini", "cardSize": { "width": 512, "height": 342 }, "script": "", "nextID": 100,
  "backgrounds": [ { "id": "00000000-0000-0000-0000-000000000001", "name": "BG", "script": "", "scriptID": 1, "parts": [] } ],
  "cards": [ { "id": "00000000-0000-0000-0000-000000000010", "name": "Card 1",
    "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 10, "script": "", "parts": [] } ]
}
""".data(using: .utf8)!
