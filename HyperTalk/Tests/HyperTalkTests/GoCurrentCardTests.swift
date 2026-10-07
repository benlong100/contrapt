//
//  GoCurrentCardTests.swift
//  HyperTalk
//
//  `go [to] this card` — re-navigate to the current card (a stay/refresh),
//  commonly an `else` branch. Resolves to the current card's number.
//

import Foundation
import Testing
@testable import HyperTalk

@Test func goThisCardNavigatesToCurrentNumber() async throws {
    let host = MockHost()
    host.cardCount = 5
    host.properties["this card.number"] = "3"
    _ = try await run("""
    on mouseUp
      go this card
    end mouseUp
    """, host: host)
    #expect(host.destinations == [.number(3)])
}

@Test func goToThisCardWithToKeyword() async throws {
    let host = MockHost()
    host.properties["this card.number"] = "1"
    _ = try await run("""
    on mouseUp
      go to this card
    end mouseUp
    """, host: host)
    #expect(host.destinations == [.number(1)])
}

@Test func goCardByShortNameOfTarget() async throws {
    // CUTLURE's EssayLink: `go cd short name of target`. The `short name of X`
    // property must parse as the card destination even though `go` suppresses
    // the generic bare-property shortcut (for `go card whichSix of stack "X"`).
    let button = HyperTalkObject.part(kind: "button", domain: .background, reference: .named("Go"), onCard: nil)
    let host = MockHost()
    host.properties["background button Go.name"] = "Chapter 3"
    let layers = [ScriptLayer(name: "btn script", source: """
    on mouseUp
      go cd short name of target
    end mouseUp
    """, object: button)]
    _ = try await HyperTalk.send("mouseUp", along: layers, host: host)
    #expect(host.destinations.last == .named("Chapter 3"))
}

@Test func singleLineElseGoThisCard() async throws {
    // The BeerStack "I want a pint!" shape: a single-line then, with the else
    // (`go this card`) on the following line.
    let host = MockHost(fields: ["out": ""])
    host.properties["this card.number"] = "2"
    host.answerChoice = "No"
    _ = try await run("""
    on mouseUp
      answer "Quit?" with "Yes" or "No"
      if it is "Yes" then put "quit" into field "out"
      else go this card
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "")       // the "No" branch didn't write
    #expect(host.destinations == [.number(2)]) // …it stayed on the current card
}

@Test func goRecentCardIsBack() async throws {
    let host = MockHost()
    _ = try await run("""
    on mouseUp
      go recent card
    end mouseUp
    """, host: host)
    #expect(host.destinations.last == .back)
}

@Test func goAnyCardPicksACard() async throws {
    // `go to any card` → a random card; with one card it's deterministically 1.
    let host = MockHost()
    host.cardCount = 1
    _ = try await run("""
    on mouseUp
      go to any card
    end mouseUp
    """, host: host)
    #expect(host.destinations.last == .number(1))
}
