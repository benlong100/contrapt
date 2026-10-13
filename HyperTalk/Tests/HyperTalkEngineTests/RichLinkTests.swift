//
//  RichLinkTests.swift
//  HyperTalkEngine
//
//  `set the link of <chunk> of field … to <target>` and `the link of <chunk>`
//  — scriptable links on RICH fields (the text is Markdown source; the chunk
//  range wraps/retargets/unwraps). Plain fields keep the group/clickText
//  idiom and refuse with a teaching error.
//

import Foundation
import Testing
@testable import HyperTalkEngine

private let richJSON = """
{
  "formatVersion": 1, "id": "11111111-1111-1111-1111-11111111BBBB",
  "name": "Links", "cardSize": {"width": 400, "height": 300},
  "script": "", "nextID": 100,
  "backgrounds": [
    { "id": "22222222-2222-2222-2222-222222222222", "name": "BG", "script": "", "scriptID": 1, "parts": [] }
  ],
  "cards": [
    { "id": "33333333-3333-3333-3333-333333333331", "name": "Home", "scriptID": 10,
      "backgroundID": "22222222-2222-2222-2222-222222222222", "script": "",
      "parts": [
        { "id": "44444444-4444-4444-4444-444444444441", "name": "Story", "scriptID": 40,
          "visible": true, "type": "field",
          "frame": { "x": 10, "y": 10, "width": 300, "height": 100 }, "script": "",
          "field": { "format": { "align": "left", "fontDesign": "standard", "isBold": false,
                      "isItalic": false, "isUnderline": false, "size": 17 },
                     "isMultiline": true, "kind": "rich", "lockText": true, "placeholder": "",
                     "showLines": false, "style": "rectangle",
                     "text": "Read the story today", "wideMargins": false } },
        { "id": "44444444-4444-4444-4444-444444444442", "name": "Plain", "scriptID": 41,
          "visible": true, "type": "field",
          "frame": { "x": 10, "y": 120, "width": 300, "height": 40 }, "script": "",
          "field": { "format": { "align": "left", "fontDesign": "standard", "isBold": false,
                      "isItalic": false, "isUnderline": false, "size": 17 },
                     "isMultiline": false, "kind": "plain", "lockText": false, "placeholder": "",
                     "showLines": false, "style": "rectangle", "text": "plain words", "wideMargins": false } }
      ] }
  ]
}
""".data(using: .utf8)!

@Test func settingTheLinkOfAChunkWrapsTheMarkdown() async throws {
    let engine = try StackEngine(stackJSON: richJSON)
    _ = try await engine.runMessage("set the link of word 2 to 3 of field \"Story\" to \"https://example.com\"")
    #expect(try await engine.runMessage("field \"Story\"") == "Read [the story](https://example.com) today")
}

@Test func readingTheLinkOfAChunk() async throws {
    let engine = try StackEngine(stackJSON: richJSON)
    _ = try await engine.runMessage("set the link of word 2 to 3 of field \"Story\" to \"card:Contents\"")
    _ = try await engine.runMessage("put the link of word 2 of field \"Story\" into msg")
    #expect(engine.drainEffects().contains(.message("card:Contents")))
}

@Test func settingInsideALinkRetargetsAndEmptyUnwraps() async throws {
    let engine = try StackEngine(stackJSON: richJSON)
    _ = try await engine.runMessage("set the link of word 2 to 3 of field \"Story\" to \"https://old.example\"")
    _ = try await engine.runMessage("set the link of word 3 of field \"Story\" to \"https://new.example\"")
    #expect(try await engine.runMessage("field \"Story\"") == "Read [the story](https://new.example) today")
    _ = try await engine.runMessage("set the link of word 3 of field \"Story\" to empty")
    #expect(try await engine.runMessage("field \"Story\"") == "Read the story today")
}

@Test func plainFieldsRefuseWithATeachingError() async throws {
    let engine = try StackEngine(stackJSON: richJSON)
    await #expect(throws: (any Error).self) {
        _ = try await engine.runMessage("set the link of word 1 of field \"Plain\" to \"https://example.com\"")
    }
    #expect(try await engine.runMessage("field \"Plain\"") == "plain words")
}
