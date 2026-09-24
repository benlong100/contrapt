//
//  TargetTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

// `me` and `the target` need a message path whose layers carry object
// identities, so these tests build the path directly rather than using
// the single-layer `run` helper.

@Test func theTargetNamesTheOriginallyTargetedPart() throws {
    let button = HyperTalkObject.part(kind: "button", domain: .card, reference: .named("Greet"))
    let host = MockHost(fields: ["out": ""])
    host.properties["card button Greet.name"] = "card button \"Greet\""
    let layers = [
        ScriptLayer(name: "button script", source: """
        on mouseUp
          doGreet
        end mouseUp
        """, object: button),
        ScriptLayer(name: "card script", source: """
        on doGreet
          put the target into field "out"
        end doGreet
        """, object: .thisCard),
    ]
    _ = try HyperTalk.send("mouseUp", along: layers, host: host)
    #expect(host.fields["out"] == "card button \"Greet\"")
}

@Test func meNamesTheObjectRunningTheScript() throws {
    let field = HyperTalkObject.part(kind: "field", domain: .card, reference: .named("Note"))
    let host = MockHost(fields: ["out": ""])
    host.properties["card field Note.name"] = "card field \"Note\""
    let layers = [
        ScriptLayer(name: "field script", source: """
        on mouseUp
          put the name of me into field "out"
        end mouseUp
        """, object: field),
    ]
    _ = try HyperTalk.send("mouseUp", along: layers, host: host)
    #expect(host.fields["out"] == "card field \"Note\"")
}

@Test func meFollowsTheHandlingLayerWhileTargetStaysAtOrigin() throws {
    let button = HyperTalkObject.part(kind: "button", domain: .card, reference: .named("Btn"))
    let host = MockHost(fields: ["out": ""])
    host.properties["card button Btn.name"] = "Btn"
    host.properties["this card.name"] = "Home"
    let layers = [
        ScriptLayer(name: "button script", source: """
        on mouseUp
          relay
        end mouseUp
        """, object: button),
        ScriptLayer(name: "card script", source: """
        on relay
          put the name of me & "/" & the name of the target into field "out"
        end relay
        """, object: .thisCard),
    ]
    _ = try HyperTalk.send("mouseUp", along: layers, host: host)
    // me is the card (the layer handling `relay`); the target is still the
    // button that first received mouseUp.
    #expect(host.fields["out"] == "Home/Btn")
}

@Test func setAPropertyOfMe() throws {
    let button = HyperTalkObject.part(kind: "button", domain: .card, reference: .named("B"))
    let host = MockHost()
    let layers = [
        ScriptLayer(name: "button script", source: """
        on mouseUp
          set the visible of me to false
        end mouseUp
        """, object: button),
    ]
    _ = try HyperTalk.send("mouseUp", along: layers, host: host)
    #expect(host.properties["card button B.visible"] == "false")
}

@Test func bareMeReadsAsTheObjectsName() throws {
    let button = HyperTalkObject.part(kind: "button", domain: .card, reference: .named("Go"))
    let host = MockHost(fields: ["out": ""])
    host.properties["card button Go.name"] = "Go"
    let layers = [
        ScriptLayer(name: "button script", source: """
        on mouseUp
          put me into field "out"
        end mouseUp
        """, object: button),
    ]
    _ = try HyperTalk.send("mouseUp", along: layers, host: host)
    #expect(host.fields["out"] == "Go")
}

@Test func meWithoutAnObjectIsAFriendlyError() throws {
    do {
        _ = try HyperTalk.send("mouseUp", along: [
            ScriptLayer(name: "script", source: """
            on mouseUp
              put the name of me into x
            end mouseUp
            """),
        ], host: MockHost())
        Issue.record("Expected a ScriptError")
    } catch let error as ScriptError {
        #expect(error.message.contains("me"))
    }
}
