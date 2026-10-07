//
//  GenericPartTests.swift
//  HyperTalkEngine
//
//  The object-model rework's generic `part N`: a part addressed by z-order
//  across kinds (`cd part 2`, `the rect of cd part i`, `last cd part`), matching
//  the set `the number of card parts` counts. Color Tools' idiom:
//    repeat with cdpts = number of cd parts down to 1
//      if (mLoc is within the rect of cd part cdpts) then …
//

import Foundation
import Testing
@testable import HyperTalkEngine

/// One card with three parts in z-order: button "Alpha", field "Beta",
/// button "Gamma".
private let mixedPartsJSON = """
{
  "formatVersion": 1, "id": "00000000-0000-0000-0000-0000000000AA",
  "name": "Parts", "cardSize": { "width": 512, "height": 342 }, "script": "", "nextID": 100,
  "backgrounds": [ { "id": "00000000-0000-0000-0000-000000000001", "name": "BG", "script": "", "scriptID": 1, "parts": [] } ],
  "cards": [
    {
      "id": "00000000-0000-0000-0000-000000000010", "name": "Card 1",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 10, "script": "",
      "parts": [
        {
          "id": "00000000-0000-0000-0000-000000000021", "name": "Alpha", "scriptID": 21,
          "frame": { "x": 10, "y": 10, "width": 80, "height": 30 }, "script": "",
          "type": "button", "button": { "title": "Alpha" }
        },
        {
          "id": "00000000-0000-0000-0000-000000000022", "name": "Beta", "scriptID": 22,
          "visible": true, "script": "", "type": "field",
          "frame": { "x": 10, "y": 50, "width": 120, "height": 40 },
          "field": { "format": { "align": "left", "fontDesign": "standard", "isBold": false,
                                 "isItalic": false, "isUnderline": false, "size": 12 },
                     "isMultiline": true, "kind": "plain", "lockText": false, "placeholder": "",
                     "showLines": false, "style": "transparent", "text": "", "wideMargins": false }
        },
        {
          "id": "00000000-0000-0000-0000-000000000023", "name": "Gamma", "scriptID": 23,
          "frame": { "x": 10, "y": 100, "width": 80, "height": 30 }, "script": "",
          "type": "button", "button": { "title": "Gamma" }
        }
      ]
    }
  ]
}
""".data(using: .utf8)!

@Test func numberOfCardParts() async throws {
    let engine = try StackEngine(stackJSON: mixedPartsJSON)
    #expect(try await engine.runMessage("the number of card parts") == "3")
}

@Test func genericPartByZOrderCrossesKinds() async throws {
    let engine = try StackEngine(stackJSON: mixedPartsJSON)
    // part 1 = button Alpha, part 2 = field Beta, part 3 = button Gamma.
    #expect(try await engine.runMessage("the short name of cd part 1") == "Alpha")
    #expect(try await engine.runMessage("the short name of cd part 2") == "Beta")
    #expect(try await engine.runMessage("the short name of cd part 3") == "Gamma")
}

@Test func lastCardPartIsTheTopmost() async throws {
    let engine = try StackEngine(stackJSON: mixedPartsJSON)
    #expect(try await engine.runMessage("the short name of last cd part") == "Gamma")
}

@Test func rectOfGenericPartResolves() async throws {
    let engine = try StackEngine(stackJSON: mixedPartsJSON)
    // Color Tools reads `the rect of cd part i` in a hit-test loop.
    #expect(try await engine.runMessage("the rect of cd part 2") == "10,50,130,90")
}
