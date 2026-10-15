//
//  FamilyTests.swift
//  HyperTalkEngine
//
//  HyperCard button families — the radio-group mechanism. Clicking an
//  autoHilite member hilites it and clears its same-layer, same-family
//  siblings; card and background families are distinct namespaces (the
//  HyperCard Help stack's own rule); `the selectedButton of family N
//  [of <card>]` reads the hilited member. Corpus users: What is
//  HyperCard?, New Features, HyperCard Help, 10th Anniversary.
//

import Foundation
import Testing
@testable import HyperTalkEngine

private func button(_ id: Int, _ name: String, style: String, family: Int, hilite: Bool = false) -> String {
    """
    { "id": "44444444-4444-4444-4444-4444444444\(String(format: "%02d", id))", "name": "\(name)",
      "scriptID": \(id), "visible": true, "type": "button",
      "frame": { "x": 10, "y": \(id * 40), "width": 120, "height": 30 }, "script": "",
      "button": { "autoHilite": true, "format": { "align": "left", "fontDesign": "standard",
                  "isBold": false, "isItalic": false, "isUnderline": false, "size": 17 },
                  "hilite": \(hilite), "showName": true, "style": "\(style)", "title": "\(name)",
                  "family": \(family) } }
    """
}

private let familyJSON = """
{
  "formatVersion": 1, "id": "11111111-1111-1111-1111-111111110F0F",
  "name": "Families", "cardSize": {"width": 400, "height": 300},
  "script": "", "nextID": 100,
  "backgrounds": [
    { "id": "22222222-2222-2222-2222-222222222222", "name": "BG", "script": "", "scriptID": 1,
      "parts": [\(button(60, "BgOpt", style: "radio", family: 1))] }
  ],
  "cards": [
    { "id": "33333333-3333-3333-3333-333333333331", "name": "Home", "scriptID": 10,
      "backgroundID": "22222222-2222-2222-2222-222222222222", "script": "",
      "parts": [\(button(40, "Red", style: "radio", family: 1)),
                \(button(41, "Blue", style: "radio", family: 1)),
                \(button(42, "Tab", style: "rectangle", family: 2)),
                \(button(43, "Agree", style: "checkbox", family: 0))] },
    { "id": "33333333-3333-3333-3333-333333333332", "name": "Two", "scriptID": 11,
      "backgroundID": "22222222-2222-2222-2222-222222222222", "script": "", "parts": [] }
  ]
}
""".data(using: .utf8)!

private func hilite(_ engine: StackEngine, _ scriptID: Int) -> Bool? {
    (engine.currentCardState().cardParts + engine.currentCardState().backgroundParts)
        .first { $0.scriptID == scriptID }?.hilite
}

@Test func familyClicksAreMutuallyExclusiveWithinTheLayer() async throws {
    let engine = try StackEngine(stackJSON: familyJSON)
    _ = try await engine.dispatchMouseUp(partScriptID: 40) // Red
    #expect(hilite(engine, 40) == true)
    _ = try await engine.dispatchMouseUp(partScriptID: 41) // Blue
    #expect(hilite(engine, 41) == true)
    #expect(hilite(engine, 40) == false)
    // Other families and the background's family 1 are untouched.
    #expect(hilite(engine, 42) == false)
    #expect(hilite(engine, 60) == false)
    // Re-clicking the selected member keeps it selected (radio, not toggle).
    _ = try await engine.dispatchMouseUp(partScriptID: 41)
    #expect(hilite(engine, 41) == true)
}

@Test func familyWorksOnAnyStyleAndFamilylessTogglesStillFlip() async throws {
    let engine = try StackEngine(stackJSON: familyJSON)
    // A rectangle "tab" button in a family latches like a radio.
    _ = try await engine.dispatchMouseUp(partScriptID: 42)
    #expect(hilite(engine, 42) == true)
    // The family-less checkbox keeps its flip behavior.
    _ = try await engine.dispatchMouseUp(partScriptID: 43)
    #expect(hilite(engine, 43) == true)
    _ = try await engine.dispatchMouseUp(partScriptID: 43)
    #expect(hilite(engine, 43) == false)
}

@Test func selectedButtonOfFamilyReads() async throws {
    let engine = try StackEngine(stackJSON: familyJSON)
    // Nothing selected yet.
    #expect(try await engine.runMessage("the selectedButton of family 1") == "")
    _ = try await engine.dispatchMouseUp(partScriptID: 41) // Blue, 2nd button
    #expect(try await engine.runMessage("the selectedButton of family 1") == "card button 2")
    // Card-scoped read from another card (New Features' exact idiom).
    _ = try await engine.openCard(index: 1)
    #expect(try await engine.runMessage("the selectedButton of family 1 of card 1") == "card button 2")
    // The background family is a distinct namespace.
    _ = try await engine.openCard(index: 0)
    #expect(try await engine.runMessage("the selectedButton of bkgnd family 1") == "")
    _ = try await engine.dispatchMouseUp(partScriptID: 60)
    #expect(try await engine.runMessage("the selectedButton of bkgnd family 1") == "bkgnd button 1")
}

@Test func familyPropertyReadsAndWrites() async throws {
    let engine = try StackEngine(stackJSON: familyJSON)
    #expect(try await engine.runMessage("the family of button \"Red\"") == "1")
    #expect(try await engine.runMessage("the family of button \"Agree\"") == "0")
    _ = try await engine.runMessage("set the family of button \"Agree\" to 3")
    #expect(try await engine.runMessage("the family of button \"Agree\"") == "3")
    await #expect(throws: (any Error).self) {
        _ = try await engine.runMessage("set the family of button \"Agree\" to 99")
    }
}

@Test func familyExistence() async throws {
    let engine = try StackEngine(stackJSON: familyJSON)
    _ = try await engine.runMessage("put (there is a family 1) & \" \" & (there is a family 9) into msg")
    #expect(engine.drainEffects().contains(.message("true false")))
}

@Test func settingHiliteByScriptClearsFamilySiblings() async throws {
    // HyperCard's family rule applies to SCRIPT sets too, not just clicks —
    // What is HyperCard?'s topic buttons depend on it (each card's openCard
    // does `set the hilite of bkgnd btn <topic> to true` and nothing ever
    // clears the previous one by hand; the stack file even ships with one
    // button hilited, so without this rule two stay lit until a click).
    let engine = try StackEngine(stackJSON: familyJSON)
    _ = try await engine.runMessage("set the hilite of button \"Red\" to true")
    #expect(hilite(engine, 40) == true)
    _ = try await engine.runMessage("set the hilite of button \"Blue\" to true")
    #expect(hilite(engine, 41) == true)
    #expect(hilite(engine, 40) == false)   // sibling cleared by the set
    // Setting a member FALSE clears only itself.
    _ = try await engine.runMessage("set the hilite of button \"Blue\" to false")
    #expect(hilite(engine, 41) == false)
    #expect(hilite(engine, 40) == false)
    // The background's family 1 is a separate namespace — untouched.
    _ = try await engine.runMessage("set the hilite of button \"Red\" to true")
    #expect(hilite(engine, 60) == nil || hilite(engine, 60) == false)
}
