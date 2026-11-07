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

@Test func theMessageBoxReadsAsAValue() async throws {
    // `the message box` / `msg` as an expression — its current contents.
    // Power Tools: `if the message box is not empty then …`; Phone: `first
    // char of the message box`.
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      put "Dial 5551234" into the message box
      if the message box is not empty then put first char of msg into field "out"
      put the message box after field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "DDial 5551234")
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

@Test func messageBoxVariablesPersistAcrossLines() async throws {
    // HyperCard's contract: variables used in the Message box are globals.
    // Each typed line runs in a fresh Runtime, so without the global store
    // a counter would reset between lines.
    let host = MockHost()
    _ = try await HyperTalk.execute(messageLine: "put 41 into counter", along: cardPath(), host: host)
    _ = try await HyperTalk.execute(messageLine: "put counter + 1 into counter", along: cardPath(), host: host)
    let shown = try await HyperTalk.execute(messageLine: "counter", along: cardPath(), host: host)
    #expect(shown == "42")
}

@Test func itSurvivesToTheNextMessageBoxLine() async throws {
    // The iPad hand-test that caught this: `answer file ""` then `put it`
    // showed the literal word "it" — the chosen path had died with the
    // first line's frame.
    let host = MockHost()
    host.answerFilePrompts = []
    host.answerFileResponse = "Disk:Folder:Picked File"
    _ = try await HyperTalk.execute(messageLine: "answer file \"\"", along: cardPath(), host: host)
    _ = try await HyperTalk.execute(messageLine: "put it", along: cardPath(), host: host)
    #expect(host.messages.last == "Disk:Folder:Picked File")
}

@Test func handlerLocalsStayLocalWhenRunFromTheMessageBox() async throws {
    // The global fallback belongs to the loose frame only: a handler
    // dispatched FROM the message box still gets ordinary local variables.
    let host = MockHost()
    host.globals["x"] = "global"
    _ = try await HyperTalk.execute(
        messageLine: "probe",
        along: cardPath(card: """
        on probe
          put "local" into x
          put x into the message box
        end probe
        """),
        host: host
    )
    #expect(host.globals["x"] == "global")
}
