//
//  WebParityStateTests.swift
//  The web-parity batch: CardState carries what the page renders live —
//  enabled, field scroll, showPicture, the scripted menus, and the
//  card-window viewport.
//

import Foundation
import Testing
@testable import HyperTalkEngine

private let parityJSON = """
{
  "formatVersion": 1, "id": "11111111-1111-1111-1111-111111111111",
  "name": "Parity", "cardSize": {"width": 400, "height": 300}, "script": "",
  "backgrounds": [
    { "id": "22222222-2222-2222-2222-222222222222", "name": "BG", "script": "", "parts": [] }
  ],
  "cards": [
    { "id": "33333333-3333-3333-3333-333333333333", "name": "C1",
      "backgroundID": "22222222-2222-2222-2222-222222222222", "script": "",
      "parts": [
        { "id": "44444444-4444-4444-4444-444444444444", "name": "Go",
          "frame": {"x": 10, "y": 10, "width": 80, "height": 24}, "script": "",
          "scriptID": 7, "type": "button",
          "button": {"title": "Go", "showName": true, "autoHilite": true,
                     "style": "roundRect", "hilite": false, "format": {}} },
        { "id": "55555555-5555-5555-5555-555555555555", "name": "List",
          "frame": {"x": 10, "y": 50, "width": 120, "height": 90}, "script": "",
          "scriptID": 8, "type": "field",
          "field": {"text": "a\\nb\\nc", "placeholder": "", "style": "scrolling",
                    "lockText": true, "format": {}} }
      ] }
  ]
}
""".data(using: .utf8)!

@Test func cardStateCarriesWebParityBits() async throws {
    let engine = try StackEngine(stackJSON: parityJSON)
    _ = try await engine.runMessage("disable card button \"Go\"")
    _ = try await engine.runMessage("set the scroll of card field \"List\" to 40")
    _ = try await engine.runMessage("hide picture of this card")
    _ = try await engine.runMessage("create menu \"Game\"")
    _ = try await engine.runMessage("put \"Start,Quit\" into menu \"Game\"")
    _ = try await engine.runMessage("set the rect of card window to \"0,0,200,150\"")

    let state = engine.currentCardState()
    let button = state.cardParts.first { $0.scriptID == 7 }
    let field = state.cardParts.first { $0.scriptID == 8 }
    #expect(button?.enabled == false)
    #expect(field?.scroll == 40)
    #expect(state.cardShowPicture == false)
    #expect(state.backgroundShowPicture == true)
    #expect(state.menus.map(\.name) == ["Game"])
    #expect(state.menus.first?.items.map(\.name) == ["Start", "Quit"])
    #expect(state.viewportWidth == 200)
    #expect(state.viewportHeight == 150)

    // Reading back through scripts agrees, and clearing the viewport clears it.
    #expect(try await engine.runMessage("the enabled of card button \"Go\"") == "false")
    #expect(try await engine.runMessage("the scroll of card field \"List\"") == "40")
    _ = try await engine.runMessage("set the rect of card window to \"0,0,400,300\"")
    #expect(engine.currentCardState().viewportWidth == nil)
}
