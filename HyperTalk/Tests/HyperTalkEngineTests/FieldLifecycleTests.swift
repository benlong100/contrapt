//
//  FieldLifecycleTests.swift
//  HyperTalkEngine
//
//  openField / closeField / exitField — the field-editing lifecycle the page
//  dispatches from focus/blur, handled by ordinary field scripts.
//

import Foundation
import Testing
@testable import HyperTalkEngine

private let lifecycleJSON = """
{
  "formatVersion": 1,
  "id": "00000000-0000-0000-0000-0000000000AB",
  "name": "Lifecycle",
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
          "visible": true, "type": "field",
          "frame": { "x": 40, "y": 60, "width": 300, "height": 40 },
          "script": "on openField\\nput \\"editing…\\" into message\\nend openField\\n\\non closeField\\nput \\"saved:\\" && field \\"Name\\" into message\\nend closeField\\n\\non exitField\\nput \\"unchanged\\" into message\\nend exitField",
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
func fieldLifecycleMessagesReachTheFieldScript() async throws {
    let engine = try StackEngine(stackJSON: lifecycleJSON)

    let opened = try await engine.send("openField", toPartWithScriptID: 20)
    #expect(opened.contains(.message("editing…")))

    try engine.setField(partScriptID: 20, text: "Marmot")
    let closed = try await engine.send("closeField", toPartWithScriptID: 20)
    
    #expect(closed.contains(.message("saved: Marmot")))

    let exited = try await engine.send("exitField", toPartWithScriptID: 20)
    #expect(exited.contains(.message("unchanged")))

    // The JSON path the page actually calls, including an unhandled message
    // (no error — it just travels the path and lands nowhere).
    let json = await engine.sendToPartJSON("openField", partScriptID: 20)
    #expect(json.contains("editing…"))
    let unhandled = await engine.sendToPartJSON("somethingNobodyHandles", partScriptID: 20)
    #expect(!unhandled.contains("\"error\""))
}
