//
//  ImportPictureTests.swift
//  HyperTalkEngine
//
//  `import picture from url … [into image <ref>]` through the web host: the
//  image part's source becomes the URL (the page's <img> fetches it); with
//  no target a new centered image part appears on the current card.
//

import Foundation
import Testing
@testable import HyperTalkEngine
@testable import HyperTalk

private let pictureJSON = """
{
  "formatVersion": 1, "id": "11111111-1111-1111-1111-11111111CCCC",
  "name": "Pics", "cardSize": {"width": 400, "height": 300},
  "script": "", "nextID": 100,
  "backgrounds": [
    { "id": "22222222-2222-2222-2222-222222222222", "name": "BG", "script": "", "scriptID": 1, "parts": [] }
  ],
  "cards": [
    { "id": "33333333-3333-3333-3333-333333333331", "name": "Home", "scriptID": 10,
      "backgroundID": "22222222-2222-2222-2222-222222222222", "script": "",
      "parts": [
        { "id": "44444444-4444-4444-4444-444444444441", "name": "Photo", "scriptID": 40,
          "visible": true, "type": "image",
          "frame": { "x": 10, "y": 10, "width": 100, "height": 80 }, "script": "",
          "image": { "assetName": "old.png" } }
      ] }
  ]
}
""".data(using: .utf8)!

@Test func importIntoAnExistingImagePartRetargetsIt() async throws {
    let engine = try StackEngine(stackJSON: pictureJSON)
    _ = try await engine.runMessage("import picture from url \"https://example.com/cat.png\" into image \"Photo\"")
    let photo = engine.currentCardState().cardParts.first { $0.scriptID == 40 }
    #expect(photo?.asset == "https://example.com/cat.png")
}

@Test func importWithoutATargetMakesANewImagePart() async throws {
    let engine = try StackEngine(stackJSON: pictureJSON)
    _ = try await engine.runMessage("""
    import picture from url "https://example.com/dog.jpg"
    put it into msg
    """)
    let state = engine.currentCardState()
    #expect(state.cardParts.filter { $0.kind == "image" }.count == 2)
    let made = state.cardParts.first { $0.asset == "https://example.com/dog.jpg" }
    #expect(made != nil)
    // `it` holds the new part's id, so `image id it` addresses it.
    if let made {
        #expect(engine.drainEffects().contains(.message(String(made.scriptID))))
    }
}

@Test func importIntoANonImagePartErrors() async throws {
    let engine = try StackEngine(stackJSON: pictureJSON)
    await #expect(throws: (any Error).self) {
        _ = try await engine.runMessage("import picture from url \"https://example.com/x.png\" into button \"Photo\"")
    }
}

@Test func classicImportPaintShapesStillParseAsMessages() throws {
    // HyperPatterns (real corpus stack) calls its own `import paint …`
    // handler — only the exact `import picture|paint from url` shape is a
    // command; everything else must stay a parseable message send.
    try HyperTalk.check("""
    on doImport
      import paint
      import paint from file "My Patterns"
    end doImport
    """)
}

@Test func customImportHandlerStillDispatches() async throws {
    // `import` is only a command before picture/paint — other forms stay
    // plain messages (here unhandled, which reads as an error, proving it
    // went to dispatch rather than the import-picture parser).
    let engine = try StackEngine(stackJSON: pictureJSON)
    await #expect(throws: (any Error).self) {
        _ = try await engine.runMessage("import everything")
    }
}
