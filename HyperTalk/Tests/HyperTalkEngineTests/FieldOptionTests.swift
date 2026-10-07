//
//  FieldOptionTests.swift
//  HyperTalkEngine
//
//  HyperCard's remaining Field Info options — dontWrap, autoTab, autoSelect,
//  multipleLines, fixedLineHeight — and the scrolling field style: scriptable
//  get/set through the engine's real host, and decodable from stack JSON.
//

import Foundation
import Testing
@testable import HyperTalkEngine

private let optionsStackJSON = """
{
  "formatVersion": 1,
  "id": "00000000-0000-0000-0000-0000000000EE",
  "name": "FieldOptions",
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
          "id": "00000000-0000-0000-0000-000000000020", "name": "List", "scriptID": 20,
          "visible": true, "script": "", "type": "field",
          "frame": { "x": 40, "y": 60, "width": 300, "height": 200 },
          "field": { "format": { "align": "left", "fontDesign": "standard", "isBold": false,
                                  "isItalic": false, "isUnderline": false, "size": 17 },
                     "isMultiline": true, "kind": "plain", "lockText": true, "placeholder": "",
                     "showLines": false, "style": "scrolling", "text": "alpha\\nbeta\\ngamma",
                     "wideMargins": false, "dontWrap": true, "autoSelect": true }
        }
      ]
    }
  ]
}
""".data(using: .utf8)!

@Test
func fieldOptionsDecodeAndReadAsProperties() async throws {
    let engine = try StackEngine(stackJSON: optionsStackJSON)
    #expect(try await engine.runMessage("the style of field \"List\"") == "scrolling")
    #expect(try await engine.runMessage("the dontWrap of field \"List\"") == "true")
    #expect(try await engine.runMessage("the autoSelect of field \"List\"") == "true")
    #expect(try await engine.runMessage("the autoTab of field \"List\"") == "false")
    #expect(try await engine.runMessage("the multipleLines of field \"List\"") == "false")
    #expect(try await engine.runMessage("the fixedLineHeight of field \"List\"") == "false")
}

@Test
func fieldOptionsAreSettable() async throws {
    let engine = try StackEngine(stackJSON: optionsStackJSON)
    _ = try await engine.runMessage("set the dontWrap of field \"List\" to false")
    #expect(try await engine.runMessage("the dontWrap of field \"List\"") == "false")
    _ = try await engine.runMessage("set the autoTab of field \"List\" to true")
    #expect(try await engine.runMessage("the autoTab of field \"List\"") == "true")
    _ = try await engine.runMessage("set the style of field \"List\" to rectangle")
    #expect(try await engine.runMessage("the style of field \"List\"") == "rectangle")
    // sharedText is accepted and ignored (background fields inherently share).
    _ = try await engine.runMessage("set the sharedText of field \"List\" to true")
}
