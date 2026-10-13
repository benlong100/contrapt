//
//  TimedSendWebTests.swift
//  HyperTalkEngine
//
//  Timed send through the web host: scheduling records a scheduleSend effect
//  (the page's setTimeout), and deliverScheduled dispatches when it fires —
//  including to a part on a card the user has since navigated away from.
//

import Foundation
import Testing
@testable import HyperTalkEngine

private let timedJSON = """
{
  "formatVersion": 1, "id": "11111111-1111-1111-1111-11111111AAAA",
  "name": "Timed", "cardSize": {"width": 400, "height": 300},
  "script": "", "nextID": 100,
  "backgrounds": [
    { "id": "22222222-2222-2222-2222-222222222222", "name": "BG", "script": "", "scriptID": 1, "parts": [] }
  ],
  "cards": [
    { "id": "33333333-3333-3333-3333-333333333331", "name": "Home", "scriptID": 10,
      "backgroundID": "22222222-2222-2222-2222-222222222222",
      "script": "on refresh what\\nput \\"refreshed\\" && what into msg\\nend refresh", "parts": [] },
    { "id": "33333333-3333-3333-3333-333333333332", "name": "Ticker", "scriptID": 11,
      "backgroundID": "22222222-2222-2222-2222-222222222222", "script": "",
      "parts": [
        { "id": "44444444-4444-4444-4444-444444444441", "name": "Clock", "scriptID": 40,
          "visible": true, "type": "button",
          "frame": { "x": 10, "y": 10, "width": 100, "height": 40 },
          "script": "on tick\\nput \\"ticked\\" into msg\\nend tick",
          "button": { "autoHilite": true, "format": { "align": "center", "fontDesign": "standard",
                      "isBold": false, "isItalic": false, "isUnderline": false, "size": 17 },
                      "hilite": false, "showName": true, "style": "roundRect", "title": "Clock" } }
      ] }
  ]
}
""".data(using: .utf8)!

@Test func schedulingRecordsTheTimerEffect() async throws {
    let engine = try StackEngine(stackJSON: timedJSON)
    _ = try await engine.runMessage("send \"refresh now\" to this card in 2 minutes")
    let effects = engine.drainEffects()
    #expect(effects.contains(.scheduleSend(message: "refresh", arguments: ["now"],
                                           partScriptID: nil, cardScriptID: 10, afterSeconds: 120)))
}

@Test func schedulingToAPartCarriesItsScriptID() async throws {
    let engine = try StackEngine(stackJSON: timedJSON)
    _ = try await engine.runMessage("send \"tick\" to button \"Clock\" of card 2 in 30 ticks")
    let effects = engine.drainEffects()
    #expect(effects.contains(.scheduleSend(message: "tick", arguments: [],
                                           partScriptID: 40, cardScriptID: 11, afterSeconds: 0.5)))
}

@Test func deliveryReachesAPartOnAnotherCard() async throws {
    // Fire the timer while the user is on card 1 — the pending send
    // survives navigation and lands on card 2's button.
    let engine = try StackEngine(stackJSON: timedJSON)
    let effects = try await engine.deliverScheduled(message: "tick", arguments: [],
                                                    partScriptID: 40, cardScriptID: 11)
    #expect(effects.contains(.message("ticked")))
}

@Test func deliveryToACardPathCarriesArguments() async throws {
    let engine = try StackEngine(stackJSON: timedJSON)
    let effects = try await engine.deliverScheduled(message: "refresh", arguments: ["please"],
                                                    partScriptID: nil, cardScriptID: 10)
    #expect(effects.contains(.message("refreshed please")))
}

@Test func deliveryToAVanishedTargetIsDroppedSilently() async throws {
    let engine = try StackEngine(stackJSON: timedJSON)
    let gonePart = try await engine.deliverScheduled(message: "tick", arguments: [],
                                                     partScriptID: 999, cardScriptID: 11)
    #expect(gonePart.isEmpty)
    let goneCard = try await engine.deliverScheduled(message: "refresh", arguments: [],
                                                     partScriptID: nil, cardScriptID: 999)
    #expect(goneCard.isEmpty)
}
