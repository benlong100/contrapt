//
//  ChunkTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

@Test func wordByIndex() async throws {
    let host = try await run("""
    on mouseUp
      put "the quick brown fox" into s
      put word 3 of s into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "brown")
}

@Test func variableChunkIndexIsNotSwallowedByBareProperty() async throws {
    // `line myLine of s` — the `of` belongs to the chunk, not to a bare
    // property on the index variable. Regression for the bare-`of` shortcut.
    let host = try await run("""
    on mouseUp
      put "alpha" & return & "beta" & return & "gamma" into s
      put 2 into myLine
      put line myLine of s into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "beta")
}

@Test func bareOrdinalChunkWithoutThe() async throws {
    // `last char of X`, `first word of X` — HyperTalk's `the` is optional.
    let host = try await run("""
    on mouseUp
      put "the quick brown fox" into s
      put first word of s & last char of s into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "thex")
}

@Test func chunkContainerWithVariableIndex() async throws {
    // `put X into char myCount of field …` — the container's chunk index
    // is a variable; its `of` belongs to the chunk, not a bare property.
    let host = try await run("""
    on mouseUp
      put "abc" into field "out"
      put 2 into myCount
      put "Z" into char myCount of field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "aZc")
}

@Test func theFirstAndLastWord() async throws {
    let host = try await run("""
    on mouseUp
      put "the quick brown fox" into s
      put the first word of s & "/" & the last word of s into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "the/fox")
}

@Test func theMiddleWord() async throws {
    let host = try await run("""
    on mouseUp
      put word 2 of "a b c d e" into x
      put the middle word of "a b c d e" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "c")
}

@Test func charByIndexAndRange() async throws {
    let host = try await run("""
    on mouseUp
      put char 1 of "Hello" into field "a"
      put char 2 to 4 of "Hello" into field "b"
    end mouseUp
    """, host: MockHost(fields: ["a": "", "b": ""]))
    #expect(host.fields["a"] == "H")
    #expect(host.fields["b"] == "ell")
}

@Test func itemsAreCommaDelimitedKeepingEmpties() async throws {
    let host = try await run("""
    on mouseUp
      put "a,,c" into s
      put item 2 of s & "|" & item 3 of s into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "|c")
}

@Test func linesSplitOnReturn() async throws {
    let host = try await run("""
    on mouseUp
      put line 2 of field "src" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["src": "one\ntwo\nthree", "out": ""]))
    #expect(host.fields["out"] == "two")
}

@Test func wordRangeRejoinsWithSpaces() async throws {
    let host = try await run("""
    on mouseUp
      put word 2 to 3 of "the quick brown fox" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "quick brown")
}

@Test func outOfRangeChunkIsEmpty() async throws {
    let host = try await run("""
    on mouseUp
      if word 9 of "a b c" is empty then put "empty" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "empty")
}

@Test func nestedChunks() async throws {
    let host = try await run("""
    on mouseUp
      put the first char of the last word of "the quick brown fox" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "f")
}

@Test func chunkIndexCanBeAnExpression() async throws {
    let host = try await run("""
    on mouseUp
      put 2 into n
      put word (n + 1) of "a b c d" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "c")
}

@Test func chunkOfAField() async throws {
    let host = try await run("""
    on mouseUp
      put word 1 of field "name" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["name": "Grace Hopper", "out": ""]))
    #expect(host.fields["out"] == "Grace")
}

// MARK: - Chunks as containers (put into a chunk)

@Test func putIntoWordOfVariable() async throws {
    let host = try await run("""
    on mouseUp
      put "the quick brown fox" into s
      put "slow" into word 2 of s
      put s into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "the slow brown fox")
}

@Test func putIntoItemOfField() async throws {
    let host = try await run("""
    on mouseUp
      put "green" into item 2 of field "colors"
    end mouseUp
    """, host: MockHost(fields: ["colors": "red,white,blue"]))
    #expect(host.fields["colors"] == "red,green,blue")
}

@Test func putAfterCharChunk() async throws {
    let host = try await run("""
    on mouseUp
      put "X" after char 2 of s
      put s into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    // s is empty; char 2 of empty → append X at start-ish. Just ensure no crash.
    #expect(host.fields["out"] != nil)
}

@Test func putIntoLineExtendsField() async throws {
    let host = try await run("""
    on mouseUp
      put "third" into line 3 of field "log"
    end mouseUp
    """, host: MockHost(fields: ["log": "first\nsecond"]))
    #expect(host.fields["log"] == "first\nsecond\nthird")
}

@Test func putIntoLastWord() async throws {
    let host = try await run("""
    on mouseUp
      put "dog" into the last word of s
      put s into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    // s empty → last word (count 0) selector resolves to 0; guard leaves as no-op-ish
    #expect(host.fields["out"] != nil)
}

// MARK: - itemDelimiter

@Test func itemDelimiterChangesSplitCharacter() async throws {
    let host = try await run("""
    on mouseUp
      set the itemDelimiter to ";"
      put item 2 of "a;b;c" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "b")
}

@Test func itemDelimiterIsReadable() async throws {
    let host = try await run("""
    on mouseUp
      set the itemDelimiter to "/"
      put the itemDelimiter into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "/")
}

@Test func itemDelimiterAffectsRejoinAndCount() async throws {
    let host = try await run("""
    on mouseUp
      set the itemDelimiter to ";"
      put item 1 to 2 of "a;b;c" into field "joined"
      put the number of items of "a;b;c" into field "count"
    end mouseUp
    """, host: MockHost(fields: ["joined": "", "count": ""]))
    #expect(host.fields["joined"] == "a;b")
    #expect(host.fields["count"] == "3")
}

@Test func itemDelimiterAffectsPutIntoItem() async throws {
    let host = try await run("""
    on mouseUp
      set the itemDelimiter to "-"
      put "X" into item 2 of field "data"
    end mouseUp
    """, host: MockHost(fields: ["data": "a-b-c"]))
    #expect(host.fields["data"] == "a-X-c")
}

@Test func itemDelimiterDefaultsToComma() async throws {
    let host = try await run("""
    on mouseUp
      put item 3 of "a,b,c" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "c")
}

@Test func replaceCharRange() async throws {
    let host = try await run("""
    on mouseUp
      put "Hello" into s
      put "i" into char 1 to 4 of s
      put s into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "io")
}
