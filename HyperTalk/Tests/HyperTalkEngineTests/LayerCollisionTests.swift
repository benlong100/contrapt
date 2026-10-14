//
//  LayerCollisionTests.swift
//  HyperTalkEngine
//
//  HyperCard numbers card parts and background parts in SEPARATE id spaces, so
//  a card-layer button and a background button can legitimately share a
//  scriptID — e.g. a demo button drawn over a shared background nav button
//  (What is HyperCard?'s "Buttons" card: card "Radio Button" id 4 sits on the
//  same card as background "Introduction" id 4). A web click carries which
//  layer it hit; the engine must route the mouseUp to THAT layer's part, not
//  whichever layer it searches first. Regression for nav buttons going dead on
//  the one card that carries colliding card parts.
//

import Foundation
import Testing
@testable import HyperTalkEngine

// Background button id 4 navigates; a card button id 4 on card "One" does not.
private let collisionJSON = """
{
  "formatVersion": 1, "id": "11111111-1111-1111-1111-1111111111cc",
  "name": "Collide", "cardSize": {"width": 400, "height": 300},
  "script": "", "nextID": 100,
  "backgrounds": [
    { "id": "22222222-2222-2222-2222-2222222222bb", "name": "BG", "script": "", "scriptID": 1,
      "parts": [
        { "id": "44444444-4444-4444-4444-4444444400b0", "name": "NavBtn", "scriptID": 4,
          "visible": true, "type": "button",
          "frame": { "x": 10, "y": 10, "width": 120, "height": 30 },
          "script": "on mouseUp\\ngo card \\"Two\\"\\nend mouseUp",
          "button": { "autoHilite": false, "hilite": false, "showName": true,
                      "style": "transparent", "title": "NavBtn", "family": 0,
                      "format": { "align": "left", "fontDesign": "standard", "isBold": false,
                                  "isItalic": false, "isUnderline": false, "size": 17 } } }
      ] }
  ],
  "cards": [
    { "id": "33333333-3333-3333-3333-333333330001", "name": "One", "scriptID": 10,
      "backgroundID": "22222222-2222-2222-2222-2222222222bb", "script": "",
      "parts": [
        { "id": "44444444-4444-4444-4444-4444444400cd", "name": "Demo", "scriptID": 4,
          "visible": true, "type": "button",
          "frame": { "x": 150, "y": 10, "width": 120, "height": 30 },
          "script": "on mouseUp\\nput \\"card-ran\\" into msg\\nend mouseUp",
          "button": { "autoHilite": false, "hilite": false, "showName": true,
                      "style": "transparent", "title": "Demo", "family": 0,
                      "format": { "align": "left", "fontDesign": "standard", "isBold": false,
                                  "isItalic": false, "isUnderline": false, "size": 17 } } }
      ] },
    { "id": "33333333-3333-3333-3333-333333330002", "name": "Two", "scriptID": 11,
      "backgroundID": "22222222-2222-2222-2222-2222222222bb", "script": "", "parts": [] }
  ]
}
""".data(using: .utf8)!

@Test func clickOnBackgroundButtonRunsItsScriptDespiteCardCollision() async throws {
    let engine = try StackEngine(stackJSON: collisionJSON)
    #expect(engine.currentCardState().cardIndex == 0)
    // The background "NavBtn" (id 4) must navigate, even though card "Demo"
    // (id 4) is searched first. Before the layer hint, this did nothing.
    _ = try await engine.dispatchMouseUp(partScriptID: 4, partLayer: "bkgnd")
    #expect(engine.currentCardState().cardIndex == 1)
}

@Test func clickOnCardButtonRunsItsScriptDespiteBackgroundCollision() async throws {
    let engine = try StackEngine(stackJSON: collisionJSON)
    let effects = try await engine.dispatchMouseUp(partScriptID: 4, partLayer: "card")
    #expect(engine.currentCardState().cardIndex == 0)   // card button doesn't navigate
    #expect(effects.contains(.message("card-ran")))
}
