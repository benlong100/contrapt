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

// MARK: - Container sort (`sort [lines|items of] <container>`)

@Test func sortAFieldSortsItsLinesInPlace() async throws {
    // The Home stack's shape: `sort bg fld "Apps For Docs"` on a field whose
    // text ends in a return — the trailing return stays a terminator, not an
    // empty first line.
    let host = MockHost(fields: ["background apps for docs": "Charlie\nAlice\nBob\n"])
    _ = try await run("""
    on mouseUp
      sort bg fld "Apps For Docs"
    end mouseUp
    """, host: host)
    #expect(host.fields["background apps for docs"] == "Alice\nBob\nCharlie\n")
    #expect(host.reorderedTo == nil) // the cards were not sorted
}

@Test func sortLinesOfAFieldDescending() async throws {
    let host = MockHost(fields: ["list": "Alice\nBob\nCharlie"])
    _ = try await run("""
    on mouseUp
      sort lines of field "List" descending
    end mouseUp
    """, host: host)
    #expect(host.fields["list"] == "Charlie\nBob\nAlice")
}

@Test func sortItemsOfAVariable() async throws {
    let host = MockHost(fields: ["out": ""])
    _ = try await run("""
    on mouseUp
      put "pear,apple,banana" into fruits
      sort items of fruits
      put fruits into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "apple,banana,pear")
}

@Test func sortContainerByEachRanksEachElement() async throws {
    let host = MockHost(fields: ["scores": "Bob 20\nAl 3\nCy 10"])
    _ = try await run("""
    on mouseUp
      sort lines of field "Scores" numeric by last word of each
    end mouseUp
    """, host: host)
    #expect(host.fields["scores"] == "Al 3\nCy 10\nBob 20")
}

@Test func sortACardFieldIsNotMistakenForTheCardsSort() async throws {
    // `cd` here qualifies the field — it must not be eaten as the cards form.
    let host = MockHost(fields: ["card names": "beta\nALPHA\ngamma"])
    _ = try await run("""
    on mouseUp
      sort cd fld "Names"
    end mouseUp
    """, host: host)
    #expect(host.fields["card names"] == "ALPHA\nbeta\ngamma")
    #expect(host.reorderedTo == nil)
}
