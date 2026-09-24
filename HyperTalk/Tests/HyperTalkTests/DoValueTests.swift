//
//  DoValueTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

// MARK: - do

@Test func doRunsAStringAsACommand() async throws {
    let host = try await run("""
    on mouseUp
      do "put 6 * 7 into field " & quote & "out" & quote
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "42")
}

@Test func doSeesAndSetsLocalVariables() async throws {
    let host = try await run("""
    on mouseUp
      put 10 into n
      do "put n + 5 into n"
      put n into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "15")
}

@Test func doCanRunSeveralStatements() async throws {
    let host = try await run("""
    on mouseUp
      put "put 1 into a" & return & "put 2 into b" into program
      do program
      put a + b into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "3")
}

@Test func doReportsAParseErrorAtTheDoLine() async throws {
    do {
        try await run("""
        on mouseUp
          do "put 1 2 3"
        end mouseUp
        """)
        Issue.record("Expected a ScriptError")
    } catch let error as ScriptError {
        #expect(error.line == 2)
        #expect(error.message.contains("Can't do"))
    }
}

// MARK: - value

@Test func valueEvaluatesAStringExpression() async throws {
    let host = try await run("""
    on mouseUp
      put the value of "2 + 3 * 4" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "14")
}

@Test func valueFunctionCallForm() async throws {
    let host = try await run("""
    on mouseUp
      put value("10 - 4") into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "6")
}

@Test func valueOfANonExpressionIsItself() async throws {
    let host = try await run("""
    on mouseUp
      put the value of "hello" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "hello")
}

@Test func valueUsesCurrentVariables() async throws {
    let host = try await run("""
    on mouseUp
      put 7 into x
      put the value of "x * 2" into field "out"
    end mouseUp
    """, host: MockHost(fields: ["out": ""]))
    #expect(host.fields["out"] == "14")
}
