//
//  BackgroundFieldStateTests.swift
//  HyperTalkEngine
//
//  A non-sharedText background field stores its text PER CARD in
//  Card.backgroundFieldContent — and CardState must merge that overlay, or
//  the page blanks every such field the moment the engine's first state
//  arrives (found by Ben in the imported What is HyperCard? stack: the
//  Introduction text vanished on the web).
//

import Foundation
import Testing
@testable import HyperTalkEngine

private let overlayJSON = """
{
  "formatVersion": 1, "id": "11111111-1111-1111-1111-1111111100AA",
  "name": "Overlay", "cardSize": {"width": 512, "height": 342},
  "script": "", "nextID": 100,
  "backgrounds": [
    { "id": "22222222-2222-2222-2222-222222222222", "name": "BG", "script": "", "scriptID": 1,
      "parts": [
        { "id": "55555555-5555-5555-5555-555555555551", "name": "Page", "scriptID": 20,
          "visible": true, "type": "field",
          "frame": { "x": 10, "y": 10, "width": 300, "height": 200 }, "script": "",
          "field": { "format": { "align": "left", "fontDesign": "standard", "isBold": false,
                      "isItalic": false, "isUnderline": false, "size": 17 },
                     "isMultiline": true, "kind": "plain", "lockText": true, "placeholder": "",
                     "showLines": false, "style": "transparent", "text": "", "wideMargins": false,
                     "sharedText": false } },
        { "id": "55555555-5555-5555-5555-555555555552", "name": "Shared", "scriptID": 21,
          "visible": true, "type": "field",
          "frame": { "x": 10, "y": 220, "width": 300, "height": 40 }, "script": "",
          "field": { "format": { "align": "left", "fontDesign": "standard", "isBold": false,
                      "isItalic": false, "isUnderline": false, "size": 17 },
                     "isMultiline": false, "kind": "plain", "lockText": true, "placeholder": "",
                     "showLines": false, "style": "transparent", "text": "same everywhere",
                     "wideMargins": false, "sharedText": true } }
      ] }
  ],
  "cards": [
    { "id": "33333333-3333-3333-3333-333333333331", "name": "One", "scriptID": 10,
      "backgroundID": "22222222-2222-2222-2222-222222222222", "script": "", "parts": [],
      "backgroundFieldContent": { "55555555-5555-5555-5555-555555555551": { "text": "Welcome to HyperCard!" } } },
    { "id": "33333333-3333-3333-3333-333333333332", "name": "Two", "scriptID": 11,
      "backgroundID": "22222222-2222-2222-2222-222222222222", "script": "", "parts": [],
      "backgroundFieldContent": { "55555555-5555-5555-5555-555555555551": { "text": "Page two's text" } } }
  ]
}
""".data(using: .utf8)!

@Test func cardStateCarriesPerCardBackgroundFieldText() async throws {
    let engine = try StackEngine(stackJSON: overlayJSON)
    func pageText() -> String? {
        engine.currentCardState().backgroundParts.first { $0.scriptID == 20 }?.text
    }
    func sharedText() -> String? {
        engine.currentCardState().backgroundParts.first { $0.scriptID == 21 }?.text
    }
    #expect(pageText() == "Welcome to HyperCard!")
    #expect(sharedText() == "same everywhere")
    _ = try await engine.openCard(index: 1)
    #expect(pageText() == "Page two's text")
    #expect(sharedText() == "same everywhere")
    // A scripted write lands in the overlay and the state shows it.
    _ = try await engine.runMessage("put \"rewritten\" into field \"Page\"")
    #expect(pageText() == "rewritten")
    _ = try await engine.openCard(index: 0)
    #expect(pageText() == "Welcome to HyperCard!")
}
