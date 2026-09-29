//
//  TourForwardTests.swift
//  HyperTalk
//
//  The Tour's shared Next button sends `forward`; card 8 overrides it with a
//  handler that dissolves through the next five cards. A background part's
//  unhandled message must pass through the current card's script.
//

import Foundation
import Testing
@testable import HyperTalk

@Suite struct TourForwardTests {
    @Test func backgroundButtonForwardReachesCardHandler() async throws {
        let button = ScriptLayer(
            name: "button",
            source: """
            on mouseUp
            forward
            end mouseUp
            """,
            object: .part(kind: "button", domain: .background, reference: .id("84626"), onCard: nil)
        )
        let card = ScriptLayer(
            name: "card",
            source: """
            on forward
            set cursor to none
            repeat 5
            set cursor to none
            visual dissolve fast
            go next cd
            end repeat
            end forward
            """,
            object: .thisCard
        )
        let host = MockHost()
        try await HyperTalk.send("mouseUp", along: [button, card], host: host)
        #expect(host.destinations == Array(repeating: GoDestination.next, count: 5))
        #expect(host.goEffects.allSatisfy { $0.count == 1 && $0.first?.kind == .dissolve })
    }
}
