//
//  NewStacksBatchDTests.swift
//  HyperTalkEngine
//
//  Closing batch from the Oct-5 stacks: `the number of cds of bg <variable>`
//  (Power Tools, a runtime-named background), `the showPict of card` (Audio
//  Help, always-shown paint layer), and `any item/word/line of X` — a random
//  chunk — behind HyperBattleship's `play (any item of "…")(any item of "…")`.
//

import Foundation
import Testing
@testable import HyperTalkEngine

/// Two backgrounds: "Alpha" (scriptID 1) with 2 cards, "Beta" (scriptID 2)
/// with 1 card.
private let twoBGJSON = """
{
  "formatVersion": 1, "id": "00000000-0000-0000-0000-0000000000BD",
  "name": "TwoBG", "cardSize": { "width": 512, "height": 342 }, "script": "", "nextID": 100,
  "backgrounds": [
    { "id": "00000000-0000-0000-0000-000000000001", "name": "Alpha", "script": "", "scriptID": 1, "parts": [] },
    { "id": "00000000-0000-0000-0000-000000000002", "name": "Beta", "script": "", "scriptID": 2, "parts": [] }
  ],
  "cards": [
    { "id": "00000000-0000-0000-0000-000000000010", "name": "A1", "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 10, "parts": [],
      "script": "on probe\\nput \\"Alpha\\" into bgNum\\nput the number of cds of bg bgNum into r1\\nput 2 into bgNum\\nput the number of cds of bg bgNum into r2\\nput r1 & \\",\\" & r2 into message\\nend probe" },
    { "id": "00000000-0000-0000-0000-000000000011", "name": "A2", "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 11, "script": "", "parts": [] },
    { "id": "00000000-0000-0000-0000-000000000012", "name": "B1", "backgroundID": "00000000-0000-0000-0000-000000000002", "scriptID": 12, "script": "", "parts": [] }
  ]
}
""".data(using: .utf8)!

@Test func numberOfCardsOfBackgroundByVariable() async throws {
    // `the number of cds of bg bgNum` — the background is named at run time, by
    // name ("Alpha" → 2 cards) and by number (2 → the "Beta" bg → 1 card).
    let e = try StackEngine(stackJSON: twoBGJSON)
    _ = try await e.runMessage("probe")
    #expect(e.drainEffects().contains(.message("2,1")))
}

@Test func showPictOfCardReadsTrueAndSetIsNoOp() async throws {
    let e = try StackEngine(stackJSON: twoBGJSON)
    #expect(try await e.runMessage("the showPict of card 1") == "true")
    _ = try await e.runMessage("set the showPict of this card to false") // no-op, no throw
    #expect(try await e.runMessage("the showPict of this card") == "true")
}

@Test func anyChunkPicksAMember() async throws {
    let e = try StackEngine(stackJSON: twoBGJSON)
    // A single-member list makes the random pick deterministic.
    #expect(try await e.runMessage("any item of \"solo\"") == "solo")
    #expect(try await e.runMessage("any word of \"only\"") == "only")
    // From a multi-item list, the pick is always one of the members.
    let picked = try await e.runMessage("any item of \"a,b,c\"")
    #expect(["a", "b", "c"].contains(picked ?? ""))
}

@Test func playWithParenthesizedAnyItemArgs() async throws {
    // HyperBattleship: `play (any item of "Sunk 1,…")(any item of "rt,…")`.
    let e = try StackEngine(stackJSON: twoBGJSON)
    // Parses and runs without throwing (the sound name resolves to a voice).
    _ = try await e.runMessage("play (any item of \"Sunk 1,Sunk 2\") (any item of \"rt,g2s\")")
}
