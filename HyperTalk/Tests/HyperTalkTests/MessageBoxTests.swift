//
//  MessageBoxTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

private func cardPath(card: String = "", stack: String = "") -> [ScriptLayer] {
    [
        ScriptLayer(name: "card \"Card 1\" script", source: card),
        ScriptLayer(name: "stack script", source: stack),
    ]
}

@Test func commandsRunFromTheMessageBox() async throws {
    let host = MockHost()
    let result = try await HyperTalk.execute(messageLine: "go to next card", along: cardPath(), host: host)
    #expect(result == nil)
    #expect(host.destinations == [.next])
}

@Test func putLandsInTheMessageBox() async throws {
    let host = MockHost()
    let result = try await HyperTalk.execute(messageLine: "put 6 * 7", along: cardPath(), host: host)
    #expect(result == nil)
    #expect(host.messages == ["42"])
}

@Test func bareExpressionsEvaluateAndReturnTheirValue() async throws {
    let host = MockHost()
    let result = try await HyperTalk.execute(messageLine: "2 + 3 * 4", along: cardPath(), host: host)
    #expect(result == "14")
}

@Test func fieldExpressionsShowTheFieldContents() async throws {
    let host = MockHost(fields: ["name": "Bill"])
    let result = try await HyperTalk.execute(messageLine: "field \"Name\"", along: cardPath(), host: host)
    #expect(result == "Bill")
}

@Test func customMessagesDispatchAlongThePath() async throws {
    let host = MockHost(fields: ["out": ""])
    let result = try await HyperTalk.execute(
        messageLine: "greet \"Bill\"",
        along: cardPath(card: """
        on greet who
          put "Hi," && who into field "out"
        end greet
        """),
        host: host
    )
    #expect(result == nil)
    #expect(host.fields["out"] == "Hi, Bill")
}

@Test func fieldErrorsAreSpecificNotCantUnderstand() async throws {
    do {
        _ = try await HyperTalk.execute(messageLine: "field \"Nope\"", along: cardPath(), host: MockHost())
        Issue.record("Expected a ScriptError")
    } catch let error as ScriptError {
        #expect(error.message.contains("Nope"))
    }
}

@Test func nonsenseIsAFriendlyError() async throws {
    do {
        _ = try await HyperTalk.execute(messageLine: "frobnicate 1, 2", along: cardPath(), host: MockHost())
        Issue.record("Expected a ScriptError")
    } catch let error as ScriptError {
        #expect(error.message.contains("frobnicate"))
    }
}

@Test func multipleStatementsSeparatedByNewlinesRun() async throws {
    let host = MockHost(fields: ["out": ""])
    _ = try await HyperTalk.execute(
        messageLine: "put \"a\" into field \"out\"\nput \"b\" after field \"out\"",
        along: cardPath(),
        host: host
    )
    #expect(host.fields["out"] == "ab")
}
