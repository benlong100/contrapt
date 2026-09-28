//
//  ClickLineTests.swift
//  HyperTalk
//
//  `the clickLine` / `the clickText` — where the last locked-field click
//  landed (HyperCard 2.2's list-field navigation idiom).
//

import Foundation
import Testing
@testable import HyperTalk

@Test func clickLineAndTextReadFromTheHost() async throws {
    let host = MockHost(fields: ["out": ""])
    host.clickValues = [.line: "line 3 of card field id 12", .text: "Beta"]
    try await run("""
    on mouseUp
      put the clickLine & "|" & the clickText into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "line 3 of card field id 12|Beta")
}

@Test func clickLineNumberAndValueFollowTheClassicIdiom() async throws {
    // The classic list script: `word 2 of the clickLine` is the line number,
    // `the value of the clickLine` is the clicked line's text.
    let host = MockHost(fields: ["out": "", "card id 12": "Alpha\nBeta\nGamma"])
    host.clickValues = [.line: "line 2 of card field id 12"]
    try await run("""
    on mouseUp
      put word 2 of the clickLine into field "out"
      put " " & the value of the clickLine after field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "2 Beta")
}

@Test func clickValuesAreEmptyBeforeAnyClick() async throws {
    let host = MockHost(fields: ["out": "x"])
    try await run("""
    on mouseUp
      put the clickLine & the clickText into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "")
}
