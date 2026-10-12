//
//  FieldColorTests.swift
//  HyperTalkEngine
//
//  The scriptable field colors — `the textColor` / `the borderColor` (alias
//  edgeColor) of a field: default-empty, set/get round-trip, empty-clears,
//  decode from stack.json, and textColor is fields-only.
//

import Foundation
import Testing
@testable import HyperTalkEngine

private func fieldJSON(_ fieldExtras: String = "") -> Data {
    """
    {
      "formatVersion": 1, "id": "11111111-1111-1111-1111-111111111111",
      "name": "Colors", "cardSize": {"width": 400, "height": 300}, "script": "",
      "backgrounds": [
        { "id": "22222222-2222-2222-2222-222222222222", "name": "BG", "script": "", "parts": [] }
      ],
      "cards": [
        { "id": "33333333-3333-3333-3333-333333333333", "name": "C1",
          "backgroundID": "22222222-2222-2222-2222-222222222222", "script": "",
          "parts": [
            { "id": "44444444-4444-4444-4444-444444444444", "name": "Notes",
              "frame": {"x": 10, "y": 10, "width": 120, "height": 90}, "script": "",
              "scriptID": 7, "type": "field",
              "field": {"text": "hello", "placeholder": "", "format": {}\(fieldExtras)} },
            { "id": "55555555-5555-5555-5555-555555555555", "name": "Go",
              "frame": {"x": 10, "y": 120, "width": 80, "height": 24}, "script": "",
              "scriptID": 8, "type": "button",
              "button": {"title": "Go"} }
          ] }
      ]
    }
    """.data(using: .utf8)!
}

@Test func fieldColorsDefaultEmpty() async throws {
    let engine = try StackEngine(stackJSON: fieldJSON())
    #expect(try await engine.runMessage("the textColor of card field \"Notes\"") == "")
    #expect(try await engine.runMessage("the borderColor of card field \"Notes\"") == "")
}

@Test func fieldColorsSetGetAndClear() async throws {
    let engine = try StackEngine(stackJSON: fieldJSON())
    _ = try await engine.runMessage("set the textColor of card field \"Notes\" to \"#00FF00\"")
    _ = try await engine.runMessage("set the borderColor of card field \"Notes\" to \"red\"")
    #expect(try await engine.runMessage("the textColor of card field \"Notes\"") == "#00FF00")
    #expect(try await engine.runMessage("the borderColor of card field \"Notes\"") == "red")
    _ = try await engine.runMessage("set the textColor of card field \"Notes\" to empty")
    #expect(try await engine.runMessage("the textColor of card field \"Notes\"") == "")
}

@Test func fieldEdgeColorSynonymWorks() async throws {
    let engine = try StackEngine(stackJSON: fieldJSON())
    _ = try await engine.runMessage("set the edgeColor of card field \"Notes\" to \"gray\"")
    #expect(try await engine.runMessage("the borderColor of card field \"Notes\"") == "gray")
}

@Test func fieldColorsDecodeFromStackJSON() async throws {
    let engine = try StackEngine(stackJSON: fieldJSON(", \"textColor\": \"navy\", \"borderColor\": \"#333333\""))
    #expect(try await engine.runMessage("the textColor of card field \"Notes\"") == "navy")
    #expect(try await engine.runMessage("the borderColor of card field \"Notes\"") == "#333333")
}

@Test func buttonHasNoTextColor() async throws {
    let engine = try StackEngine(stackJSON: fieldJSON())
    await #expect(throws: (any Error).self) {
        _ = try await engine.runMessage("the textColor of card button \"Go\"")
    }
}
