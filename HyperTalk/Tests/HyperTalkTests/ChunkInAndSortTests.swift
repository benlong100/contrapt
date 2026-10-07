//
//  ChunkInAndSortTests.swift
//  HyperTalk
//
//  Two pervasive 2nd-batch gaps: `in` as a synonym for `of` in chunk
//  expressions (`first word in field "range"`, `char 2 in x`) and `sort by
//  [ascending|descending] <key>` — the direction/style after `by` (Politca1).
//

import Foundation
import Testing
@testable import HyperTalk

@Test func inIsASynonymForOfInChunks() async throws {
    let host = MockHost(fields: ["range": "40 190", "out": ""])
    try await run("""
    on mouseUp
      put first word in field "range" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "40")
}

@Test func inSynonymForIndexedChunk() async throws {
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      put "abcd" into x
      put char 2 in x into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "b")
}

@Test func sortByDescendingKey() async throws {
    // `sort by descending <key>` — direction after `by` (both orders work).
    let host = MockHost(fields: ["out": ""])
    host.sortKeys = ["b", "a", "c"]
    try await run("""
    on mouseUp
      sort by descending field "Year"
    end mouseUp
    """, host: host)
    // Descending by the per-card key → c, b, a (original indices 2,0,1).
    #expect(host.reorderedTo == [2, 0, 1])
}

@Test func sortDescendingByKeyStillWorks() async throws {
    let host = MockHost(fields: ["out": ""])
    host.sortKeys = ["b", "a", "c"]
    try await run("""
    on mouseUp
      sort descending by field "Year"
    end mouseUp
    """, host: host)
    #expect(host.reorderedTo == [2, 0, 1])
}
