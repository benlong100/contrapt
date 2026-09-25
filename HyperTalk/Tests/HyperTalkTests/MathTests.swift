//
//  MathTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

@Test func sqrtAndPowers() async throws {
    let host = try await run("""
    on mouseUp
      put sqrt(16) into field "a"
      put exp2(10) into field "b"
      put compound(0.1, 2) into field "c"
    end mouseUp
    """, host: MockHost(fields: ["a": "", "b": "", "c": ""]))
    #expect(host.fields["a"] == "4")
    #expect(host.fields["b"] == "1024")
    // (1.1)^2 = 1.21
    #expect(host.fields["c"] == "1.21")
}

@Test func exponentOperator() async throws {
    let host = try await run("""
    on mouseUp
      put 2 ^ 3 into field "a"
      put 2 ^ 2 ^ 3 into field "b"
      put 2 ^ -1 into field "c"
      put 1 + 2 * 3 ^ 2 into field "d"
    end mouseUp
    """, host: MockHost(fields: ["a": "", "b": "", "c": "", "d": ""]))
    #expect(host.fields["a"] == "8")
    // Right-associative: 2 ^ (2 ^ 3) = 2 ^ 8 = 256.
    #expect(host.fields["b"] == "256")
    #expect(host.fields["c"] == "0.5")
    // ^ binds tighter than * and +: 1 + 2 * 9 = 19.
    #expect(host.fields["d"] == "19")
}

@Test func trigAndLogs() async throws {
    let host = try await run("""
    on mouseUp
      put sin(0) into field "a"
      put cos(0) into field "b"
      put ln(1) into field "c"
      put log2(8) into field "d"
    end mouseUp
    """, host: MockHost(fields: ["a": "", "b": "", "c": "", "d": ""]))
    #expect(host.fields["a"] == "0")
    #expect(host.fields["b"] == "1")
    #expect(host.fields["c"] == "0")
    #expect(host.fields["d"] == "3")
}

@Test func theMathFunctionOfForm() async throws {
    let host = try await run("""
    on mouseUp
      put the sqrt of 81 into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "9")
}

@Test func annuityFactor() async throws {
    let host = try await run("""
    on mouseUp
      put annuity(0, 5) into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    // With a zero rate, annuity(0, n) is n.
    #expect(host.fields["out"] == "5")
}

@Test func sumAndAverageOfArguments() async throws {
    let host = try await run("""
    on mouseUp
      put sum(1, 2, 3, 4) into field "a"
      put average(2, 4, 6) into field "b"
    end mouseUp
    """, host: MockHost(fields: ["a": "", "b": ""]))
    #expect(host.fields["a"] == "10")
    #expect(host.fields["b"] == "4")
}

@Test func sumOfACommaListInOneValue() async throws {
    let host = try await run("""
    on mouseUp
      put "10,20,30" into nums
      put sum(nums) into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "60")
}

@Test func theAverageOfAFieldOfLines() async throws {
    let host = try await run("""
    on mouseUp
      put the average of field "scores" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["scores": "10\n20\n30\n40", "out": ""]))
    #expect(host.fields["out"] == "25")
}
