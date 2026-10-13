//
//  TimedSendTests.swift
//  HyperTalk
//
//  `send <msg> [to <object>] in <time>` — the timed send (LiveCode's idiom,
//  credited in EXTENSIONS). The message, arguments, target, and delay are
//  all resolved at schedule time; the host owns the clock.
//

import Testing
@testable import HyperTalk

@Test func timedSendResolvesUnitsToSeconds() async throws {
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      send "refresh" to this card in 2 minutes
      send "blink" to this card in 90 ticks
      send "poke" to this card in 5
    end p
    """, host: host)
    #expect(host.scheduledSends.count == 3)
    #expect(host.scheduledSends[0].message == "refresh")
    #expect(host.scheduledSends[0].afterSeconds == 120)
    #expect(host.scheduledSends[1].afterSeconds == 1.5)
    #expect(host.scheduledSends[2].afterSeconds == 5) // bare delay reads as seconds
}

@Test func timedSendBakesArgumentsAtScheduleTime() async throws {
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put 7 into total
      send "update total, 2+3" to this card in 1 second
    end p
    """, host: host)
    #expect(host.scheduledSends.first?.message == "update")
    #expect(host.scheduledSends.first?.arguments == ["7", "5"])
}

@Test func timedSendWithoutToTargetsThisCard() async throws {
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      send "refresh" in 3 seconds
    end p
    """, host: host)
    #expect(host.scheduledSends.first?.target == .thisCard)
}

@Test func plainSendStillDispatchesImmediately() async throws {
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      send "greet" to this card
    end p

    on greet
      put "hello" into msg
    end greet
    """, host: host)
    #expect(host.messages.last == "hello")
    #expect(host.scheduledSends.isEmpty)
}

@Test func waitAcceptsMinutes() throws {
    try HyperTalk.check("""
    on p
      wait 2 minutes
    end p
    """)
}
