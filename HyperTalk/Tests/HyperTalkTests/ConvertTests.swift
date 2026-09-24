//
//  ConvertTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

@Test func convertSecondsToDateItems() async throws {
    // 2019686400 = 2034-01-01 00:00:00 UTC (a Sunday, weekday 1).
    let host = try await run("""
    on mouseUp
      put 2019686400 into t
      convert t to dateItems
      put t into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "2034,1,1,0,0,0,1")
}

@Test func convertDateItemsToSeconds() async throws {
    let host = try await run("""
    on mouseUp
      put "2034,1,1,0,0,0" into t
      convert t from dateItems to seconds
      put t into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "2019686400")
}

@Test func convertBareExpressionLandsInIt() async throws {
    // A date-only string, auto-detected, converted to seconds into `it`.
    let host = try await run("""
    on mouseUp
      convert "1/1/34" to seconds
      put it into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "2019686400")
}

@Test func convertRewritesAFieldInPlace() async throws {
    let host = try await run("""
    on mouseUp
      convert field "when" to dateItems
    end mouseUp
    """, host: MockHost(fields: ["when": "2019686400"]))
    #expect(host.fields["when"] == "2034,1,1,0,0,0,1")
}

@Test func convertToDateAndTime() async throws {
    let host = try await run("""
    on mouseUp
      put 2019686400 into t
      convert t to short date and short time
      put t into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "1/1/34 12:00 AM")
}

@Test func convertToLongDate() async throws {
    let host = try await run("""
    on mouseUp
      put 2019686400 into t
      convert t to long date
      put t into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "Sunday, January 1, 2034")
}
