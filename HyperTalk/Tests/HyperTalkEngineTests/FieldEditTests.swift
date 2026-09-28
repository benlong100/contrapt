//
//  FieldEditTests.swift
//  HyperTalkEngine
//
//  The page pushes visitor-typed field text into the engine (setField), and
//  scripts read what was typed.
//

import Foundation
import Testing
@testable import HyperTalkEngine

private let fieldStackJSON = """
{
  "formatVersion": 1,
  "id": "00000000-0000-0000-0000-0000000000DD",
  "name": "FieldEdit",
  "cardSize": { "width": 512, "height": 342 },
  "script": "",
  "nextID": 100,
  "backgrounds": [
    { "id": "00000000-0000-0000-0000-000000000001", "name": "BG", "script": "", "scriptID": 1, "parts": [] }
  ],
  "cards": [
    {
      "id": "00000000-0000-0000-0000-000000000010", "name": "Card 1",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 10, "script": "",
      "parts": [
        {
          "id": "00000000-0000-0000-0000-000000000020", "name": "Name", "scriptID": 20,
          "visible": true, "script": "", "type": "field",
          "frame": { "x": 40, "y": 60, "width": 300, "height": 40 },
          "field": { "format": { "align": "left", "fontDesign": "standard", "isBold": false,
                                  "isItalic": false, "isUnderline": false, "size": 17 },
                     "isMultiline": false, "kind": "plain", "lockText": false, "placeholder": "",
                     "showLines": false, "style": "rectangle", "text": "", "wideMargins": false }
        }
      ]
    }
  ]
}
""".data(using: .utf8)!

@Test
func setFieldRecordsVisitorTypedText() async throws {
    let engine = try StackEngine(stackJSON: fieldStackJSON)
    try engine.setField(partScriptID: 20, text: "Marmot")
    #expect(engine.fieldText(named: "Name") == "Marmot")
    // The value flows through to what scripts read.
    let result = try await engine.runMessage("field \"Name\"")
    #expect(result == "Marmot")
    // And the JSON envelope reports the new state, no error.
    let json = engine.setFieldJSON(partScriptID: 20, text: "Second")
    #expect(json.contains("\"Second\""))
    #expect(!json.contains("\"error\""))
    // An unknown part is an error envelope, not a trap.
    #expect(engine.setFieldJSON(partScriptID: 999, text: "x").contains("\"error\""))
}
