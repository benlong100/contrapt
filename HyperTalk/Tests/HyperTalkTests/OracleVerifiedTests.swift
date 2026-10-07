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
    // …and numberFormat never reformats the constant on put.
    let host = try await run("on p\nput pi\nend p", handler: "p")
    #expect(host.messages.last == "3.14159265358979323846")
}

@Test func middleOfEvenCountIsTheHigherIndex() async throws {
    let host = try await run("on p\nput middle item of \"a,b,c,d\" & middle word of \"x y z\"\nend p", handler: "p")
    #expect(host.messages.last == "cy")
}

@Test func emptyIsContainedInNothing() async throws {
    let host = try await run("on p\nput (\"abc\" contains \"\") & \",\" & (\"\" is in \"abc\") & \",\" & (\"b\" is in \"abc\")\nend p", handler: "p")
    #expect(host.messages.last == "false,false,true")
}

@Test func numberFormatAppliesAtPutNotBetweenOperations() async throws {
    // Full precision flows through the expression; the default 0.######
    // rounds only when the number becomes text. atan(1)*4 is 3.141593 (not
    // 3.141592) and sqrt(2)*sqrt(2) is exactly 2.
    let host = try await run("on p\nput atan(1) * 4 & \",\" & sqrt(2) * sqrt(2) & \",\" & 1/3\nend p", handler: "p")
    #expect(host.messages.last == "3.141593,2,0.333333")
}

@Test func charThirteenIsTheReturnConstant() async throws {
    let host = try await run("on p\nput (numToChar(13) = return) & charToNum(return)\nend p", handler: "p")
    #expect(host.messages.last == "true13")
}

@Test func theNumberFormatReadsTheDefault() async throws {
    let host = try await run("on p\nput the numberFormat\nend p", handler: "p")
    #expect(host.messages.last == "0.######")
}
