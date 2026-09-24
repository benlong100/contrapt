//
//  WordComparisonTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

@Test func isGreaterThanAndLessThan() async throws {
    let host = try await run("""
    on mouseUp
      if 5 is greater than 3 then put "a" after field "out"
      if 3 is less than 5 then put "b" after field "out"
      if 5 is greater than 9 then put "x" after field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "ab")
}

@Test func orEqualToForms() async throws {
    let host = try await run("""
    on mouseUp
      if 5 is greater than or equal to 5 then put "a" after field "out"
      if 4 is less than or equal to 4 then put "b" after field "out"
      if 6 is less than or equal to 4 then put "x" after field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "ab")
}

@Test func isNotGreaterThanNegates() async throws {
    let host = try await run("""
    on mouseUp
      if 3 is not greater than 5 then put "yes" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "yes")
}
