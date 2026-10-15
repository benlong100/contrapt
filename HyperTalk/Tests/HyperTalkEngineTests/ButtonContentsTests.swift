//
//  ButtonContentsTests.swift
//  HyperTalkEngine
//
//  HyperCard 2.x button CONTENTS: text stored on a button (popup lists, the
//  10th Anniversary slide lists). A bare `btn "X"` in an expression reads it;
//  `put … into btn "X"` writes it; `the contents of btn` reads it by name.
//

import Foundation
import Testing
@testable import HyperTalkEngine

private let contentsJSON = """
{
  "formatVersion": 1, "id": "00000000-0000-0000-0000-0000000000C7",
  "name": "Covers", "cardSize": {"width": 512, "height": 342},
  "script": "", "nextID": 100,
  "backgrounds": [
    { "id": "00000000-0000-0000-0000-000000000001", "name": "BG", "script": "", "scriptID": 1, "parts": [] }
  ],
  "cards": [
    { "id": "00000000-0000-0000-0000-000000000010", "name": "One",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 10, "script": "",
      "parts": [
        { "id": "44444444-4444-4444-4444-4444444400c1", "name": "cover1", "scriptID": 5,
          "visible": true, "type": "button",
          "frame": { "x": 10, "y": 10, "width": 60, "height": 20 }, "script": "",
          "button": { "autoHilite": false, "hilite": false, "showName": true,
                      "style": "transparent", "title": "cover1", "family": 0,
                      "contents": "pict one\\npict two\\npict three",
                      "format": { "align": "center", "fontDesign": "standard", "isBold": false,
                                  "isItalic": false, "isUnderline": false, "size": 17 } } }
      ] }
  ]
}
""".data(using: .utf8)!

@Test func buttonContentsReadAndWrite() async throws {
    let engine = try StackEngine(stackJSON: contentsJSON)
    // Bare button-as-value reads the contents (the slideShow idiom).
    _ = try await engine.runMessage("put btn \"cover1\" into msg")
    #expect(engine.drainEffects().contains(.message("pict one\npict two\npict three")))
    #expect(try await engine.runMessage("the number of lines in btn \"cover1\"") == "3")
    #expect(try await engine.runMessage("the contents of btn \"cover1\"") == "pict one\npict two\npict three")
    // Writing replaces it.
    _ = try await engine.runMessage("put \"fresh\" into btn \"cover1\"")
    #expect(try await engine.runMessage("btn \"cover1\"") == "fresh")
    _ = try await engine.runMessage("put empty into btn \"cover1\"")
    #expect(try await engine.runMessage("the contents of btn \"cover1\"") == "")
}
