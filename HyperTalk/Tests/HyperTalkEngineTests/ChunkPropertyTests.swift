//
//  ChunkPropertyTests.swift
//  HyperTalkEngine
//
//  Reading a text-run property of a CHUNK of a field — `the textStyle of char
//  3 of field "X"`, `the textSize of line 2 of fld "Notes"`. The run property
//  is read over the chunk's character range: the uniform value, or "mixed".
//  (The Library: `textSize of char 1 of fld "styled"`; Power Tools: `textStyle
//  of line N of bg field "MenuItems"`.)
//

import Foundation
import Testing
@testable import HyperTalkEngine

/// Field "Styled" = "AABBCC": chars 1–2 plain/12pt, chars 3–4 bold/18pt,
/// chars 5–6 plain/12pt (style runs start at offsets 0, 2, 4).
private let styledJSON = """
{
  "formatVersion": 1, "id": "00000000-0000-0000-0000-0000000000CP",
  "name": "Styled", "cardSize": { "width": 512, "height": 342 }, "script": "", "nextID": 100,
  "backgrounds": [ { "id": "00000000-0000-0000-0000-000000000001", "name": "BG", "script": "", "scriptID": 1, "parts": [] } ],
  "cards": [
    {
      "id": "00000000-0000-0000-0000-000000000010", "name": "Card 1",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 10, "script": "",
      "parts": [
        {
          "id": "00000000-0000-0000-0000-000000000020", "name": "Styled", "scriptID": 20,
          "visible": true, "script": "", "type": "field",
          "frame": { "x": 10, "y": 10, "width": 200, "height": 100 },
          "field": {
            "format": { "align": "left", "fontDesign": "standard", "isBold": false, "isItalic": false, "isUnderline": false, "size": 12 },
            "isMultiline": true, "kind": "plain", "lockText": false, "placeholder": "", "showLines": false,
            "style": "transparent", "text": "AABBCC", "wideMargins": false,
            "styleRuns": [
              { "start": 0, "format": { "align": "left", "fontDesign": "standard", "isBold": false, "isItalic": false, "isUnderline": false, "size": 12 } },
              { "start": 2, "format": { "align": "left", "fontDesign": "standard", "isBold": true,  "isItalic": false, "isUnderline": false, "size": 18 } },
              { "start": 4, "format": { "align": "left", "fontDesign": "standard", "isBold": false, "isItalic": false, "isUnderline": false, "size": 12 } }
            ]
          }
        }
      ]
    }
  ]
}
""".data(using: .utf8)!

@Test func textStyleOfUniformChunk() async throws {
    let engine = try StackEngine(stackJSON: styledJSON)
    #expect(try await engine.runMessage("the textStyle of char 1 to 2 of field \"Styled\"") == "plain")
    #expect(try await engine.runMessage("the textStyle of char 3 to 4 of field \"Styled\"") == "bold")
    #expect(try await engine.runMessage("the textStyle of char 3 of field \"Styled\"") == "bold")
}

@Test func textStyleOfMixedChunkIsMixed() async throws {
    let engine = try StackEngine(stackJSON: styledJSON)
    #expect(try await engine.runMessage("the textStyle of char 1 to 6 of field \"Styled\"") == "mixed")
}

@Test func textSizeOfChunk() async throws {
    let engine = try StackEngine(stackJSON: styledJSON)
    #expect(try await engine.runMessage("the textSize of char 3 of field \"Styled\"") == "18")
    #expect(try await engine.runMessage("the textSize of char 1 of field \"Styled\"") == "12")
}

@Test func textStyleOfLineChunk() async throws {
    // Power Tools' idiom: `the textStyle of line N of bg field`.
    let engine = try StackEngine(stackJSON: styledJSON)
    // The whole field is one line; chars span plain+bold+plain → mixed.
    #expect(try await engine.runMessage("the textStyle of line 1 of field \"Styled\"") == "mixed")
}

@Test func bareTextStyleOfChunkWithoutThe() async throws {
    // No leading `the` — Power Tools writes `if (textStyle of line count of …)`.
    let engine = try StackEngine(stackJSON: styledJSON)
    #expect(try await engine.runMessage("textStyle of char 1 to 2 of field \"Styled\"") == "plain")
}
