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

@Test func commandsRunFromTheMessageBox() throws {
    let host = MockHost()
    let result = try HyperTalk.execute(messageLine: "go to next card", along: cardPath(), host: host)
    #expect(result == nil)
    #expect(host.destinations == [.next])
}

@Test func putLandsInTheMessageBox() throws {
    let host = MockHost()
    let result = try HyperTalk.execute(messageLine: "put 6 * 7", along: cardPath(), host: host)
    #expect(result == nil)
    #expect(host.messages == ["42"])
}

@Test func bareExpressionsEvaluateAndReturnTheirValue() throws {
    let host = MockHost()
    let result = try HyperTalk.execute(messageLine: "2 + 3 * 4", along: cardPath(), host: host)
    #expect(result == "14")
}

@Test func fieldExpressionsShowTheFieldContents() throws {
    let host = MockHost(fields: ["name": "Bill"])
    let result = try HyperTalk.execute(messageLine: "field \"Name\"", along: cardPath(), host: host)
    #expect(result == "Bill")
}

@Test func customMessagesDispatchAlongThePath() throws {
    let host = MockHost(fields: ["out": ""])
    let result = try HyperTalk.execute(
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

@Test func fieldErrorsAreSpecificNotCantUnderstand() throws {
    do {
        _ = try HyperTalk.execute(messageLine: "field \"Nope\"", along: cardPath(), host: MockHost())
        Issue.record("Expected a ScriptError")
    } catch let error as ScriptError {
        #expect(error.message.contains("Nope"))
    }
}

@Test func nonsenseIsAFriendlyError() throws {
    do {
        _ = try HyperTalk.execute(messageLine: "frobnicate 1, 2", along: cardPath(), host: MockHost())
        Issue.record("Expected a ScriptError")
    } catch let error as ScriptError {
        #expect(error.message.contains("frobnicate"))
    }
}

@Test func multipleStatementsSeparatedByNewlinesRun() throws {
    let host = MockHost(fields: ["out": ""])
    _ = try HyperTalk.execute(
        messageLine: "put \"a\" into field \"out\"\nput \"b\" after field \"out\"",
        along: cardPath(),
        host: host
    )
    #expect(host.fields["out"] == "ab")
}
