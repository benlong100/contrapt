//
//  SelectTests.swift
//  HyperTalk
//
//  The `select` command and the selected* readers — the script selection
//  behind HyperCard's drag-a-list-selection idiom (Power Tools).
//

import Foundation
import Testing
@testable import HyperTalk

@Test func selectLineComputesTheAbsoluteRange() async throws {
    let host = MockHost(fields: ["topics": "Alpha\nBeta\nGamma"])
    try await run("""
    on mouseUp
      select line 2 of field "Topics"
    end mouseUp
    """, host: host)
    #expect(host.selections.count == 1)
    #expect(host.selections.first?.start == 6)   // after "Alpha\n"
    #expect(host.selections.first?.end == 10)    // "Beta"
}

@Test func selectNestedChunkOffsetsThroughTheLine() async throws {
    // Power Tools' shape: a char range within a line range.
    let host = MockHost(fields: ["topics": "Alpha\nBeta\nGamma"])
    try await run("""
    on mouseUp
      select char 2 to 3 of line 2 of field "Topics"
    end mouseUp
    """, host: host)
    #expect(host.selections.first?.start == 7)   // "et" of Beta
    #expect(host.selections.first?.end == 9)
}

@Test func selectTextEmptyAndEdges() async throws {
    let host = MockHost(fields: ["name": "Marmot"])
    try await run("""
    on mouseUp
      select text of field "Name"
      select before text of field "Name"
      select after text of field "Name"
      select empty
    end mouseUp
    """, host: host)
    #expect(host.selections.map { [$0.start, $0.end] } == [[0, 6], [0, 0], [6, 6]])
    #expect(host.selectionCleared)
}

@Test func selectingANonFieldIsAGracefulNoOp() async throws {
    // Old stacks `select theObject` to drive paint tools — parse, run, no-op.
    let host = MockHost(fields: [:])
    try await run("""
    on mouseUp
      put "cd btn id 3" into theObject
      select theObject
      select char 1 to 5 of theOther
    end mouseUp
    """, host: host)
    #expect(host.selections.isEmpty)
    #expect(!host.selectionCleared)
}

@Test func selectedReadersComeFromTheHost() async throws {
    let host = MockHost(fields: ["out": ""])
    host.selectionValues = [
        .line: "line 2 of card field id 7",
        .text: "Beta",
        .chunk: "char 7 to 10 of card field id 7",
        .field: "card field id 7",
    ]
    try await run("""
    on mouseUp
      put the selectedLine & "|" & the selectedText & "|" & the selection into field "out"
      put "|" & the selectedChunk & "|" & the selectedField after field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "line 2 of card field id 7|Beta|Beta|char 7 to 10 of card field id 7|card field id 7")
}

@Test func selectTheClickLineSelectsTheDescriptor() async throws {
    // HyperCard's classic list one-liner: the clickLine's value is a chunk
    // descriptor, re-parsed and selected.
    let host = MockHost(fields: ["card id 20": "Alpha\nBeta\nGamma"])
    host.clickValues = [.line: "line 2 of card field id 20"]
    try await run("""
    on mouseUp
      select the clickLine
    end mouseUp
    """, host: host)
    #expect(host.selections.first?.start == 6)
    #expect(host.selections.first?.end == 10)
    // Before any click the descriptor is empty — a graceful no-op.
    let idle = MockHost(fields: [:])
    try await run("on mouseUp\nselect the clickLine\nend mouseUp", host: idle)
    #expect(idle.selections.isEmpty)
}
