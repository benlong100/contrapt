//
//  RepeatVisualExitTests.swift
//  HyperTalk
//
//  More 2nd-batch fixes: `repeat with i is A to B` (`is` for `=`, Home's STAK),
//  `visual effect "CheckerBoard"` (a quoted effect name), and `exit "mouseUp"`
//  (a quoted handler name, Checking & Savings demo).
//

import Foundation
import Testing
@testable import HyperTalk

@Test func repeatWithIsInsteadOfEquals() async throws {
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      put 0 into total
      repeat with i is 1 to 3
        add i to total
      end repeat
      put total into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "6")
}

@Test func visualEffectQuotedName() async throws {
    let host = try await run("""
    on mouseUp
      visual effect "CheckerBoard" slowly
      go next card
    end mouseUp
    """)
    #expect(host.destinations.count == 1)
}

@Test func exitQuotedHandlerName() async throws {
    // `exit "mouseUp"` exits before the beep.
    let host = try await run("""
    on mouseUp
      exit "mouseUp"
      beep
    end mouseUp
    """)
    #expect(host.beeps == 0)
}
