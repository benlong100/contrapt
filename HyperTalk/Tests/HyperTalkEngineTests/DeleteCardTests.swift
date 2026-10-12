//
//  DeleteCardTests.swift
//  HyperTalkEngine
//
//  `delete [the] <card>` — real card deletion (was accepted-and-ignored).
//  Ordinals, bare `delete card` (current), by number, the last-remaining
//  guard, and cantDelete.
//

import Foundation
import Testing
@testable import HyperTalkEngine

private func threeCardJSON(cantDeleteSecond: Bool = false) -> Data {
    """
    {
      "formatVersion": 1, "id": "11111111-1111-1111-1111-111111111111",
      "name": "Del", "cardSize": {"width": 400, "height": 300}, "script": "",
      "backgrounds": [
        { "id": "22222222-2222-2222-2222-222222222222", "name": "BG", "script": "", "parts": [] }
      ],
      "cards": [
        { "id": "33333333-3333-3333-3333-333333333331", "name": "One",
          "backgroundID": "22222222-2222-2222-2222-222222222222", "script": "", "parts": [] },
        { "id": "33333333-3333-3333-3333-333333333332", "name": "Two",
          "backgroundID": "22222222-2222-2222-2222-222222222222", "script": "", "parts": [],
          "cantDelete": \(cantDeleteSecond) },
        { "id": "33333333-3333-3333-3333-333333333333", "name": "Three",
          "backgroundID": "22222222-2222-2222-2222-222222222222", "script": "", "parts": [] }
      ]
    }
    """.data(using: .utf8)!
}

@Test func deleteLastCardRemovesIt() async throws {
    let engine = try StackEngine(stackJSON: threeCardJSON())
    _ = try await engine.runMessage("delete the last card")
    #expect(engine.cardCount == 2)
    #expect(try await engine.runMessage("the name of last card") == "Two")
}

@Test func deleteCardByNumber() async throws {
    let engine = try StackEngine(stackJSON: threeCardJSON())
    _ = try await engine.runMessage("delete card 2")
    #expect(engine.cardCount == 2)
    #expect(try await engine.runMessage("the name of card 2") == "Three")
}

@Test func bareDeleteCardRemovesTheCurrentOne() async throws {
    let engine = try StackEngine(stackJSON: threeCardJSON())
    _ = try await engine.runMessage("delete card")
    #expect(engine.cardCount == 2)
    #expect(try await engine.runMessage("the name of card 1") == "Two")
}

@Test func deleteThisCardLandsOnTheNeighbor() async throws {
    let engine = try StackEngine(stackJSON: threeCardJSON())
    _ = try await engine.runMessage("go to card 2")
    _ = try await engine.runMessage("delete this card")
    #expect(engine.cardCount == 2)
    // Still a valid current card (index clamped to the survivor at 2).
    #expect(try await engine.runMessage("the name of this card") == "Three")
}

@Test func lastRemainingCardCantBeDeleted() async throws {
    let engine = try StackEngine(stackJSON: threeCardJSON())
    _ = try await engine.runMessage("delete card 1")
    _ = try await engine.runMessage("delete card 1")
    await #expect(throws: (any Error).self) {
        _ = try await engine.runMessage("delete card 1")
    }
    #expect(engine.cardCount == 1)
}

@Test func cantDeleteCardIsHonored() async throws {
    let engine = try StackEngine(stackJSON: threeCardJSON(cantDeleteSecond: true))
    await #expect(throws: (any Error).self) {
        _ = try await engine.runMessage("delete card 2")
    }
    #expect(engine.cardCount == 3)
}

@Test func deleteCardFieldNeverDeletesACard() async throws {
    // `delete card field 1` is part deletion (now real) — it must NOT delete a
    // card, and with no such field it errors honestly.
    let engine = try StackEngine(stackJSON: threeCardJSON())
    await #expect(throws: (any Error).self) {
        _ = try await engine.runMessage("delete card field 1")
    }
    #expect(engine.cardCount == 3)
}
