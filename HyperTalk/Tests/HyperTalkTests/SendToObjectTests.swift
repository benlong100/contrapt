//
//  SendToObjectTests.swift
//  HyperTalk
//
//  `send <msg> to <object>` — off-path targets run their own scripts, message
//  arguments evaluate in the sender's context, `the target` names the send
//  target, and an unhandled send errors as in HyperCard.
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

@Test func sendToAnOffPathButtonRunsItsScript() async throws {
    // The clicked button sends to ANOTHER button — not on the running path;
    // the host supplies its script and the message dispatches there.
    let host = MockHost(fields: ["out": ""])
    host.objectScripts["button Clock"] = """
    on reset
      put "clock reset" into field "out"
    end reset
    """
    _ = try await HyperTalk.send("mouseUp", along: layers(button: """
    on mouseUp
      send "reset" to card button "Clock"
    end mouseUp
    """), host: host)
    #expect(host.fields["out"] == "clock reset")
}

@Test func sendToAnotherCardRunsItsScript() async throws {
    let host = MockHost(fields: ["out": ""])
    host.objectScripts["card 2"] = """
    on wake
      put "card 2 woke" into field "out"
    end wake
    """
    _ = try await HyperTalk.send("mouseUp", along: layers(button: """
    on mouseUp
      send "wake" to card 2
    end mouseUp
    """), host: host)
    #expect(host.fields["out"] == "card 2 woke")
}

@Test func theTargetInsideASentHandlerNamesTheSendTarget() async throws {
    // A handler reached via `send … to this background` sees the background —
    // not the clicked button — as the target.
    let host = MockHost(fields: ["out": ""])
    host.properties["this background.name"] = "Weekly"
    _ = try await HyperTalk.send("mouseUp", along: layers(
        button: """
        on mouseUp
          send "identify" to this background
        end mouseUp
        """,
        background: """
        on identify
          put the target into field "out"
        end identify
        """), host: host)
    #expect(host.fields["out"] == "Weekly")
}

@Test func theTargetStillNamesTheClickedPartForSystemMessages() async throws {
    // The classic idiom is untouched: a card handler catching a button's
    // mouseUp targets the button.
    let host = MockHost(fields: ["out": ""])
    host.properties["card button Test.name"] = "Test"
    _ = try await HyperTalk.send("mouseUp", along: layers(card: """
    on mouseUp
      put the target into field "out"
    end mouseUp
    """), host: host)
    #expect(host.fields["out"] == "Test")
}

@Test func messageArgumentsEvaluateInTheSendersContext() async throws {
    // 2+3 computes; a variable the sender holds passes its value; a bare word
    // with no value passes verbatim, case intact.
    let host = MockHost(fields: ["out": ""])
    _ = try await HyperTalk.send("mouseUp", along: layers(
        button: """
        on mouseUp
          put "Ann" into who
          send "greet 2+3," && who & ", Bill" to this card
        end mouseUp
        """,
        card: """
        on greet a, b, c
          put a && b && c into field "out"
        end greet
        """), host: host)
    #expect(host.fields["out"] == "5 Ann Bill")
}

@Test func unhandledSendErrors() async throws {
    // Nobody handles it and it isn't an external — HyperCard errors, so do we.
    await #expect(throws: ScriptError.self) {
        try await run("""
        on mouseUp
          send "nonsense" to this card
        end mouseUp
        """)
    }
}

@Test func unhandledSendToAKnownExternalIsANoOp() async throws {
    let host = MockHost()
    host.externalNames = ["generalpalette"]
    _ = try await run("""
    on mouseUp
      send "GeneralPalette" to this card
      beep
    end mouseUp
    """, host: host)
    #expect(host.beeps == 1) // reached the line after the send
}
