//
//  AnswerAskTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

@Test func answerPutsTheClickedButtonInIt() async throws {
    let host = MockHost(fields: ["out": ""])
    host.answerChoice = "No"
    _ = try await run("""
    on mouseUp
      answer "Save changes?" with "Yes" or "No"
      put it into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "No")
    #expect(host.answerPrompts == ["Save changes?"])
}

@Test func answerDefaultsToFirstButton() async throws {
    let host = MockHost(fields: ["out": ""])
    // No scripted choice → the host returns the first button.
    _ = try await run("""
    on mouseUp
      answer "Pick one" with "Alpha" or "Beta" or "Gamma"
      put it into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "Alpha")
}

@Test func answerWithNoButtonsUsesOK() async throws {
    let host = MockHost(fields: ["out": ""])
    _ = try await run("""
    on mouseUp
      answer "Done!"
      put it into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "OK")
}

@Test func askPutsTheEnteredTextInIt() async throws {
    let host = MockHost(fields: ["out": ""])
    host.askResponse = "Ada"
    _ = try await run("""
    on mouseUp
      ask "What is your name?" with "friend"
      put it into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "Ada")
    #expect(host.askPrompts == ["What is your name?"])
}

@Test func askCancelYieldsEmptyAndSetsTheResult() async throws {
    let host = MockHost(fields: ["out": "", "res": ""])
    host.askResponse = nil // the user cancelled
    _ = try await run("""
    on mouseUp
      ask "Your age?"
      put it into field "out"
      put the result into field "res"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "")
    #expect(host.fields["res"] == "Cancel")
}

@Test func answerPromptCanBeAnExpression() async throws {
    let host = MockHost(fields: ["out": ""])
    host.answerChoice = "OK"
    _ = try await run("""
    on mouseUp
      put "world" into who
      answer "Hello, " & who
      put it into field "out"
    end mouseUp
    """, host: host)
    #expect(host.answerPrompts == ["Hello, world"])
}
