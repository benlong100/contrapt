//
//  WebRenderStateTests.swift
//  HyperTalkEngine
//
//  The state-driven web renderer's contract: CardState carries the live
//  card's full parts (stack.json shape) and its background overlay, so the
//  exported player can build script-CREATED cards and parts — which the
//  static stack doesn't contain — with its one renderPart.
//

import Foundation
import Testing
@testable import HyperTalkEngine

private let bg = "22222222-2222-2222-2222-222222222222"
private func field(_ id: Int, _ name: String) -> String {
    """
    { "id": "44444444-4444-4444-4444-4444444444\(String(format: "%02d", id))", "name": "\(name)",
      "scriptID": \(id), "visible": true, "type": "field",
      "frame": { "x": 10, "y": \(id), "width": 200, "height": 30 }, "script": "",
      "field": { "format": { "align": "left", "fontDesign": "standard", "isBold": false,
                  "isItalic": false, "isUnderline": false, "size": 17 },
                 "isMultiline": false, "kind": "plain", "lockText": false, "placeholder": "",
                 "showLines": false, "style": "rectangle", "text": "", "wideMargins": false,
                 "sharedText": false } }
    """
}
private let renderJSON = """
{
  "formatVersion": 1, "id": "11111111-1111-1111-1111-1111111100FF",
  "name": "Render", "cardSize": {"width": 400, "height": 300}, "script": "", "nextID": 100,
  "backgrounds": [
    { "id": "\(bg)", "name": "Story", "script": "", "scriptID": 1,
      "parts": [\(field(20, "title")), \(field(21, "text"))] }
  ],
  "cards": [
    { "id": "33333333-3333-3333-3333-333333333331", "name": "Home", "scriptID": 10,
      "backgroundID": "\(bg)", "script": "", "parts": [] }
  ]
}
""".data(using: .utf8)!

@Test func existingCardStateCarriesFullPartsForRebuild() async throws {
    let engine = try StackEngine(stackJSON: renderJSON)
    let state = engine.currentCardState()
    // The background's two fields are present in full (stack.json) shape, so
    // the player can render the card from state alone.
    #expect(state.backgroundID == bg)
    let names = Set(state.backgroundPartsFull.compactMap { part -> String? in
        if case .field = part.kind { return part.name } else { return nil }
    })
    #expect(names == ["title", "text"])
}

@Test func createdCardsAndFieldsAppearInState() async throws {
    let engine = try StackEngine(stackJSON: renderJSON)
    // A merge makes two new cards and fills the background fields per card.
    _ = try await engine.runMessage("""
    put "First Story" into stories[1]["title"]
    put "First body" into stories[1]["text"]
    put "Second Story" into stories[2]["title"]
    make a card for each element of stories using background "Story"
    """)
    #expect(engine.cardCount == 3)
    // Card 2 (index 1) is script-created — not in the exported static stack —
    // yet its state is fully renderable: the background fields and this card's
    // text for them.
    let s = engine.cardState(at: 1)
    #expect(s.cardCount == 3)
    #expect(s.backgroundID == bg)
    #expect(s.backgroundPartsFull.count == 2)                 // the two bg fields
    #expect(s.backgroundFieldContent.values.contains { $0.text == "First Story" })
    #expect(s.backgroundFieldContent.values.contains { $0.text == "First body" })
    // The third card carries the second story and an empty body.
    let third = engine.cardState(at: 2)
    #expect(third.backgroundFieldContent.values.contains { $0.text == "Second Story" })
}
