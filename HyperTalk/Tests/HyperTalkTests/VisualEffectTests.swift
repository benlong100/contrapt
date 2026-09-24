//
//  VisualEffectTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

@Test func visualEffectPlaysOnTheNextGo() async throws {
    let host = try await run("""
    on mouseUp
      visual effect dissolve
      go to next card
    end mouseUp
    """)
    #expect(host.destinations == [.next])
    #expect(host.goEffects == [[ScreenEffect(kind: .dissolve)]])
}

@Test func visualEffectWithDirectionAndSpeed() async throws {
    let host = try await run("""
    on mouseUp
      visual effect wipe left very fast
      go to card 2
    end mouseUp
    """)
    #expect(host.goEffects == [[ScreenEffect(kind: .wipe, direction: .left, speed: .veryFast)]])
}

@Test func theEffectWordIsOptional() async throws {
    let host = try await run("""
    on mouseUp
      visual iris open slowly
      go next card
    end mouseUp
    """)
    #expect(host.goEffects == [[ScreenEffect(kind: .iris, direction: .open, speed: .slow)]])
}

@Test func multipleEffectsQueueForOneGo() async throws {
    let host = try await run("""
    on mouseUp
      visual effect dissolve
      visual effect barn door open
      go to next card
    end mouseUp
    """)
    #expect(host.goEffects == [[
        ScreenEffect(kind: .dissolve),
        ScreenEffect(kind: .barnDoor, direction: .open),
    ]])
}

@Test func effectsClearAfterTheGo() async throws {
    let host = try await run("""
    on mouseUp
      visual effect dissolve
      go to next card
      go to next card
    end mouseUp
    """)
    // First go plays the effect; the second is a plain cut.
    #expect(host.goEffects == [[ScreenEffect(kind: .dissolve)], []])
}

@Test func plainGoHasNoEffects() async throws {
    let host = try await run("""
    on mouseUp
      go to next card
    end mouseUp
    """)
    #expect(host.goEffects == [[]])
}
