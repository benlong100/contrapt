//
//  DeleteObjectTests.swift
//  HyperTalkEngine
//
//  Scripted object deletion beyond cards: parts (buttons, fields, images),
//  empty backgrounds, and the paint layer — the cleanup-script vocabulary
//  (delete button i / delete background 2 / delete the card picture).
//

import Foundation
import Testing
@testable import HyperTalkEngine

private let objJSON = """
{
  "formatVersion": 1, "id": "11111111-1111-1111-1111-111111111111",
  "name": "Del", "cardSize": {"width": 400, "height": 300}, "script": "",
  "backgrounds": [
    { "id": "22222222-2222-2222-2222-222222222221", "name": "Main", "script": "", "parts": [
        { "id": "66666666-6666-6666-6666-666666666661", "name": "BGBtn",
          "frame": {"x": 5, "y": 5, "width": 60, "height": 20}, "script": "",
          "scriptID": 20, "type": "button", "button": {"title": "BGBtn"} }
    ] },
    { "id": "22222222-2222-2222-2222-222222222222", "name": "Spare", "script": "", "parts": [] }
  ],
  "cards": [
    { "id": "33333333-3333-3333-3333-333333333331", "name": "One",
      "backgroundID": "22222222-2222-2222-2222-222222222221", "script": "",
      "parts": [
        { "id": "44444444-4444-4444-4444-444444444441", "name": "Go",
          "frame": {"x": 10, "y": 10, "width": 80, "height": 24}, "script": "",
          "scriptID": 7, "type": "button", "button": {"title": "Go"} },
        { "id": "44444444-4444-4444-4444-444444444442", "name": "Notes",
          "frame": {"x": 10, "y": 50, "width": 120, "height": 90}, "script": "",
          "scriptID": 8, "type": "field", "field": {"text": "hi", "placeholder": "", "format": {}} },
        { "id": "44444444-4444-4444-4444-444444444443", "name": "Photo",
          "frame": {"x": 10, "y": 150, "width": 60, "height": 60}, "script": "",
          "scriptID": 9, "type": "image", "image": {"assetName": "photo.png"} }
      ] }
  ]
}
""".data(using: .utf8)!

@Test func deleteButtonByNumberRemovesIt() async throws {
    let engine = try StackEngine(stackJSON: objJSON)
    _ = try await engine.runMessage("delete button 1")
    #expect(try await engine.runMessage("the number of card buttons") == "0")
    // The background button survives (unqualified counts are per layer).
    #expect(try await engine.runMessage("the number of background buttons") == "1")
}

@Test func deleteCardFieldByName() async throws {
    let engine = try StackEngine(stackJSON: objJSON)
    _ = try await engine.runMessage("delete card field \"Notes\"")
    #expect(try await engine.runMessage("the number of card fields") == "0")
}

@Test func deleteImageAndCountImages() async throws {
    let engine = try StackEngine(stackJSON: objJSON)
    #expect(try await engine.runMessage("the number of card images") == "1")
    _ = try await engine.runMessage("delete image 1")
    #expect(try await engine.runMessage("the number of card images") == "0")
}

@Test func deleteEmptyBackgroundWorksAndUsedOneRefuses() async throws {
    let engine = try StackEngine(stackJSON: objJSON)
    #expect(try await engine.runMessage("the number of backgrounds") == "2")
    _ = try await engine.runMessage("delete background 2")   // Spare: no cards
    #expect(try await engine.runMessage("the number of backgrounds") == "1")
    await #expect(throws: (any Error).self) {
        _ = try await engine.runMessage("delete background 1")  // still has cards
    }
}

@Test func deleteCardPictureHidesPaintInTheEngine() async throws {
    // The engine model carries no paint asset — hiding is its observable
    // effect (the app host truly clears the assets).
    let engine = try StackEngine(stackJSON: objJSON)
    _ = try await engine.runMessage("delete the card picture")
    #expect(engine.currentCardState().cardShowPicture == false)
    _ = try await engine.runMessage("delete the picture of this background")
    #expect(engine.currentCardState().backgroundShowPicture == false)
}

@Test func deleteLoopClearsEveryCardPart() async throws {
    // The cleanup idiom — loop DOWN so indices stay valid while deleting.
    let engine = try StackEngine(stackJSON: objJSON)
    _ = try await engine.runMessage("repeat with i = the number of card parts down to 1\ndelete card part i\nend repeat")
    #expect(try await engine.runMessage("the number of card parts") == "0")
}
