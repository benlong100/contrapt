//
//  SortTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

@Test func sortByFieldReordersCards() async throws {
    let host = MockHost()
    host.sortKeys = ["Charlie", "Alice", "Bob"]
    _ = try await run("""
    on mouseUp
      sort by first word of first line of field "Name"
    end mouseUp
    """, host: host)
    // Ascending: Alice(1), Bob(2), Charlie(0).
    #expect(host.reorderedTo == [1, 2, 0])
}

@Test func sortDescendingReversesOrder() async throws {
    let host = MockHost()
    host.sortKeys = ["Charlie", "Alice", "Bob"]
    _ = try await run("""
    on mouseUp
      sort descending by field "Name"
    end mouseUp
    """, host: host)
    #expect(host.reorderedTo == [0, 2, 1])
}

@Test func sortNumericComparesAsNumbers() async throws {
    let host = MockHost()
    host.sortKeys = ["10", "2", "30"]
    _ = try await run("""
    on mouseUp
      sort numeric by field "n"
    end mouseUp
    """, host: host)
    // Numeric ascending: 2(1), 10(0), 30(2) — not lexicographic.
    #expect(host.reorderedTo == [1, 0, 2])
}
