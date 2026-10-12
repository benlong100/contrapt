//
//  ButtonColorTests.swift
//  HyperTalkEngine
//
//  The scriptable button colors — `the fillColor` / `the borderColor` (alias
//  edgeColor) of a button: default-empty, set/get round-trip, empty-clears,
//  decode from stack.json, and buttons-only.
//

import Foundation
import Testing
@testable import HyperTalkEngine

private func buttonJSON(_ buttonExtras: String = "") -> Data {
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
            { "id": "44444444-4444-4444-4444-444444444444", "name": "Go",
              "frame": {"x": 10, "y": 10, "width": 80, "height": 24}, "script": "",
              "scriptID": 7, "type": "button",
              "button": {"title": "Go", "style": "opaque"\(buttonExtras)} },
            { "id": "55555555-5555-5555-5555-555555555555", "name": "Notes",
              "frame": {"x": 10, "y": 50, "width": 120, "height": 90}, "script": "",
              "scriptID": 8, "type": "field",
              "field": {"text": "", "placeholder": "", "format": {}} }
          ] }
      ]
    }
    """.data(using: .utf8)!
}

@Test func buttonColorsDefaultEmpty() async throws {
    let engine = try StackEngine(stackJSON: buttonJSON())
    #expect(try await engine.runMessage("the fillColor of card button \"Go\"") == "")
    #expect(try await engine.runMessage("the borderColor of card button \"Go\"") == "")
}

@Test func buttonColorsSetGetAndClear() async throws {
    let engine = try StackEngine(stackJSON: buttonJSON())
    _ = try await engine.runMessage("set the fillColor of card button \"Go\" to \"#FF3B30\"")
    _ = try await engine.runMessage("set the borderColor of card button \"Go\" to \"blue\"")
    #expect(try await engine.runMessage("the fillColor of card button \"Go\"") == "#FF3B30")
    #expect(try await engine.runMessage("the borderColor of card button \"Go\"") == "blue")
    // Empty restores the default.
    _ = try await engine.runMessage("set the fillColor of card button \"Go\" to empty")
    #expect(try await engine.runMessage("the fillColor of card button \"Go\"") == "")
}

@Test func edgeColorIsASynonymForBorderColor() async throws {
    let engine = try StackEngine(stackJSON: buttonJSON())
    _ = try await engine.runMessage("set the edgeColor of card button \"Go\" to \"gray\"")
    #expect(try await engine.runMessage("the borderColor of card button \"Go\"") == "gray")
    #expect(try await engine.runMessage("the edgeColor of card button \"Go\"") == "gray")
}

@Test func buttonColorsDecodeFromStackJSON() async throws {
    let engine = try StackEngine(stackJSON: buttonJSON(", \"fillColor\": \"yellow\", \"borderColor\": \"#000000\""))
    #expect(try await engine.runMessage("the fillColor of card button \"Go\"") == "yellow")
    #expect(try await engine.runMessage("the borderColor of card button \"Go\"") == "#000000")
}

@Test func fieldHasNoButtonColors() async throws {
    let engine = try StackEngine(stackJSON: buttonJSON())
    await #expect(throws: (any Error).self) {
        _ = try await engine.runMessage("the fillColor of card field \"Notes\"")
    }
}

@Test func buttonTextColorSetGetAndClear() async throws {
    let engine = try StackEngine(stackJSON: buttonJSON())
    #expect(try await engine.runMessage("the textColor of card button \"Go\"") == "")
    _ = try await engine.runMessage("set the textColor of card button \"Go\" to \"white\"")
    #expect(try await engine.runMessage("the textColor of card button \"Go\"") == "white")
    _ = try await engine.runMessage("set the textColor of card button \"Go\" to empty")
    #expect(try await engine.runMessage("the textColor of card button \"Go\"") == "")
}
