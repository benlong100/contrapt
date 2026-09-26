//
//  EngineJSONTests.swift
//  HyperTalkEngine
//
//  Exercises the string-in/string-out ABI the browser bridge will call.
//

import Foundation
import Testing
@testable import HyperTalkEngine

/// Decodable mirrors of the ABI envelopes, so tests read them back as JS would.
private struct DecodedState: Decodable {
    struct Part: Decodable { let scriptID: Int; let kind: String; let name: String; let text: String?; let visible: Bool }
    let cardIndex: Int
    let cardName: String
    let cardParts: [Part]
}
private struct DecodedEvent: Decodable {
    struct Effect: Decodable { let type: String; let text: String?; let cardIndex: Int? }
    let effects: [Effect]
    let state: DecodedState
    let error: String?
}
private struct DecodedSnapshot: Decodable {
    let name: String
    let cardCount: Int
    let currentCardIndex: Int
    let cardWidth: Double
    let state: DecodedState
}

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

@Test
func snapshotJSONDescribesStack() throws {
    let engine = try StackEngine(stackJSON: sampleJSON)
    let snapshot = try decode(DecodedSnapshot.self, engine.snapshotJSON())
    #expect(snapshot.name == "Sample")
    #expect(snapshot.cardCount == 2)
    #expect(snapshot.currentCardIndex == 0)
    #expect(snapshot.cardWidth == 512)
    #expect(snapshot.state.cardName == "Card 1")
}

@Test
func mouseUpJSONReportsFieldWrite() async throws {
    let engine = try StackEngine(stackJSON: sampleJSON)
    let event = try decode(DecodedEvent.self, await engine.dispatchMouseUpJSON(partScriptID: 21))
    #expect(event.error == nil)
    let result = event.state.cardParts.first { $0.name == "Result" }
    #expect(result?.text == "hello")
}

@Test
func mouseUpJSONReportsNavigateEffect() async throws {
    let engine = try StackEngine(stackJSON: sampleJSON)
    let event = try decode(DecodedEvent.self, await engine.dispatchMouseUpJSON(partScriptID: 23))
    #expect(event.effects.contains { $0.type == "navigate" && $0.cardIndex == 1 })
    #expect(event.state.cardName == "Card 2")
}

@Test
func mouseUpJSONReportsMessageEffect() async throws {
    let engine = try StackEngine(stackJSON: sampleJSON)
    let event = try decode(DecodedEvent.self, await engine.dispatchMouseUpJSON(partScriptID: 24))
    #expect(event.effects.contains { $0.type == "message" && $0.text == "hi there" })
}

@Test
func unknownPartBecomesErrorEnvelope() async throws {
    let engine = try StackEngine(stackJSON: sampleJSON)
    let event = try decode(DecodedEvent.self, await engine.dispatchMouseUpJSON(partScriptID: 999))
    #expect(event.error != nil)
}

@Test
func messageBoxJSONReturnsValue() async throws {
    let engine = try StackEngine(stackJSON: sampleJSON)
    struct R: Decodable { let result: String?; let error: String? }
    let r = try decode(R.self, await engine.runMessageJSON("3 * 4"))
    #expect(r.error == nil)
    #expect(r.result == "12")
}
