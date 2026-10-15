//
//  EnvironmentTests.swift
//  HyperTalkEngine
//
//  `the environment` reads "Development" — Contrapt is full HyperCard, not the
//  Player. Stacks with Player/Development twin field sets switch on it (What is
//  HyperCard?'s showTextFields: `get (the environment is "Development") / set
//  the visible of fld "Body Dev" to it / … "Body Player" to not it`), so the
//  value decides which fields real HyperCard — and Contrapt — display.
//

import Foundation
import Testing
@testable import HyperTalkEngine

private let environmentJSON = """
{
  "formatVersion": 1,
  "id": "00000000-0000-0000-0000-0000000000EE",
  "name": "Env",
  "cardSize": { "width": 512, "height": 342 },
  "script": "",
  "nextID": 100,
  "backgrounds": [
    { "id": "00000000-0000-0000-0000-000000000001", "name": "BG", "script": "", "scriptID": 1, "parts": [] }
  ],
  "cards": [
    { "id": "00000000-0000-0000-0000-000000000010", "name": "Only",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 10, "parts": [], "script": "" }
  ]
}
""".data(using: .utf8)!

@Test func theEnvironmentReadsDevelopment() async throws {
    let engine = try StackEngine(stackJSON: environmentJSON)
    #expect(try await engine.runMessage("the environment") == "Development")
    // The showTextFields comparison idiom evaluates true.
    #expect(try await engine.runMessage("the environment is \"Development\"") == "true")
}
