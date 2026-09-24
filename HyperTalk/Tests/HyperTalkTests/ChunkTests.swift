//
//  ChunkTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

@Test func wordByIndex() throws {
    let host = try run("""
    on mouseUp
      put "the quick brown fox" into s
      put word 3 of s into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "brown")
}

@Test func theFirstAndLastWord() throws {
    let host = try run("""
    on mouseUp
      put "the quick brown fox" into s
      put the first word of s & "/" & the last word of s into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "the/fox")
}

@Test func theMiddleWord() throws {
    let host = try run("""
    on mouseUp
      put word 2 of "a b c d e" into x
      put the middle word of "a b c d e" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "c")
}

@Test func charByIndexAndRange() throws {
    let host = try run("""
    on mouseUp
      put char 1 of "Hello" into field "a"
      put char 2 to 4 of "Hello" into field "b"
    end mouseUp
    """, host: MockHost(fields: ["a": "", "b": ""]))
    #expect(host.fields["a"] == "H")
    #expect(host.fields["b"] == "ell")
}

@Test func itemsAreCommaDelimitedKeepingEmpties() throws {
    let host = try run("""
    on mouseUp
      put "a,,c" into s
      put item 2 of s & "|" & item 3 of s into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "|c")
}

@Test func linesSplitOnReturn() throws {
    let host = try run("""
    on mouseUp
      put line 2 of field "src" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["src": "one\ntwo\nthree", "out": ""]))
    #expect(host.fields["out"] == "two")
}

@Test func wordRangeRejoinsWithSpaces() throws {
    let host = try run("""
    on mouseUp
      put word 2 to 3 of "the quick brown fox" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "quick brown")
}

@Test func outOfRangeChunkIsEmpty() throws {
    let host = try run("""
    on mouseUp
      if word 9 of "a b c" is empty then put "empty" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "empty")
}

@Test func nestedChunks() throws {
    let host = try run("""
    on mouseUp
      put the first char of the last word of "the quick brown fox" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "f")
}

@Test func chunkIndexCanBeAnExpression() throws {
    let host = try run("""
    on mouseUp
      put 2 into n
      put word (n + 1) of "a b c d" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "c")
}

@Test func chunkOfAField() throws {
    let host = try run("""
    on mouseUp
      put word 1 of field "name" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["name": "Grace Hopper", "out": ""]))
    #expect(host.fields["out"] == "Grace")
}
