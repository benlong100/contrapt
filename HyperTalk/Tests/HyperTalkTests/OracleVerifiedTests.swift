//
//  OracleVerifiedTests.swift
//  Behaviors verified against REAL HyperCard 2.3 via the Basilisk oracle
//  (Scripts/oracle-diff.sh, 2026-10-07). These pin the semantics offline so
//  the emulator isn't needed to catch a regression.
//

import Testing
@testable import HyperTalk

@Test func roundUsesBankersRounding() async throws {
    // HyperCard rounds half to even: round(2.5)=2, round(3.5)=4.
    let host = try await run("on p\nput round(2.5) & \",\" & round(3.5) & \",\" & round(-2.5)\nend p", handler: "p")
    #expect(host.messages.last == "2,4,-2")
}

@Test func trailingDelimiterMakesNoEmptyChunk() async throws {
    // ",a,,b," is 4 items (leading/middle empties count, trailing doesn't);
    // `last item of "a,b,"` is b; a lone return is 1 line; "" has 0 items.
    let host = try await run("""
    on p
      put the number of items in ",a,,b," & "|" & last item of "a,b," & "|" ¬
        & the number of lines in return & "|" & the number of items in ""
    end p
    """, handler: "p")
    #expect(host.messages.last == "4|b|1|0")
}

@Test func middleEmptyItemsStillCount() async throws {
    let host = try await run("on p\nput item 2 of \",a,,b,\" & \"|\" & item 1 of \",a\"\nend p", handler: "p")
    #expect(host.messages.last == "a|")
}

@Test func piIsTheTwentyDigitLiteral() async throws {
    let host = try await run("on p\nput pi\nend p", handler: "p")
    #expect(host.messages.last == "3.14159265358979323846")
}
