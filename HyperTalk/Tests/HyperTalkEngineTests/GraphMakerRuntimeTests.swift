//
//  GraphMakerRuntimeTests.swift
//  HyperTalkEngine
//
//  Runtime behavior needed by Apple's Graph Maker stack script: the openStack
//  guard (wrongStack via `the stacks` / `the long name of me`), scoped part
//  property sets, and rect writes.
//

import Foundation
import Testing
@testable import HyperTalkEngine

/// One background ("Graphs") carrying a hilited button with scriptID 68 and a
/// frame button; the stack script is a trimmed Graph Maker openStack.
private let graphJSON = """
{
  "formatVersion": 1, "id": "00000000-0000-0000-0000-0000000000DD",
  "name": "Graph Maker", "cardSize": { "width": 512, "height": 342 },
  "script": "on openStack\\nif wrongStack() then pass openStack\\nglobal IsCommonData,theData,SavLvl\\nput the userLevel into SavLvl\\nset the userLevel to 5\\nif there is a bg \\"Graphs\\" then\\nset hilite of bg btn id 68 of cd 1 of bg \\"Graphs\\" to false\\nend if\\nput false into IsCommonData\\nput empty into theData\\npass openStack\\nend openStack\\n\\nfunction wrongStack\\nget the value of word 2 of the long name of me\\nreturn (it is not line 1 of the stacks)\\nend wrongStack\\n\\non setFrame\\nset rect of bg btn \\"Frame\\" to \\"10,20,110,70\\"\\nend setFrame",
  "nextID": 100,
  "backgrounds": [
    {
      "id": "00000000-0000-0000-0000-000000000001", "name": "Graphs", "script": "", "scriptID": 1,
      "parts": [
        {
          "id": "00000000-0000-0000-0000-000000000021", "name": "Shared Data", "scriptID": 68,
          "frame": { "x": 10, "y": 10, "width": 80, "height": 30 }, "script": "",
          "type": "button", "button": { "title": "Shared Data", "style": "checkbox", "hilite": true }
        },
        {
          "id": "00000000-0000-0000-0000-000000000022", "name": "Frame", "scriptID": 69,
          "frame": { "x": 0, "y": 0, "width": 50, "height": 50 }, "script": "",
          "type": "button", "button": { "title": "" }
        }
      ]
    }
  ],
  "cards": [
    {
      "id": "00000000-0000-0000-0000-000000000010", "name": "Card 1",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "script": "", "scriptID": 10, "parts": []
    }
  ]
}
""".data(using: .utf8)!

@Test func graphMakerOpenStackRuns() async throws {
    let engine = try StackEngine(stackJSON: graphJSON)
    _ = try await engine.start()   // sends openStack (then openCard)
    // wrongStack() must be false (right stack), so the handler runs through:
    // the shared-data button's hilite is cleared.
    let shared = engine.currentCardState().backgroundParts.first { $0.scriptID == 68 }
    #expect(shared?.hilite == false)
}

@Test func rectPropertySetsFrame() async throws {
    let engine = try StackEngine(stackJSON: graphJSON)
    _ = try await engine.send("setFrame", toPartWithScriptID: 68)
    let frame = engine.currentCardState().backgroundParts.first { $0.scriptID == 69 }
    #expect(frame?.x == 10)
    #expect(frame?.y == 20)
    #expect(frame?.width == 100)
    #expect(frame?.height == 50)
}
