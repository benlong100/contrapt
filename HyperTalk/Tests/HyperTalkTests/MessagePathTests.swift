//
//  MessagePathTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

private func layers(button: String = "", card: String = "", background: String = "", stack: String = "") -> [ScriptLayer] {
    [
        ScriptLayer(name: "button \"Test\" script", source: button,
                    object: .part(kind: "button", domain: .card, reference: .named("Test"), onCard: nil)),
        ScriptLayer(name: "card \"Card 1\" script", source: card, object: .thisCard),
        ScriptLayer(name: "background script", source: background, object: .thisBackground),
        ScriptLayer(name: "stack script", source: stack, object: .thisStack),
    ]
}

@Test func doMenuPerformsBuiltInWhenNotTrapped() async throws {
    let host = MockHost()
    _ = try await run("""
    on mouseUp
      doMenu "New Card"
    end mouseUp
    """, host: host)
    #expect(host.performedMenu == ["New Card"])
}

@Test func doMenuCardAuthoringItemsReachTheHost() async throws {
    // Copy/Cut/Paste Card (like New/Delete Card) travel to the host's
    // performMenu when no handler traps them; the app performs the action.
    let host = MockHost()
    _ = try await run("""
    on mouseUp
      doMenu "Copy Card"
      doMenu "Cut Card"
      doMenu "Paste Card"
    end mouseUp
    """, host: host)
    #expect(host.performedMenu == ["Copy Card", "Cut Card", "Paste Card"])
}

@Test func doMenuPartAuthoringItemsReachTheHost() async throws {
    // New/Clear Button and Field travel to performMenu like the card verbs; the
    // app creates or removes the part.
    let host = MockHost()
    _ = try await run("""
    on mouseUp
      doMenu "New Button"
      doMenu "New Field"
      doMenu "Clear Button"
    end mouseUp
    """, host: host)
    #expect(host.performedMenu == ["New Button", "New Field", "Clear Button"])
}

@Test func scriptPropertyRoundTrips() async throws {
    // `set the script of button …` then reading it back — the plumbing a stack
    // uses to wire up a button it just created (DateBook's fillWeekly).
    let host = MockHost(fields: ["out": ""])
    _ = try await run("""
    on mouseUp
      set the script of card button "Go" to "on mouseUp" & return & "beep" & return & "end mouseUp"
      put the script of card button "Go" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "on mouseUp\nbeep\nend mouseUp")
}

@Test func doMenuHandlerCanTrapTheCommand() async throws {
    // An `on doMenu` that doesn't pass traps the command — no built-in.
    let host = MockHost(fields: ["out": ""])
    _ = try await HyperTalk.send("mouseUp", along: layers(
        card: """
        on mouseUp
          doMenu "New Card"
        end mouseUp
        """,
        background: """
        on doMenu which
          put which into field "out"
        end doMenu
        """), host: host)
    #expect(host.fields["out"] == "New Card")
    #expect(host.performedMenu.isEmpty) // trapped → built-in didn't run
}

@Test func sendMessageToBackgroundDispatchesThere() async throws {
    // `send extendWeekly to bkgnd` runs the background's handler.
    let host = MockHost(fields: ["out": ""])
    _ = try await HyperTalk.send("mouseUp", along: layers(
        card: """
        on mouseUp
          send "greet Bill" to bkgnd
        end mouseUp
        """,
        background: """
        on greet who
          put "hi " & who into field "out"
        end greet
        """), host: host)
    #expect(host.fields["out"] == "hi Bill")
}

@Test func exitToHyperCardAbortsEveryHandler() async throws {
    let host = MockHost(fields: ["out": ""])
    _ = try await run("""
    on mouseUp
      put "a" into field "out"
      helper
      put "b" after field "out"
    end mouseUp
    on helper
      put "h" after field "out"
      exit to HyperCard
      put "x" after field "out"
    end helper
    """, host: host)
    // Neither the rest of helper ("x") nor mouseUp after the call ("b") runs.
    #expect(host.fields["out"] == "ah")
}

@Test func unhandledMessagesBubbleUpThePath() async throws {
    let host = MockHost(fields: ["out": ""])
    let handled = try await HyperTalk.send("mouseUp", along: layers(
        card: """
        on mouseUp
          put "card handled it" into field "out"
        end mouseUp
        """
    ), host: host)
    #expect(handled)
    #expect(host.fields["out"] == "card handled it")
}

@Test func theTargetObjectWinsOverThePath() async throws {
    let host = MockHost(fields: ["out": ""])
    try await HyperTalk.send("mouseUp", along: layers(
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

@Test func messagesReachTheStackLayer() async throws {
    let host = MockHost(fields: ["out": ""])
    let handled = try await HyperTalk.send("openCard", along: layers(
        stack: """
        on openCard
          put "stack saw it" into field "out"
        end openCard
        """
    ), host: host)
    #expect(handled)
    #expect(host.fields["out"] == "stack saw it")
}

@Test func unhandledTopLevelMessageReturnsFalse() async throws {
    let handled = try await HyperTalk.send("openCard", along: layers(), host: MockHost())
    #expect(handled == false)
}

@Test func customMessagesTravelThePathWithArguments() async throws {
    let host = MockHost(fields: ["out": ""])
    try await HyperTalk.send("mouseUp", along: layers(
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

@Test func handlersCanCallHandlersInTheirOwnScript() async throws {
    let host = MockHost(fields: ["out": ""])
    try await HyperTalk.send("mouseUp", along: layers(
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

@Test func missingArgumentsBindAsEmpty() async throws {
    let host = MockHost(fields: ["out": ""])
    try await HyperTalk.send("mouseUp", along: layers(
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

@Test func variablesAreLocalToEachHandler() async throws {
    let host = MockHost(fields: ["out": ""])
    try await HyperTalk.send("mouseUp", along: layers(
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

@Test func unhandledCustomMessageIsAFriendlyError() async throws {
    do {
        try await HyperTalk.send("mouseUp", along: layers(
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

@Test func runawayMessageRecursionIsStopped() async {
    await #expect(throws: ScriptError.self) {
        try await HyperTalk.send("mouseUp", along: layers(
            button: """
            on mouseUp
              mouseUp
            end mouseUp
            """
        ), host: MockHost())
    }
}

@Test func errorsNameTheLayerTheyCameFrom() async throws {
    do {
        try await HyperTalk.send("mouseUp", along: layers(
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

@Test func aBrokenUpperLayerCannotBreakAHandlingButton() async throws {
    let host = MockHost(fields: ["out": ""])
    // The stack script has a syntax error, but the button handles mouseUp
    // itself — lazy parsing means the broken layer is never consulted.
    try await HyperTalk.send("mouseUp", along: layers(
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

@Test func standaloneRunStillWorksWithoutContext() async throws {
    do {
        try await HyperTalk.run(handler: "mouseUp", in: """
        on mouseUp
          put 1 / 0 into x
        end mouseUp
        """, host: MockHost())
        Issue.record("Expected a ScriptError")
    } catch let error as ScriptError {
        #expect(error.context == nil)
    }
}

@Test func passContinuesToTheNextObject() async throws {
    let host = MockHost(fields: ["a": "", "b": ""])
    let handled = try await HyperTalk.send("mouseUp", along: layers(
        button: """
        on mouseUp
          put "button" into field "a"
          pass mouseUp
        end mouseUp
        """,
        card: """
        on mouseUp
          put "card" into field "b"
        end mouseUp
        """
    ), host: host)
    #expect(handled)
    #expect(host.fields["a"] == "button") // button ran first
    #expect(host.fields["b"] == "card")    // then passed to the card
}

@Test func passWithNoFurtherHandlerIsHarmless() async throws {
    let host = MockHost(fields: ["a": ""])
    // The button passes and nothing below handles it — no error, message ends.
    _ = try await HyperTalk.send("mouseUp", along: layers(
        button: """
        on mouseUp
          put "button" into field "a"
          pass mouseUp
        end mouseUp
        """
    ), host: host)
    #expect(host.fields["a"] == "button")
}

@Test func statementsAfterPassDoNotRun() async throws {
    let host = MockHost(fields: ["a": ""])
    _ = try await HyperTalk.send("mouseUp", along: layers(
        button: """
        on mouseUp
          pass mouseUp
          put "should not run" into field "a"
        end mouseUp
        """
    ), host: host)
    #expect(host.fields["a"] == "")
}
