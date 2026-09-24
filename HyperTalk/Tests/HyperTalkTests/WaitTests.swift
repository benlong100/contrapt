//
//  WaitTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

@Test func waitSecondsAsksTheHostForThatDuration() async throws {
    let host = try await run("""
    on mouseUp
      wait 2 seconds
    end mouseUp
    """)
    #expect(host.waits == [2])
}

@Test func bareNumberWaitsInTicks() async throws {
    let host = try await run("""
    on mouseUp
      wait 30
    end mouseUp
    """)
    // 30 ticks = 0.5 seconds.
    #expect(host.waits == [0.5])
}

@Test func waitForTicks() async throws {
    let host = try await run("""
    on mouseUp
      wait for 60 ticks
    end mouseUp
    """)
    #expect(host.waits == [1])
}

@Test func waitUntilAnAlreadyTrueConditionDoesNotPause() async throws {
    let host = try await run("""
    on mouseUp
      wait until 1 = 1
    end mouseUp
    """)
    #expect(host.waits.isEmpty)
}

@Test func waitWhileAnAlwaysTrueConditionIsStoppedByTheStepBudget() async throws {
    // `wait while` polls; a condition that never flips is bounded by maxSteps.
    await #expect(throws: ScriptError.self) {
        try await run("""
        on mouseUp
          wait while 1 = 1
        end mouseUp
        """, maxSteps: 50)
    }
}

@Test func zeroWaitDoesNothing() async throws {
    let host = try await run("""
    on mouseUp
      wait 0 seconds
    end mouseUp
    """)
    #expect(host.waits.isEmpty)
}
