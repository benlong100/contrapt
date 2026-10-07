//
//  ConvertTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

@Test func convertSecondsToDateItems() async throws {
    // Seconds count from HyperCard's 1904 epoch (local); render the expected
    // items through the same helper so the test is timezone-independent.
    let seconds = 2019686400
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let expected = utc.dateComponents(
        [.year, .month, .day, .hour, .minute, .second, .weekday],
        from: HyperCardDate.date(fromSeconds: Double(seconds), calendar: utc))
    let expectedItems = [expected.year!, expected.month!, expected.day!, expected.hour!,
                         expected.minute!, expected.second!, expected.weekday!]
        .map(String.init).joined(separator: ",")
    let host = try await run("""
    on mouseUp
      put \(seconds) into t
      convert t to dateItems
      put t into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == expectedItems)
}

@Test func convertEmptyUsesTheCurrentDate() async throws {
    // HyperCard fills omitted components from the current date/time, so an
    // empty value converts as "now" (here the fixed 2034-01-01) rather than
    // erroring — DateBook's `goSixMonthly field "weekSecs"` relies on this when
    // the field is empty.
    let host = try await run("""
    on mouseUp
      put empty into t
      convert t to seconds
      put t into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    // MockHost's fixed "now" (2034-01-01 UTC), as 1904-epoch seconds.
    #expect(host.fields["out"] == "4102531200" /* 2019686400 unix + 2082844800 (1904→1970, UTC) */)
}

@Test func convertDateItemsFillsMissingComponentsFromNow() async throws {
    // `,,,0,0,0` (what `put 0 into item 4/5/6` of an empty value produces in
    // startOfWeek) is today at midnight, not an invalid year-0 date.
    let host = try await run("""
    on mouseUp
      put ",,,0,0,0" into t
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
    // MockHost's dateItems parse in UTC; seconds from the 1904 epoch helper.
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let parsed = utc.date(from: DateComponents(year: 2034, month: 1, day: 1))!
    #expect(host.fields["out"] == String(HyperCardDate.seconds(of: parsed, calendar: utc)))
}

@Test func convertBareExpressionLandsInIt() async throws {
    // A date-only string, auto-detected, converted to seconds into `it`.
    let host = try await run("""
    on mouseUp
      convert "1/1/2034" to seconds
      put it into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    // MockHost parses in UTC; seconds count from the 1904 epoch (local helper).
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let parsed = utc.date(from: DateComponents(year: 2034, month: 1, day: 1))!
    #expect(host.fields["out"] == String(HyperCardDate.seconds(of: parsed, calendar: utc)))
}

@Test func convertRewritesAFieldInPlace() async throws {
    let host = try await run("""
    on mouseUp
      convert field "when" to dateItems
    end mouseUp
    """, host: MockHost(fields: ["when": "2019686400"]))
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let expected = utc.dateComponents(
        [.year, .month, .day, .hour, .minute, .second, .weekday],
        from: HyperCardDate.date(fromSeconds: 2019686400, calendar: utc))
    #expect(host.fields["when"] == [expected.year!, expected.month!, expected.day!,
        expected.hour!, expected.minute!, expected.second!, expected.weekday!]
        .map(String.init).joined(separator: ","))
}

@Test func convertToDateAndTime() async throws {
    let host = try await run("""
    on mouseUp
      put \(HyperCardDate.seconds(of: referenceSunday, calendar: utcCal)) into t
      convert t to short date and short time
      put t into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "1/1/34 12:00 AM")
}

private var utcCal: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

/// 2034-01-01 00:00 UTC — a Sunday (MockHost renders in UTC).
private var referenceSunday: Date {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    return utc.date(from: DateComponents(year: 2034, month: 1, day: 1))!
}

@Test func convertToLongDate() async throws {
    let host = try await run("""
    on mouseUp
      put \(HyperCardDate.seconds(of: referenceSunday, calendar: utcCal)) into t
      convert t to long date
      put t into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "Sunday, January 1, 2034")
}

@Test func isADateUsesTheHostCalendar() async throws {
    // `is a[n] date` — Readymade Fields' validation loop (`if it is a date`).
    // A readable date is true; nonsense is false.
    let host = try await run("""
    on mouseUp
      if "1995,10,5" is a date then put "yes" into field "out"
      if "not a date" is a date then put "oops" after field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "yes")
}
