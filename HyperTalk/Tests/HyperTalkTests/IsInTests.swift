//
//  IsInTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

@Test func isInChecksContainment() async throws {
    let host = try await run("""
    on mouseUp
      if "per" is in "HyperCard" then put "yes" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "yes")
}

@Test func isNotInIsTheNegation() async throws {
    let host = try await run("""
    on mouseUp
      if "z" is not in "HyperCard" then put "absent" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "absent")
}

@Test func isInWorksWithVariables() async throws {
    let host = try await run("""
    on mouseUp
      put "brown" into needle
      put "the quick brown fox" into haystack
      if needle is in haystack then put "found" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "found")
}
