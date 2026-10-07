//
//  NavigationPathTests.swift
//  HyperTalk
//
//  The message path follows navigation: after an in-stack `go`, a handler that
//  sends a message (or lets one travel unhandled) reaches the card it moved to,
//  not the one it started on. This is what lets DateBook's `extend` navigate to
//  the last "Weekly" card and then `send extendWeekly to bkgnd` find that
//  background's handler.
//

import Foundation
import Testing
@testable import HyperTalk

/// A host with two cards, each with its own background script, and a shared
/// stack script. `goToCard` moves the current card; `systemScriptLayers`
/// reports the current card's card/background/stack scripts so the interpreter
/// can refresh the path.
private final class TwoCardHost: HyperTalkHost {
    var current = 0
    var log: [String] = []

    let cardScripts: [String]
    let backgroundScripts: [String]
    let stackScript: String

    init(cardScripts: [String], backgroundScripts: [String], stackScript: String) {
        self.cardScripts = cardScripts
        self.backgroundScripts = backgroundScripts
        self.stackScript = stackScript
    }

    func systemScriptLayers() -> [ScriptLayer]? {
        [
            ScriptLayer(name: "card \(current) script", source: cardScripts[current], object: .thisCard),
            ScriptLayer(name: "background \(current) script", source: backgroundScripts[current], object: .thisBackground),
            ScriptLayer(name: "stack script", source: stackScript, object: .thisStack),
        ]
    }

    func goToCard(_ destination: GoDestination, effects: [ScreenEffect]) async throws {
        switch destination {
        case .next: current = min(current + 1, cardScripts.count - 1)
        case .previous: current = max(current - 1, 0)
        case .first: current = 0
        case .last: current = cardScripts.count - 1
        case .number(let n): current = max(0, min(n - 1, cardScripts.count - 1))
        default: break
        }
    }

    // The handlers under test record what ran via `log` through this command.
    func showMessage(_ text: String) { log.append(text) }

    // Unused host surface.
    func fieldText(_ r: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, onCard: GoDestination?) throws -> String { "" }
    func setFieldText(_ r: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, onCard: GoDestination?, to text: String) throws {}
    func beep() {}
    func propertyValue(_ p: String, of o: HyperTalkObject) throws -> String { "" }
    func setProperty(_ p: String, of o: HyperTalkObject, to v: String) throws {}
    func globalValue(_ n: String) -> String? { nil }
    func setGlobalValue(_ n: String, to v: String) {}
    func clock(_ f: ClockField) -> String { "" }
    func convert(_ v: String, from: [ConvertFormat], to: [ConvertFormat]) throws -> String { "" }
    func answer(_ p: String, buttons: [String]) async -> String { "" }
    func ask(_ p: String, initialAnswer: String) async -> String? { nil }
    func answerFile(_ p: String, type: String?) async -> String? { nil }
    func wait(seconds: Double) async {}
    func exists(_ o: HyperTalkObject) -> Bool { false }
    func find(_ t: String, mode: FindMode, inField: HyperTalkObject.Reference?, fieldDomain: HyperTalkObject.PartDomain) throws -> Bool { false }
    func foundValue(_ f: FoundField) -> String { "" }
    func count(_ c: Countable) throws -> Int { 0 }
    func setSortContext(_ i: Int?) {}
    func reorderCards(_ o: [Int]) throws {}
    func performMenu(_ i: String) throws {}
    func click(x: Int, y: Int) {}
    func pushCard() {}
    func popCard() -> String? { nil }
}

/// Builds the initial path for card 0 — a button layer plus card 0's
/// card/background/stack scripts — matching how the app dispatches a click.
private func pathForCard0(button: String, host: TwoCardHost) -> [ScriptLayer] {
    [
        ScriptLayer(name: "button script", source: button,
                    object: .part(kind: "button", domain: .card, reference: .id("1"), onCard: nil)),
        ScriptLayer(name: "card 0 script", source: host.cardScripts[0], object: .thisCard),
        ScriptLayer(name: "background 0 script", source: host.backgroundScripts[0], object: .thisBackground),
        ScriptLayer(name: "stack script", source: host.stackScript, object: .thisStack),
    ]
}

@Test func sendToBackgroundAfterGoReachesTheNewCardsBackground() async throws {
    // The stack handler navigates to card 2, then sends a message to `bkgnd`.
    // Only card 2's background defines the handler — so it runs only if the
    // path followed the navigation.
    let host = TwoCardHost(
        cardScripts: ["", ""],
        backgroundScripts: [
            "", // card 0's background: no `extendWeekly`
            "on extendWeekly\nput \"ran on card 2 bg\"\nend extendWeekly",
        ],
        stackScript: """
        on go2AndSend
          go to card 2
          send "extendWeekly" to bkgnd
        end go2AndSend
        """
    )
    let button = """
    on mouseUp
      go2AndSend
    end mouseUp
    """
    _ = try await HyperTalk.send("mouseUp", along: pathForCard0(button: button, host: host), host: host)
    #expect(host.current == 1)
    #expect(host.log == ["ran on card 2 bg"])
}

@Test func unhandledMessageAfterGoTravelsTheNewCardsScripts() async throws {
    // An unhandled command dispatched after navigation should find the new
    // card's card-script handler, not the starting card's.
    let host = TwoCardHost(
        cardScripts: [
            "on ping\nput \"card 0\"\nend ping",
            "on ping\nput \"card 1\"\nend ping",
        ],
        backgroundScripts: ["", ""],
        stackScript: ""
    )
    let button = """
    on mouseUp
      go next
      ping
    end mouseUp
    """
    _ = try await HyperTalk.send("mouseUp", along: pathForCard0(button: button, host: host), host: host)
    #expect(host.current == 1)
    #expect(host.log == ["card 1"])
}

@Test func pathStaysFixedWhenHostOptsOut() async throws {
    // A host returning nil from systemScriptLayers keeps the classic fixed
    // path: MockHost never refreshes, so this is just a smoke check that a
    // navigating handler still runs without error.
    let host = MockHost(fields: ["out": ""])
    _ = try await run("""
    on mouseUp
      go next
      put "done" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "done")
    #expect(host.destinations == [.next])
}
