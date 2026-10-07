//
//  QuotedHandlerTests.swift
//  HyperTalk
//
//  Quoted handler names — `on "CreditSubs" … end "CreditSubs"` (Checking &
//  Savings demo). The name is keyed lowercased like any other, so the handler
//  parses, nested `end if`/`end repeat` still close correctly, and the handler
//  is reachable by message.
//

import Foundation
import Testing
@testable import HyperTalk

@Test func quotedHandlerIsReachable() async throws {
    let host = try await run("""
    on mouseUp
      send "CreditSubs"
    end mouseUp
    on "CreditSubs"
      beep
    end "CreditSubs"
    """)
    #expect(host.beeps == 1)
}

@Test func quotedHandlerWithNestedBlocksCloses() async throws {
    // The `end if` inside must not be mistaken for the handler's `end "name"`.
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      doIt
    end mouseUp
    on "doIt"
      if 1 is 1 then
        put "ran" into field "out"
      end if
    end "doIt"
    """, host: host)
    #expect(host.fields["out"] == "ran")
}
