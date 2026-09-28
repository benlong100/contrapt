//
//  VisualEffectPassthroughTests.swift
//  HyperTalkEngine
//
//  A scripted `visual effect` arrives structured (kind/direction/speed) in
//  the navigate effect, for the web player's transition renderer.
//

import Foundation
import Testing
import HyperTalk
@testable import HyperTalkEngine

private let fxJSON = """
{
  "formatVersion": 1,
  "id": "00000000-0000-0000-0000-0000000000FF",
  "name": "FX",
  "cardSize": { "width": 512, "height": 342 },
  "script": "",
  "nextID": 100,
  "backgrounds": [
    { "id": "00000000-0000-0000-0000-000000000001", "name": "BG", "script": "", "scriptID": 1, "parts": [] }
  ],
  "cards": [
    {
      "id": "00000000-0000-0000-0000-000000000010", "name": "One",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 10, "parts": [],
      "script": "on go2\\nvisual effect iris open slow\\ngo next\\nend go2"
    },
    {
      "id": "00000000-0000-0000-0000-000000000011", "name": "Two",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 11, "parts": [], "script": ""
    }
  ]
}
""".data(using: .utf8)!

@Test
func scriptedEffectArrivesStructuredInNavigate() async throws {
    let engine = try StackEngine(stackJSON: fxJSON)
    _ = try await engine.runMessage("go2")
    let effects = engine.drainEffects()
    let expected = ScreenEffect(kind: .iris, direction: .open, speed: .slow)
    #expect(effects.contains { effect in
        if case .navigate(1, let fx) = effect { return fx == [expected] }
        return false
    })
    // …and it serializes with the keys the player reads (kind/direction/speed).
    let data = try JSONEncoder().encode([expected])
    let json = String(data: data, encoding: .utf8) ?? ""
    #expect(json.contains(#""kind":"iris""#))
    #expect(json.contains(#""direction":"open""#))
    #expect(json.contains(#""speed":"slow""#))
}
