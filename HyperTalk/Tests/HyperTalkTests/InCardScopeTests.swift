//
//  InCardScopeTests.swift
//  HyperTalk
//
//  HyperCard accepts `in card N` wherever `of card N` scopes a part or field to
//  a specific card (Adventures of Sean 2: `show card button "X" in card 81`,
//  `put card field "chain" in card 81 into beer`), plus a couple of lenient go/
//  answer forms real stacks use. These are parse-level regressions.
//

import Foundation
import Testing
@testable import HyperTalk

@Test func showPartScopedToCardWithIn() throws {
    _ = try Parser.parse("""
    on openStack
      hide card button "Return to game" in card "about card"
      show card field "loading" in card 81
    end openStack
    """)
}

@Test func sendToPartScopedToCardWithIn() throws {
    _ = try Parser.parse("""
    on mouseUp
      send mouseUp to card button "phone" in card 25
    end mouseUp
    """)
}

@Test func fieldValueScopedToCardWithIn() throws {
    _ = try Parser.parse("""
    on mouseUp
      put card field "chain" in card 81 into beer
    end mouseUp
    """)
}

@Test func bareGoToCardStaysPut() throws {
    _ = try Parser.parse("""
    on mouseUp
      go to card
      go card id
    end mouseUp
    """)
}

@Test func answerButtonsSeparatedByCommas() async throws {
    // Comma-separated button list (some stacks use it instead of `or`).
    let host = try await run("""
    on mouseUp
      answer "Pick one" with "No","Yes"
    end mouseUp
    """)
    #expect(host.answerButtons.first == ["No", "Yes"])
}
