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

@Test func typeInsertsAtTheScriptSelection() async throws {
    // `select after text of field` + `type` — the data-entry idiom. The typed
    // text lands at the caret; a selected range is replaced.
    let engine = try StackEngine(stackJSON: parityJSON)
    _ = try await engine.runMessage("put \"abc\" into card field \"List\"")
    _ = try await engine.runMessage("select after text of card field \"List\"")
    _ = try await engine.runMessage("type \"XY\"")
    #expect(engine.fieldText(named: "List") == "abcXY")
    _ = try await engine.runMessage("select char 1 to 3 of card field \"List\"")
    _ = try await engine.runMessage("type \"Z\"")
    #expect(engine.fieldText(named: "List") == "ZXY")
    // `type … with commandKey` is a shortcut, not text — accepted, no insert.
    _ = try await engine.runMessage("type \"v\" with commandKey")
    #expect(engine.fieldText(named: "List") == "ZXY")
}

@Test func homePreferencesEnvironmentGlobalsRoundTrip() async throws {
    // The Home stack's Preferences card: set userLevel then read it and the
    // typing flags back to drive hilites. Reading `the textArrows` used to
    // echo "textarrows" and blow up `set hilite … to <that>` (reported as
    // line 18 of the card script).
    let engine = try StackEngine(stackJSON: parityJSON)
    #expect(try await engine.runMessage("the userLevel") == "5")
    _ = try await engine.runMessage("set userLevel to 3")
    #expect(try await engine.runMessage("the userLevel") == "3")
    #expect(try await engine.runMessage("the userLevel = 3") == "true")
    _ = try await engine.runMessage("set userLevel to 99") // clamps 1…5
    #expect(try await engine.runMessage("the userLevel") == "5")
    #expect(try await engine.runMessage("the textArrows") == "false")
    _ = try await engine.runMessage("set the textArrows to true")
    #expect(try await engine.runMessage("the textArrows") == "true")
    // The crash line's exact shape now evaluates to a boolean.
    _ = try await engine.runMessage("set hilite of card button \"Go\" to the textArrows")
    #expect(try await engine.runMessage("the hilite of card button \"Go\"") == "true")
    _ = try await engine.runMessage("set the powerKeys to true")
    _ = try await engine.runMessage("set the blindTyping to false")
    #expect(try await engine.runMessage("the powerKeys & the blindTyping") == "truefalse")
}

@Test func hilightIsAHiliteSynonym() async throws {
    // HyperCard accepts hilite / hilight / highlight interchangeably; a stack
    // using `set the hilight of button …` (reported as card 5 line 9) must
    // not error.
    let engine = try StackEngine(stackJSON: parityJSON)
    #expect(try await engine.runMessage("the hilight of card button \"Go\"") == "false")
    _ = try await engine.runMessage("set the hilight of card button \"Go\" to true")
    #expect(try await engine.runMessage("the hilite of card button \"Go\"") == "true")
    #expect(try await engine.runMessage("the autoHilight of card button \"Go\"") != nil)
}

@Test func classicFontNamesMapInsteadOfErroring() async throws {
    // `set the textFont of field … to Chicago` (and other classic Mac fonts)
    // must not error — HyperCard names real faces; we map each to the nearest
    // design and read it back, and an unknown font falls back to system.
    let engine = try StackEngine(stackJSON: parityJSON)
    _ = try await engine.runMessage("set the textFont of card field \"List\" to Chicago")
    #expect(try await engine.runMessage("the textFont of card field \"List\"") == "standard")
    _ = try await engine.runMessage("set the textFont of card field \"List\" to Palatino")
    #expect(try await engine.runMessage("the textFont of card field \"List\"") == "serif")
    _ = try await engine.runMessage("set the textFont of card field \"List\" to Monaco")
    #expect(try await engine.runMessage("the textFont of card field \"List\"") == "monospaced")
    // An unknown face doesn't throw — becomes the system font.
    _ = try await engine.runMessage("set the textFont of card field \"List\" to Flibbertigibbet")
    #expect(try await engine.runMessage("the textFont of card field \"List\"") == "standard")
}

@Test func textHeightPropertyRoundTrips() async throws {
    // `the textHeight of field` reads/writes a field's line height (0 = the
    // font's natural height) — Hyper-Wordle, HyperCard 10th Anniversary.
    let engine = try StackEngine(stackJSON: parityJSON)
    #expect(try await engine.runMessage("the textHeight of card field \"List\"") == "0")
    _ = try await engine.runMessage("set the textHeight of card field \"List\" to 18")
    #expect(try await engine.runMessage("the textHeight of card field \"List\"") == "18")
    _ = try await engine.runMessage("set the textHeight of card field \"List\" to 0")
    #expect(try await engine.runMessage("the textHeight of card field \"List\"") == "0")
}
