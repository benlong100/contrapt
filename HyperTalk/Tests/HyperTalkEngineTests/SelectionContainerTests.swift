//
//  SelectionContainerTests.swift
//  HyperTalkEngine
//
//  `put … into/after/before the selection` — the selected text as a writable
//  container (Meal Time's `put empty into the selection`). Replacing resolves
//  to the selected field and character range.
//

import Foundation
import Testing
@testable import HyperTalkEngine

private let fieldJSON = """
{
  "formatVersion": 1, "id": "00000000-0000-0000-0000-0000000000SC",
  "name": "Sel", "cardSize": { "width": 512, "height": 342 }, "script": "", "nextID": 100,
  "backgrounds": [ { "id": "00000000-0000-0000-0000-000000000001", "name": "BG", "script": "", "scriptID": 1, "parts": [] } ],
  "cards": [
    {
      "id": "00000000-0000-0000-0000-000000000010", "name": "Card 1",
      "backgroundID": "00000000-0000-0000-0000-000000000001", "scriptID": 10,
      "parts": [ { "id": "00000000-0000-0000-0000-000000000020", "name": "N", "scriptID": 20,
        "visible": true, "type": "field", "frame": { "x": 10, "y": 10, "width": 120, "height": 40 },
        "field": { "format": { "align": "left", "fontDesign": "standard", "isBold": false, "isItalic": false, "isUnderline": false, "size": 12 },
          "isMultiline": true, "kind": "plain", "lockText": false, "placeholder": "", "showLines": false, "style": "transparent", "text": "Hello", "wideMargins": false } } ],
      "script": "\(handler)"
    }
  ]
}
"""

private let handler = """
on replaceSel\\nselect char 1 to 2 of field \\"N\\"\\nput \\"J\\" into the selection\\nput field \\"N\\" into message\\nend replaceSel\\n\\non appendSel\\nselect char 1 to 2 of field \\"N\\"\\nput \\"X\\" after the selection\\nput field \\"N\\" into message\\nend appendSel\\n\\non emptySel\\nselect char 1 to 2 of field \\"N\\"\\nput empty into the selection\\nput field \\"N\\" into message\\nend emptySel
"""

@Test func putIntoSelectionReplaces() async throws {
    let e = try StackEngine(stackJSON: Data(fieldJSON.utf8))
    _ = try await e.runMessage("replaceSel")
    #expect(e.drainEffects().contains(.message("Jllo"))) // "He" → "J"
}

@Test func putAfterSelectionInserts() async throws {
    let e = try StackEngine(stackJSON: Data(fieldJSON.utf8))
    _ = try await e.runMessage("appendSel")
    #expect(e.drainEffects().contains(.message("HeXllo"))) // after "He"
}

@Test func putEmptyIntoSelectionDeletes() async throws {
    let e = try StackEngine(stackJSON: Data(fieldJSON.utf8))
    _ = try await e.runMessage("emptySel")
    #expect(e.drainEffects().contains(.message("llo"))) // "He" removed
}
