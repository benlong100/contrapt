//
//  PersistenceWebTests.swift
//  HyperTalkEngine
//
//  `stackData` on the exported page: the WebHost keeps the store in memory
//  (seeded from localStorage at load) and records a `persist` effect on each
//  write, which the page flushes back to localStorage. These prove the
//  round-trip: a write surfaces as an effect carrying the encoded store, and
//  seeding a fresh engine with that string makes the value readable again.
//

import Foundation
import Testing
@testable import HyperTalkEngine

private let persistJSON = """
{
  "formatVersion": 1, "id": "11111111-1111-1111-1111-111111111111",
  "name": "Persist", "cardSize": {"width": 400, "height": 300}, "script": "",
  "backgrounds": [
    { "id": "22222222-2222-2222-2222-222222222222", "name": "BG", "script": "", "parts": [] }
  ],
  "cards": [
    { "id": "33333333-3333-3333-3333-333333333333", "name": "C1",
      "backgroundID": "22222222-2222-2222-2222-222222222222", "parts": [],
      "script": "on saveName\\nput \\"Ada\\" into stackData[\\"name\\"]\\nend saveName\\n\\non loadName\\nput stackData[\\"name\\"]\\nend loadName" }
  ]
}
""".data(using: .utf8)!

private func lastMessage(_ effects: [HostEffect]) -> String? {
    for effect in effects.reversed() { if case .message(let text) = effect { return text } }
    return nil
}

private func lastPersist(_ effects: [HostEffect]) -> String? {
    for effect in effects.reversed() { if case .persist(let encoded) = effect { return encoded } }
    return nil
}

@Test func webHostWriteRecordsPersistEffect() async throws {
    let engine = try StackEngine(stackJSON: persistJSON)
    _ = try await engine.runMessage("saveName")
    #expect(lastPersist(engine.drainEffects()) != nil)
}

@Test func webHostPersistSeedRoundTrips() async throws {
    // Capture the encoded store a write produces, then seed a fresh engine with
    // it (as the page would from localStorage) and read the value back.
    let engine = try StackEngine(stackJSON: persistJSON)
    _ = try await engine.runMessage("saveName")
    let encoded = try #require(lastPersist(engine.drainEffects()))

    let reopened = try StackEngine(stackJSON: persistJSON, persistentData: encoded)
    _ = try await reopened.runMessage("loadName")
    #expect(lastMessage(reopened.drainEffects()) == "Ada")
}

@Test func webHostEmptyStoreWhenUnseeded() async throws {
    let engine = try StackEngine(stackJSON: persistJSON)
    #expect(try await engine.runMessage("the number of elements of stackData") == "0")
}
