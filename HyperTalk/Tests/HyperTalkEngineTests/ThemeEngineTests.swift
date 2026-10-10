//
//  ThemeEngineTests.swift
//  HyperTalkEngine
//
//  The `theme` stack property on the shared engine: default, script get/set
//  (with normalization), decode from stack.json, and that it surfaces in
//  CardState so the exported page can re-apply the palette live.
//

import Foundation
import Testing
@testable import HyperTalkEngine

private func themeJSON(_ themeField: String) -> Data {
    """
    {
      "formatVersion": 1, "id": "11111111-1111-1111-1111-111111111111",
      "name": "Themed", "cardSize": {"width": 400, "height": 300}, "script": "",
      \(themeField)
      "backgrounds": [
        { "id": "22222222-2222-2222-2222-222222222222", "name": "BG", "script": "", "parts": [] }
      ],
      "cards": [
        { "id": "33333333-3333-3333-3333-333333333333", "name": "C1",
          "backgroundID": "22222222-2222-2222-2222-222222222222", "script": "", "parts": [] }
      ]
    }
    """.data(using: .utf8)!
}

@Test func themeDefaultsToClassic() async throws {
    let engine = try StackEngine(stackJSON: themeJSON(""))
    #expect(try await engine.runMessage("the theme of this stack") == "classic")
}

@Test func themeDecodesFromStackJSON() async throws {
    let engine = try StackEngine(stackJSON: themeJSON("\"theme\": \"dark\","))
    #expect(try await engine.runMessage("the theme of this stack") == "dark")
}

@Test func themeDecodeNormalizesUnknown() async throws {
    let engine = try StackEngine(stackJSON: themeJSON("\"theme\": \"bogus\","))
    #expect(try await engine.runMessage("the theme of this stack") == "classic")
}

@Test func themeSetThroughScriptRoundTrips() async throws {
    let engine = try StackEngine(stackJSON: themeJSON(""))
    _ = try await engine.runMessage("set the theme of this stack to \"dark\"")
    #expect(try await engine.runMessage("the theme of this stack") == "dark")
}

@Test func themeSetNormalizesAliasAndUnknown() async throws {
    let engine = try StackEngine(stackJSON: themeJSON(""))
    _ = try await engine.runMessage("set the theme of this stack to \"Modern Light\"")
    #expect(try await engine.runMessage("the theme of this stack") == "light")
    _ = try await engine.runMessage("set the theme of this stack to \"nope\"")
    #expect(try await engine.runMessage("the theme of this stack") == "classic")
}

@Test func themeSurfacesInCardState() async throws {
    let engine = try StackEngine(stackJSON: themeJSON(""))
    _ = try await engine.runMessage("set the theme of this stack to \"dark\"")
    #expect(engine.currentCardState().theme == "dark")
}
