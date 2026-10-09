//
//  GoBackgroundTests.swift
//  HyperTalkEngine
//
//  `go next/previous background` — navigate to the first card of the adjacent
//  background (stack order, wrapping), against a real multi-background stack.
//

import Foundation
import Testing
@testable import HyperTalkEngine

/// Three cards across two backgrounds: Guide (G1 idx0, G2 idx1) and Extras
/// (X1 idx2). Each card can step to the next/previous background.
private let json = """
{
  "formatVersion": 1,
  "id": "00000000-0000-0000-0000-0000000000CC",
  "name": "Sections",
  "cardSize": { "width": 512, "height": 342 },
  "script": "", "nextID": 100,
  "backgrounds": [
    { "id": "00000000-0000-0000-0000-000000000001", "name": "Guide", "script": "", "scriptID": 1, "parts": [] },
    { "id": "00000000-0000-0000-0000-000000000002", "name": "Extras", "script": "", "scriptID": 2, "parts": [] }
  ],
  "cards": [
    { "id": "00000000-0000-0000-0000-000000000010", "name": "G1",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 10, "parts": [],
      "script": "on fwd\\ngo next background\\nend fwd\\n\\non bwd\\ngo previous background\\nend bwd" },
    { "id": "00000000-0000-0000-0000-000000000011", "name": "G2",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 11, "parts": [], "script": "" },
    { "id": "00000000-0000-0000-0000-000000000012", "name": "X1",
      "backgroundID": "00000000-0000-0000-0000-000000000002", "scriptID": 12, "parts": [],
      "script": "on fwd\\ngo next background\\nend fwd" }
  ]
}
""".data(using: .utf8)!

private func landedCardIndex(_ effects: [HostEffect]) -> Int? {
    for e in effects.reversed() { if case .navigate(let i, _) = e { return i } }
    return nil
}

@Test func goNextBackgroundLandsOnAdjacentBackgroundFirstCard() async throws {
    let engine = try StackEngine(stackJSON: json)
    // From G1 (Guide), next background is Extras → its first card X1 (idx 2).
    _ = try await engine.runMessage("fwd")
    #expect(landedCardIndex(engine.drainEffects()) == 2)
    // From X1 (Extras, now current), next background wraps to Guide → G1 (idx 0).
    _ = try await engine.runMessage("fwd")
    #expect(landedCardIndex(engine.drainEffects()) == 0)
}

@Test func goPreviousBackgroundWrapsBackward() async throws {
    let engine = try StackEngine(stackJSON: json)
    // From G1 (Guide), previous background wraps to Extras → X1 (idx 2).
    _ = try await engine.runMessage("bwd")
    #expect(landedCardIndex(engine.drainEffects()) == 2)
}
