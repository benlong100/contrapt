//
//  MenuRecentEndTests.swift
//  HyperTalk
//
//  Further 2nd-batch fixes: `if menu is "X"` (a bareword `menu` followed by an
//  operator isn't a menu keyword — regression guard), `field 1 of recent card`,
//  `end <handler> <trailing>` (Home's `end doMenu which`), and `show (expr)
//  cards` (a parenthesized flip-through count).
//

import Foundation
import Testing
@testable import HyperTalk

@Test func menuFollowedByOperatorIsNotAMenuName() async throws {
    // `if menu is "X"` — `menu` is a plain value here (reads empty), so the
    // comparison is `"" is "X"` → false; the then-branch doesn't fire.
    let host = try await run("""
    on mouseUp
      if menu is "Background" then beep
    end mouseUp
    """)
    #expect(host.beeps == 0)
}

@Test func menuVariableStillParses() async throws {
    // The original need still works: `menu it` where `it` names the menu.
    _ = try Parser.parse("on t\nput line 8 of menu it into x\nend t")
}

@Test func fieldOfRecentCardParses() async throws {
    _ = try Parser.parse("on t\nif field 1 of recent card is not empty then beep\nend t")
}

@Test func endHandlerWithTrailingWordParses() async throws {
    // Apple's Home: `on doMenu which … end doMenu which`.
    let script = try Parser.parse("on doMenu which\npass doMenu\nend doMenu which")
    #expect(script.handlers["domenu"] != nil)
}

@Test func showParenthesizedCardCountIsIgnored() async throws {
    let host = try await run("""
    on mouseUp
      show (number of cards) cards
      beep
    end mouseUp
    """)
    #expect(host.beeps == 1)
}
