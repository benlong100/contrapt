//
//  IconSymbolRoundTripTests.swift
//  HyperTalkEngine
//
//  An SF-symbol button icon must survive the engine's decode→encode cycle: the
//  web player's state-driven render (buildLayerFromState) reads cardPartsFull as
//  JSON encoded by Part/ButtonPart, so if ButtonPart drops iconSymbol the button
//  renders with no icon on any engine-rendered card (regression: Home stack's
//  house / arrowshape nav buttons showed nothing on the web).
//

import Foundation
import Testing
@testable import HyperTalkEngine

private let symbolStackJSON = """
{
  "formatVersion": 1, "id": "11111111-1111-1111-1111-1111111111c0",
  "name": "Symbols", "cardSize": {"width": 400, "height": 300},
  "script": "", "nextID": 100,
  "backgrounds": [
    { "id": "22222222-2222-2222-2222-2222222222bb", "name": "BG", "script": "", "scriptID": 1, "parts": [] }
  ],
  "cards": [
    { "id": "33333333-3333-3333-3333-333333330001", "name": "One", "scriptID": 10,
      "backgroundID": "22222222-2222-2222-2222-2222222222bb", "script": "",
      "parts": [
        { "id": "44444444-4444-4444-4444-4444444400a0", "name": "Home", "scriptID": 7,
          "visible": true, "type": "button",
          "frame": { "x": 10, "y": 10, "width": 40, "height": 40 }, "script": "",
          "button": { "autoHilite": false, "hilite": false, "showName": false,
                      "style": "transparent", "title": "", "family": 0, "iconSymbol": "house",
                      "format": { "align": "center", "fontDesign": "standard", "isBold": false,
                                  "isItalic": false, "isUnderline": false, "size": 17 } } }
      ] }
  ]
}
""".data(using: .utf8)!

@Test func iconSymbolSurvivesEngineJSONRoundTrip() async throws {
    let engine = try StackEngine(stackJSON: symbolStackJSON)
    let state = engine.currentCardState()
    // cardPartsFull is what buildLayerFromState renders — encode it as the player
    // receives it and confirm the symbol name is present.
    let json = try JSONEncoder().encode(state.cardPartsFull)
    let text = String(decoding: json, as: UTF8.self)
    #expect(text.contains("\"iconSymbol\""))
    #expect(text.contains("house"))
}
