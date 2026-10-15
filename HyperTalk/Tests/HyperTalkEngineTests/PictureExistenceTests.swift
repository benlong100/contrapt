//
//  PictureExistenceTests.swift
//  HyperTalkEngine
//
//  `there is a[ no] [card|bkgnd] picture` — the paint layer as an existence
//  test. Clip Art prunes blank cards with `if background field "key words" is
//  empty and there is no card picture then doMenu "delete card"`.
//

import Foundation
import Testing
@testable import HyperTalkEngine

private let pictureJSON = """
{
  "formatVersion": 1, "id": "00000000-0000-0000-0000-0000000000D0",
  "name": "Pics", "cardSize": {"width": 512, "height": 342},
  "script": "", "nextID": 100,
  "backgrounds": [
    { "id": "00000000-0000-0000-0000-000000000001", "name": "BG", "script": "", "scriptID": 1,
      "parts": [], "paintImageAsset": "bg-paint.png" }
  ],
  "cards": [
    { "id": "00000000-0000-0000-0000-000000000010", "name": "Painted",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 10, "parts": [],
      "script": "", "paintImageAsset": "card-paint.png" },
    { "id": "00000000-0000-0000-0000-000000000011", "name": "Blank",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 11, "parts": [], "script": "" }
  ]
}
""".data(using: .utf8)!

@Test func cardPictureExistenceFollowsThePaintLayer() async throws {
    let engine = try StackEngine(stackJSON: pictureJSON)
    #expect(try await engine.runMessage("there is a card picture") == "true")
    #expect(try await engine.runMessage("there is no card picture") == "false")
    #expect(try await engine.runMessage("there is a bkgnd picture") == "true")
    _ = try await engine.openCard(index: 1)
    #expect(try await engine.runMessage("there is a card picture") == "false")
    #expect(try await engine.runMessage("there is no card picture") == "true")
    // The background's paint is shared — still present from the blank card.
    #expect(try await engine.runMessage("there is a background picture") == "true")
}

@Test func clipArtConditionParses() async throws {
    // The exact Clip Art shape: existence inside an `and` condition.
    let engine = try StackEngine(stackJSON: pictureJSON)
    _ = try await engine.openCard(index: 1)
    let value = try await engine.runMessage("(\"\" is empty) and (there is no card picture)")
    #expect(value == "true")
}
