//
//  AppleEventTests.swift
//  HyperTalkEngine
//
//  AppleEvent verbs (HyperBattleship's networked play) — `put X to program Y
//  [without reply]`, `send X to program Y`, `answer program <prompt> [of type]`,
//  `request X from program Y`, `reply X`. No other app is reachable, so each is
//  accepted and no-op'd; `answer program` comes back cancelled (empty `it`).
//

import Foundation
import Testing
@testable import HyperTalkEngine

private let aeStackJSON = """
{
  "formatVersion": 1, "id": "00000000-0000-0000-0000-0000000000AE",
  "name": "AE", "cardSize": { "width": 512, "height": 342 }, "script": "", "nextID": 100,
  "backgrounds": [ { "id": "00000000-0000-0000-0000-000000000001", "name": "BG", "script": "", "scriptID": 1, "parts": [] } ],
  "cards": [
    {
      "id": "00000000-0000-0000-0000-000000000010", "name": "Card 1",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 10, "parts": [],
      "script": "on probe\\nanswer program \\"Select a player...\\" of type \\"WILDep01\\"\\nput it into message\\nend probe"
    }
  ]
}
""".data(using: .utf8)!

@Test func appleEventSendCommandsAreNoOps() async throws {
    let e = try StackEngine(stackJSON: aeStackJSON)
    // None throw — the external application is unreachable, so each no-ops.
    _ = try await e.runMessage("put \"loc\" to program \"WILD\"")
    _ = try await e.runMessage("put \"loc\" to program \"WILD\" without reply")
    _ = try await e.runMessage("send \"hi\" to program \"WILD\"")
    _ = try await e.runMessage("request \"x\" from program \"WILD\"")
    _ = try await e.runMessage("reply \"ok\"")
}

@Test func answerProgramComesBackEmpty() async throws {
    // `answer program …` behaves as cancelled: `it` is empty.
    let e = try StackEngine(stackJSON: aeStackJSON)
    _ = try await e.runMessage("probe")
    #expect(e.drainEffects().contains(.message("")))
}
