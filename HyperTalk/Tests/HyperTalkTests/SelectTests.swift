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

@Test func selectTextOfMeAndTargetInAFieldScript() async throws {
    // Readymade Fields / Phone Dialer idiom: `select text of me`, and the
    // before/after collapses — the field designator is `me`, not a literal ref.
    let field = HyperTalkObject.part(kind: "field", domain: .card, reference: .named("Note"), onCard: nil)
    let host = MockHost(fields: ["card note": "Marmot"])
    _ = try await HyperTalk.send("mouseUp", along: [
        ScriptLayer(name: "field script", source: """
        on mouseUp
          select text of me
          select after text of me
          select before text of the target
        end mouseUp
        """, object: field)
    ], host: host)
    #expect(host.selections.map { [$0.start, $0.end] } == [[0, 6], [6, 6], [0, 0]])
}

@Test func selectTextOfAVariableFieldReference() async throws {
    // Readymade Buttons: `select text of whichLayer`, where the variable holds
    // a field descriptor — resolved at run time.
    let host = MockHost(fields: ["name": "Marmot"])
    try await run("""
    on mouseUp
      put "field " & quote & "Name" & quote into whichLayer
      select text of whichLayer
    end mouseUp
    """, host: host)
    #expect(host.selections.map { [$0.start, $0.end] } == [[0, 6]])
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

@Test func selectingAButtonObjectIsANoOp() async throws {
    // `select cd btn id 17` / `select line 0 of bg btn "X"` drive HyperCard's
    // edit tools (copy/paste a button, a popup's list) — not modeled, so they
    // parse and no-op, and the handler keeps running.
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      select cd btn id 17
      select line 0 of bg btn "Go Back"
      put "ran" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "ran")
    #expect(host.selections.isEmpty)
    #expect(!host.selectionCleared)
}
