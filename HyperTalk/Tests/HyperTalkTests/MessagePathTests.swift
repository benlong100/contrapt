//
//  MessagePathTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

private func layers(button: String = "", card: String = "", background: String = "", stack: String = "") -> [ScriptLayer] {
    [
        ScriptLayer(name: "button \"Test\" script", source: button),
        ScriptLayer(name: "card \"Card 1\" script", source: card),
        ScriptLayer(name: "background script", source: background),
        ScriptLayer(name: "stack script", source: stack),
    ]
}

@Test func unhandledMessagesBubbleUpThePath() throws {
    let host = MockHost(fields: ["out": ""])
    let handled = try HyperTalk.send("mouseUp", along: layers(
        card: """
        on mouseUp
          put "card handled it" into field "out"
        end mouseUp
        """
    ), host: host)
    #expect(handled)
    #expect(host.fields["out"] == "card handled it")
}

@Test func theTargetObjectWinsOverThePath() throws {
    let host = MockHost(fields: ["out": ""])
    try HyperTalk.send("mouseUp", along: layers(
        button: """
        on mouseUp
          put "button" into field "out"
        end mouseUp
        """,
        card: """
        on mouseUp
          put "card" into field "out"
        end mouseUp
        """
    ), host: host)
    #expect(host.fields["out"] == "button")
}

@Test func messagesReachTheStackLayer() throws {
    let host = MockHost(fields: ["out": ""])
    let handled = try HyperTalk.send("openCard", along: layers(
        stack: """
        on openCard
          put "stack saw it" into field "out"
        end openCard
        """
    ), host: host)
    #expect(handled)
    #expect(host.fields["out"] == "stack saw it")
}

@Test func unhandledTopLevelMessageReturnsFalse() throws {
    let handled = try HyperTalk.send("openCard", along: layers(), host: MockHost())
    #expect(handled == false)
}

@Test func customMessagesTravelThePathWithArguments() throws {
    let host = MockHost(fields: ["out": ""])
    try HyperTalk.send("mouseUp", along: layers(
        button: """
        on mouseUp
          greet "Bill", "!"
        end mouseUp
        """,
        card: """
        on greet who, punctuation
          put "Hi," && who & punctuation into field "out"
        end greet
        """
    ), host: host)
    #expect(host.fields["out"] == "Hi, Bill!")
}

@Test func handlersCanCallHandlersInTheirOwnScript() throws {
    let host = MockHost(fields: ["out": ""])
    try HyperTalk.send("mouseUp", along: layers(
        button: """
        on mouseUp
          double 21
        end mouseUp

        on double n
          put n * 2 into field "out"
        end double
        """
    ), host: host)
    #expect(host.fields["out"] == "42")
}

@Test func missingArgumentsBindAsEmpty() throws {
    let host = MockHost(fields: ["out": ""])
    try HyperTalk.send("mouseUp", along: layers(
        button: """
        on mouseUp
          greet "Bill"
        end mouseUp
        """,
        card: """
        on greet who, punctuation
          if punctuation is empty then
            put "no punctuation" into field "out"
          end if
        end greet
        """
    ), host: host)
    #expect(host.fields["out"] == "no punctuation")
}

@Test func variablesAreLocalToEachHandler() throws {
    let host = MockHost(fields: ["out": ""])
    try HyperTalk.send("mouseUp", along: layers(
        button: """
        on mouseUp
          put "mine" into x
          scramble
          put x into field "out"
        end mouseUp

        on scramble
          put "changed" into x
        end scramble
        """
    ), host: host)
    #expect(host.fields["out"] == "mine")
}

@Test func unhandledCustomMessageIsAFriendlyError() throws {
    do {
        try HyperTalk.send("mouseUp", along: layers(
            button: """
            on mouseUp
              frobnicate
            end mouseUp
            """
        ), host: MockHost())
        Issue.record("Expected a ScriptError")
    } catch let error as ScriptError {
        #expect(error.line == 2)
        #expect(error.message.contains("frobnicate"))
    }
}

@Test func runawayMessageRecursionIsStopped() {
    #expect(throws: ScriptError.self) {
        try HyperTalk.send("mouseUp", along: layers(
            button: """
            on mouseUp
              mouseUp
            end mouseUp
            """
        ), host: MockHost())
    }
}

@Test func errorsNameTheLayerTheyCameFrom() throws {
    do {
        try HyperTalk.send("mouseUp", along: layers(
            button: """
            on mouseUp
              greet
            end mouseUp
            """,
            card: """
            on greet
              put 1 / 0 into x
            end greet
            """
        ), host: MockHost())
        Issue.record("Expected a ScriptError")
    } catch let error as ScriptError {
        #expect(error.context == "card \"Card 1\" script")
        #expect(error.errorDescription?.contains("card \"Card 1\" script") == true)
    }
}

@Test func aBrokenUpperLayerCannotBreakAHandlingButton() throws {
    let host = MockHost(fields: ["out": ""])
    // The stack script has a syntax error, but the button handles mouseUp
    // itself — lazy parsing means the broken layer is never consulted.
    try HyperTalk.send("mouseUp", along: layers(
        button: """
        on mouseUp
          put "fine" into field "out"
        end mouseUp
        """,
        stack: """
        on openCard
          repeat forever
        end openCard
        """
    ), host: host)
    #expect(host.fields["out"] == "fine")
}

@Test func standaloneRunStillWorksWithoutContext() throws {
    do {
        try HyperTalk.run(handler: "mouseUp", in: """
        on mouseUp
          put 1 / 0 into x
        end mouseUp
        """, host: MockHost())
        Issue.record("Expected a ScriptError")
    } catch let error as ScriptError {
        #expect(error.context == nil)
    }
}
