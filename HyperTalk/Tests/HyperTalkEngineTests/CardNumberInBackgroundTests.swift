//
//  CardNumberInBackgroundTests.swift
//  HyperTalkEngine
//
//  `the number of this card in this background` — parses, and reads the plain
//  STACK number: Car Care's page counter subtracts the background's first
//  card itself (`… the number of this card in this background - (first - 1)`),
//  so the scope tail is identity, not background-relative renumbering.
//

import Foundation
import Testing
@testable import HyperTalkEngine

// Two backgrounds; cards interleaved so stack numbering != background numbering.
private let twoBackgroundsJSON = """
{
  "formatVersion": 1, "id": "00000000-0000-0000-0000-0000000000B2",
  "name": "Pages", "cardSize": {"width": 512, "height": 342},
  "script": "", "nextID": 100,
  "backgrounds": [
    { "id": "00000000-0000-0000-0000-000000000001", "name": "Cover", "script": "", "scriptID": 1, "parts": [] },
    { "id": "00000000-0000-0000-0000-000000000002", "name": "Gas Log", "script": "", "scriptID": 2, "parts": [] }
  ],
  "cards": [
    { "id": "00000000-0000-0000-0000-000000000010", "name": "Front",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 10, "parts": [], "script": "" },
    { "id": "00000000-0000-0000-0000-000000000011", "name": "Log1",
      "backgroundID": "00000000-0000-0000-0000-000000000002", "scriptID": 11, "parts": [], "script": "" },
    { "id": "00000000-0000-0000-0000-000000000012", "name": "Log2",
      "backgroundID": "00000000-0000-0000-0000-000000000002", "scriptID": 12, "parts": [], "script": "" }
  ]
}
""".data(using: .utf8)!

@Test func numberOfThisCardInThisBackground() async throws {
    let engine = try StackEngine(stackJSON: twoBackgroundsJSON)
    _ = try await engine.openCard(index: 2)   // Log2: card 3 of the stack
    #expect(try await engine.runMessage("the number of this card") == "3")
    #expect(try await engine.runMessage("the number of this card in this background") == "3")
    // Car Care's page counter end to end: first card of the background, then
    // the relative page from plain stack numbers.
    let first = try await engine.runMessage("the number of the first card in background \"Gas Log\"")
    #expect(first == "2")
    let page = try await engine.runMessage(
        "\"Page \" & the number of this card in this background - (2 - 1) & \" of \" & the number of cards in this background")
    #expect(page == "Page 2 of 2")
}
