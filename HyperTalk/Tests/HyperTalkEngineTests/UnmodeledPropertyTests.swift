//
//  UnmodeledPropertyTests.swift
//  HyperTalkEngine
//
//  Property getters the runtime audit (tool #4) surfaced as unimplemented:
//  reading `the script of` an object, benign defaults for unmodeled stack
//  properties (cantModify, …), and part `enabled`/`scroll`. Reading these must
//  return a value, not throw "no such property".
//

import Foundation
import Testing
@testable import HyperTalkEngine

private let propStackJSON = """
{
  "formatVersion": 1, "id": "00000000-0000-0000-0000-0000000000AF",
  "name": "Props", "cardSize": { "width": 512, "height": 342 },
  "script": "on doIt\\nend doIt", "nextID": 100,
  "backgrounds": [
    { "id": "00000000-0000-0000-0000-000000000001", "name": "BG", "script": "", "scriptID": 1,
      "parts": [
        { "id": "00000000-0000-0000-0000-000000000030", "name": "B", "scriptID": 30, "type": "button",
          "frame": { "x": 0, "y": 0, "width": 40, "height": 20 }, "button": { "title": "B" } }
      ] }
  ],
  "cards": [
    {
      "id": "00000000-0000-0000-0000-000000000010", "name": "Card 1",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 10,
      "script": "on probe\\nput (the script of this stack is not empty) into field \\"out\\"\\nput \\",\\" & the cantModify of this stack after field \\"out\\"\\nput \\",\\" & the enabled of bg btn \\"B\\" after field \\"out\\"\\nput \\",\\" & the scroll of field \\"out\\" after field \\"out\\"\\nend probe",
      "parts": [
        { "id": "00000000-0000-0000-0000-000000000020", "name": "out", "scriptID": 20, "type": "field",
          "frame": { "x": 10, "y": 10, "width": 200, "height": 100 }, "field": { "text": "" } }
      ]
    }
  ]
}
""".data(using: .utf8)!

@Test func unmodeledPropertyGettersReturnDefaults() async throws {
    let engine = try StackEngine(stackJSON: propStackJSON)
    _ = try await engine.send("probe", toPartWithScriptID: 20)
    // script-of-stack non-empty, cantModify false, enabled true, scroll 0.
    #expect(engine.fieldText(named: "out") == "true,false,true,0")
}
