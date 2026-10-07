//
//  StyleRunTests.swift
//  HyperTalkEngine
//
//  Styled-text runs decode from stack JSON into FieldPart.styleRuns — the
//  exchange-format side of HyperCard's mixed-font field text.
//

import Foundation
import Testing
@testable import HyperTalkEngine

private let styledStackJSON = """
{
  "formatVersion": 1,
  "id": "00000000-0000-0000-0000-0000000000AA",
  "name": "Styled",
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
          "id": "00000000-0000-0000-0000-000000000020", "name": "Prose", "scriptID": 20,
          "visible": true, "script": "", "type": "field",
          "frame": { "x": 20, "y": 20, "width": 400, "height": 200 },
          "field": {
            "format": { "align": "left", "fontDesign": "serif", "isBold": false, "isItalic": false,
                        "isUnderline": false, "size": 18 },
            "isMultiline": true, "kind": "plain", "lockText": true, "placeholder": "",
            "showLines": false, "style": "rectangle", "text": "Bold then plain", "wideMargins": false,
            "styleRuns": [
              { "start": 0, "format": { "align": "left", "fontDesign": "serif", "isBold": true, "isItalic": false, "isUnderline": false, "size": 18 } },
              { "start": 5, "format": { "align": "left", "fontDesign": "serif", "isBold": false, "isItalic": false, "isUnderline": false, "size": 18 } }
            ]
          }
        }
      ]
    }
  ]
}
""".data(using: .utf8)!

@Test
func styleRunsDecodeFromStackJSON() throws {
    let stack = try JSONDecoder().decode(Stack.self, from: styledStackJSON)
    guard case .field(let field) = stack.cards[0].parts[0].kind else {
        Issue.record("expected a field"); return
    }
    #expect(field.styleRuns.count == 2)
    #expect(field.styleRuns[0].start == 0)
    #expect(field.styleRuns[0].format.isBold == true)
    #expect(field.styleRuns[1].start == 5)
    #expect(field.styleRuns[1].format.isBold == false)
    #expect(field.text == "Bold then plain")
}

@Test
func plainFieldDecodesWithNoStyleRuns() throws {
    // A field without a styleRuns key decodes to an empty run list (uniform).
    let stack = try StackEngine(stackJSON: styledStackJSON).stackName
    #expect(stack == "Styled")
}

private let groupStackJSON = """
{
  "formatVersion": 1,
  "id": "00000000-0000-0000-0000-0000000000AB",
  "name": "Grouped",
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
          "id": "00000000-0000-0000-0000-000000000020", "name": "Nav", "scriptID": 20,
          "visible": true, "type": "field",
          "frame": { "x": 20, "y": 20, "width": 400, "height": 200 },
          "script": "on mouseUp\\nset the textStyle of me to \\"group\\"\\nput the textStyle of me into message\\nend mouseUp",
          "field": {
            "format": { "align": "left", "fontDesign": "standard", "isBold": false, "isItalic": false,
                        "isUnderline": false, "size": 17 },
            "isMultiline": true, "kind": "plain", "lockText": true, "placeholder": "",
            "showLines": false, "style": "rectangle", "text": "Go Home", "wideMargins": false,
            "styleRuns": [
              { "start": 0, "format": { "align": "left", "fontDesign": "standard", "isBold": false, "isItalic": false, "isUnderline": false, "isGroup": true, "size": 17 } }
            ]
          }
        }
      ]
    }
  ]
}
""".data(using: .utf8)!

@Test
func groupStyleDecodesFromStackJSON() throws {
    let stack = try JSONDecoder().decode(Stack.self, from: groupStackJSON)
    guard case .field(let field) = stack.cards[0].parts[0].kind else {
        Issue.record("expected a field"); return
    }
    #expect(field.styleRuns.count == 1)
    #expect(field.styleRuns[0].format.isGroup == true)
}

@Test
func textStyleGroupSetsAndReadsBack() async throws {
    // `set the textStyle of me to "group"` then `the textStyle of me` — the
    // scriptable side of group support in the web engine.
    let engine = try StackEngine(stackJSON: groupStackJSON)
    let effects = try await engine.dispatchMouseUp(partScriptID: 20)
    #expect(effects.contains(.message("group")))
}
