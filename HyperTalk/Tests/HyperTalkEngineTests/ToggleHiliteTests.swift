//
//  ToggleHiliteTests.swift
//  HyperTalkEngine
//
//  A checkbox/radio click flips its hilite (the checked state) before
//  mouseUp dispatches — the app's CardView order, mirrored in the engine
//  so web checkboxes actually check.
//

import Foundation
import Testing
@testable import HyperTalkEngine

private let toggleJSON = """
{
  "formatVersion": 1, "id": "11111111-1111-1111-1111-11111111DDDD",
  "name": "Toggles", "cardSize": {"width": 400, "height": 300},
  "script": "", "nextID": 100,
  "backgrounds": [
    { "id": "22222222-2222-2222-2222-222222222222", "name": "BG", "script": "", "scriptID": 1, "parts": [] }
  ],
  "cards": [
    { "id": "33333333-3333-3333-3333-333333333331", "name": "Home", "scriptID": 10,
      "backgroundID": "22222222-2222-2222-2222-222222222222", "script": "",
      "parts": [
        { "id": "44444444-4444-4444-4444-444444444441", "name": "Agree", "scriptID": 40,
          "visible": true, "type": "button",
          "frame": { "x": 10, "y": 10, "width": 140, "height": 28 },
          "script": "on mouseUp\\nput the hilite of me into msg\\nend mouseUp",
          "button": { "autoHilite": true, "format": { "align": "left", "fontDesign": "standard",
                      "isBold": false, "isItalic": false, "isUnderline": false, "size": 17 },
                      "hilite": false, "showName": true, "style": "checkbox", "title": "Agree" } },
        { "id": "44444444-4444-4444-4444-444444444442", "name": "Go", "scriptID": 41,
          "visible": true, "type": "button",
          "frame": { "x": 10, "y": 50, "width": 140, "height": 28 },
          "script": "on mouseUp\\nif the hilite of button \\"Agree\\" is true then\\nput \\"agreed\\" into msg\\nelse\\nput \\"not yet\\" into msg\\nend if\\nend mouseUp",
          "button": { "autoHilite": true, "format": { "align": "center", "fontDesign": "standard",
                      "isBold": false, "isItalic": false, "isUnderline": false, "size": 17 },
                      "hilite": false, "showName": true, "style": "roundRect", "title": "Go" } }
      ] }
  ]
}
""".data(using: .utf8)!

@Test func checkboxClickFlipsItsHiliteBeforeMouseUp() async throws {
    let engine = try StackEngine(stackJSON: toggleJSON)
    let effects = try await engine.dispatchMouseUp(partScriptID: 40)
    // The script saw the NEW state — the flip happens before dispatch.
    #expect(effects.contains(.message("true")))
    #expect(engine.currentCardState().cardParts.first { $0.scriptID == 40 }?.hilite == true)
    // A second click unchecks.
    _ = try await engine.dispatchMouseUp(partScriptID: 40)
    #expect(engine.currentCardState().cardParts.first { $0.scriptID == 40 }?.hilite == false)
}

@Test func processButtonBranchesOnWhichCheckboxIsChecked() async throws {
    // Ben's exact web scenario: a named checkbox, and a button whose script
    // branches on `the hilite of button "Agree"` (the Go script in the JSON).
    let engine = try StackEngine(stackJSON: toggleJSON)
    // Unchecked: the else branch.
    var effects = try await engine.dispatchMouseUp(partScriptID: 41)
    #expect(effects.contains(.message("not yet")))
    // Check the box, click again: the then branch.
    _ = try await engine.dispatchMouseUp(partScriptID: 40)
    effects = try await engine.dispatchMouseUp(partScriptID: 41)
    #expect(effects.contains(.message("agreed")))
}

@Test func pushButtonsDoNotLatchHilite() async throws {
    let engine = try StackEngine(stackJSON: toggleJSON)
    _ = try await engine.dispatchMouseUp(partScriptID: 41)
    #expect(engine.currentCardState().cardParts.first { $0.scriptID == 41 }?.hilite == false)
}
