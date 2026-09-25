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

@Test func isWithinTestsPointInRect() async throws {
    let host = try await run("""
    on mouseUp
      if "10,10" is within "0,0,50,50" then put "in" into field "a"
      if "60,10" is within "0,0,50,50" then put "in" into field "b"
      if "60,10" is not within "0,0,50,50" then put "out" into field "c"
      if "50,50" is within "0,0,50,50" then put "in" into field "d"
    end mouseUp
    """, host: MockHost(fields: ["a": "", "b": "", "c": "", "d": ""]))
    #expect(host.fields["a"] == "in")
    #expect(host.fields["b"] == "")       // right of the rect
    #expect(host.fields["c"] == "out")
    #expect(host.fields["d"] == "")       // right/bottom edge is exclusive
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
