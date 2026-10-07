//
//  SendAndEffectTests.swift
//  HyperTalk
//
//  Gaps from the Oct-5 2nd batch (BMUG, HyperCard Vol 1, …): `send <message>`
//  with no `to` (dispatches to the current card — `send openCard`, `send
//  postCheck`), and `visual effect <variable>` / unmodeled effects (cosmetic,
//  so they fall back to a dissolve rather than failing the handler).
//

import Foundation
import Testing
@testable import HyperTalk

@Test func sendWithoutToReachesACardHandler() async throws {
    let host = try await run("""
    on mouseUp
      send "greet"
    end mouseUp
    on greet
      beep
    end greet
    """)
    #expect(host.beeps == 1)
}

@Test func sendWithoutToWithComputedMessage() async throws {
    // `send "greet" && x` — a computed message string with an argument.
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      put 5 into x
      send "greet" && x
    end mouseUp
    on greet n
      put n into field "out"
    end greet
    """, host: host)
    #expect(host.fields["out"] == "5")
}

@Test func sendUnhandledSystemMessageWithoutToNoOps() async throws {
    // `send openCard` with no handler is a recognized system message → no-op.
    let host = try await run("""
    on mouseUp
      send openCard
      beep
    end mouseUp
    """)
    #expect(host.beeps == 1)
}

@Test func visualEffectVariableFallsBack() async throws {
    // `visual effect theEffect` — the name is a variable, unresolvable at parse
    // time; parses (cosmetic dissolve fallback) and the `go` still runs.
    let host = try await run("""
    on mouseUp
      visual effect theEffect
      go next card
    end mouseUp
    """)
    #expect(host.destinations.count == 1)
}

@Test func visualEffectPushParses() async throws {
    let host = try await run("""
    on mouseUp
      visual effect push left
      go next card
    end mouseUp
    """)
    #expect(host.destinations.count == 1)
}
