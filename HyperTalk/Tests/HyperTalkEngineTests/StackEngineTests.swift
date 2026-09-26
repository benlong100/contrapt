//
//  StackEngineTests.swift
//  HyperTalkEngine
//

import Foundation
import Testing
@testable import HyperTalkEngine

/// A small two-card stack exercised by the tests. Card 1 carries four parts:
/// a button that writes a field, the field itself, a button that navigates, a
/// button that posts to the message box, and a button reading a property.
let sampleJSON = """
{
  "formatVersion": 1,
  "id": "00000000-0000-0000-0000-0000000000AA",
  "name": "Sample",
  "cardSize": { "width": 512, "height": 342 },
  "script": "",
  "nextID": 100,
  "backgrounds": [
    { "id": "00000000-0000-0000-0000-000000000001", "name": "BG", "script": "", "scriptID": 1, "parts": [] }
  ],
  "cards": [
    {
      "id": "00000000-0000-0000-0000-000000000010",
      "name": "Card 1",
      "backgroundID": "00000000-0000-0000-0000-000000000001",
      "script": "",
      "scriptID": 10,
      "parts": [
        {
          "id": "00000000-0000-0000-0000-000000000021", "name": "Say", "scriptID": 21,
          "frame": { "x": 10, "y": 10, "width": 80, "height": 30 },
          "script": "on mouseUp\\nput \\"hello\\" into field \\"Result\\"\\nend mouseUp",
          "type": "button", "button": { "title": "Say" }
        },
        {
          "id": "00000000-0000-0000-0000-000000000022", "name": "Result", "scriptID": 22,
          "frame": { "x": 10, "y": 50, "width": 200, "height": 30 },
          "script": "",
          "type": "field", "field": { "text": "", "placeholder": "" }
        },
        {
          "id": "00000000-0000-0000-0000-000000000023", "name": "Next", "scriptID": 23,
          "frame": { "x": 10, "y": 90, "width": 80, "height": 30 },
          "script": "on mouseUp\\ngo to next card\\nend mouseUp",
          "type": "button", "button": { "title": "Next" }
        },
        {
          "id": "00000000-0000-0000-0000-000000000024", "name": "Msg", "scriptID": 24,
          "frame": { "x": 10, "y": 130, "width": 80, "height": 30 },
          "script": "on mouseUp\\nput \\"hi there\\"\\nend mouseUp",
          "type": "button", "button": { "title": "Msg" }
        },
        {
          "id": "00000000-0000-0000-0000-000000000025", "name": "Hide", "scriptID": 25,
          "frame": { "x": 10, "y": 170, "width": 80, "height": 30 },
          "script": "on mouseUp\\nset the visible of button \\"Msg\\" to false\\nend mouseUp",
          "type": "button", "button": { "title": "Hide" }
        }
      ]
    },
    {
      "id": "00000000-0000-0000-0000-000000000011",
      "name": "Card 2",
      "backgroundID": "00000000-0000-0000-0000-000000000001",
      "script": "",
      "scriptID": 11,
      "parts": []
    }
  ]
}
""".data(using: .utf8)!


private func makeEngine() throws -> StackEngine {
    try StackEngine(stackJSON: sampleJSON)
}

@Test
func loadsStack() throws {
    let engine = try makeEngine()
    #expect(engine.stackName == "Sample")
    #expect(engine.cardCount == 2)
    #expect(engine.currentCardIndex == 0)
    #expect(engine.cardWidth == 512)
}

@Test
func mouseUpWritesField() async throws {
    let engine = try makeEngine()
    #expect(engine.fieldText(named: "Result") == "")
    try await engine.dispatchMouseUp(partScriptID: 21)   // "Say"
    #expect(engine.fieldText(named: "Result") == "hello")
}

@Test
func mouseUpNavigates() async throws {
    let engine = try makeEngine()
    let effects = try await engine.dispatchMouseUp(partScriptID: 23)   // "Next"
    #expect(engine.currentCardIndex == 1)
    #expect(effects.contains(.navigate(cardIndex: 1, effects: [])))
}

@Test
func mouseUpPostsMessage() async throws {
    let engine = try makeEngine()
    let effects = try await engine.dispatchMouseUp(partScriptID: 24)   // "Msg"
    #expect(effects.contains(.message("hi there")))
}

@Test
func setPropertyMutatesModel() async throws {
    let engine = try makeEngine()
    try await engine.dispatchMouseUp(partScriptID: 25)   // "Hide" → set visible of Msg false
    let msg = engine.currentCardState().cardParts.first { $0.scriptID == 24 }
    #expect(msg?.visible == false)
}

@Test
func messageBoxEvaluatesExpression() async throws {
    let engine = try makeEngine()
    let result = try await engine.runMessage("1 + 2")
    #expect(result == "3")
}

@Test
func currentCardStateReflectsCard() throws {
    let engine = try makeEngine()
    let state = engine.currentCardState()
    #expect(state.cardName == "Card 1")
    #expect(state.cardParts.contains { $0.name == "Result" && $0.kind == "field" })
}
