//
//  FindTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

// MARK: - The matcher (pure)

@Test func findCharsMatchesSubstringAnywhere() {
    let range = FindMatcher.firstRange(in: "category", query: "ego", mode: .chars)
    #expect(range == 3..<6)
}

@Test func findWordMatchesOnlyWholeWords() {
    #expect(FindMatcher.firstRange(in: "category cat", query: "cat", mode: .wholeWord) == 9..<12)
    #expect(FindMatcher.firstRange(in: "category", query: "cat", mode: .wholeWord) == nil)
}

@Test func findDefaultMatchesWordPrefix() {
    // Boxes the whole word that begins with the query.
    #expect(FindMatcher.firstRange(in: "the category", query: "cat", mode: .wordPrefix) == 4..<12)
    // Mid-word starts don't count.
    #expect(FindMatcher.firstRange(in: "scatter", query: "cat", mode: .wordPrefix) == nil)
}

@Test func findDefaultRequiresAllWordsPresent() {
    // Boxes the first search word's whole word ("brown").
    #expect(FindMatcher.firstRange(in: "quick brown fox", query: "br fo", mode: .wordPrefix) == 6..<11)
    #expect(FindMatcher.firstRange(in: "quick brown fox", query: "br zz", mode: .wordPrefix) == nil)
}

@Test func findWholePhraseMatchesOnBoundaries() {
    #expect(FindMatcher.firstRange(in: "a red car here", query: "red car", mode: .wholePhrase) == 2..<9)
    #expect(FindMatcher.firstRange(in: "unred cart", query: "red car", mode: .wholePhrase) == nil)
}

@Test func findIsCaseInsensitive() {
    #expect(FindMatcher.firstRange(in: "HyperCard", query: "card", mode: .chars) == 5..<9)
}

@Test func findResumesFromOffset() {
    // Second occurrence of "an".
    #expect(FindMatcher.firstRange(in: "banana banana", query: "an", mode: .chars, from: 2) == 3..<5)
}

// MARK: - The command (interpreter wiring)

@Test func findSetsResultEmptyOnHit() async throws {
    let host = MockHost(fields: ["notes": "the quick brown fox"])
    _ = try await run("""
    on mouseUp
      find "brown"
      put the result into field "out"
    end mouseUp
    """, host: withOut(host))
    #expect(host.fields["out"] == "")
    #expect(host.findCalls.count == 1)
    #expect(host.findCalls[0].mode == .wordPrefix)
}

@Test func findSetsResultNotFoundOnMiss() async throws {
    let host = MockHost(fields: ["notes": "the quick brown fox"])
    _ = try await run("""
    on mouseUp
      find "zebra"
      put the result into field "out"
    end mouseUp
    """, host: withOut(host))
    #expect(host.fields["out"] == "not found")
}

@Test func findExposesFoundText() async throws {
    let host = MockHost(fields: ["notes": "the quick brown fox"])
    _ = try await run("""
    on mouseUp
      find "qu"
      put the foundText into field "out"
    end mouseUp
    """, host: withOut(host))
    #expect(host.fields["out"] == "quick")
}

@Test func findParsesModesAndInField() async throws {
    let host = MockHost(fields: ["notes": "category", "other": "cat"])
    _ = try await run("""
    on mouseUp
      find chars "ego" in field "notes"
    end mouseUp
    """, host: host)
    #expect(host.findCalls.count == 1)
    #expect(host.findCalls[0].mode == .chars)
    #expect(host.findCalls[0].inField == .named("notes"))
}

@Test func findInMissingFieldIsAnError() async {
    await #expect(throws: ScriptError.self) {
        try await run("""
        on mouseUp
          find "world" in field "ghost"
        end mouseUp
        """, host: MockHost(fields: ["notes": "hello world"]))
    }
}

/// Adds an "out" field to a host's set so the assertions above can read into it.
private func withOut(_ host: MockHost) -> MockHost {
    host.fields["out"] = ""
    return host
}
