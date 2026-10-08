import Testing
@testable import HyperTalk

@Test func goCardInStackNewWindow() async throws {
    // `in stack` is a synonym for `of stack`, and the trailing
    // `in a new window [without dialog]` modifier is consumed (Sean's Help).
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      go to card 1 in stack "Zzz" in a new window
    end p
    """, host: host, maxSteps: 1000)
    #expect(host.destinations.last == .stack(name: "Zzz", card: .number(1)))
}

@Test func executeUnlocksScreenAtDispatchEnd() async throws {
    // execute(messageLine:) must unlock like send() does — the app's custom
    // menu strip dispatches doMenu through it, and DocumentScriptHost parks a
    // locked-screen cross-stack go until that unlock (Sean's Help: `lock
    // screen` then `go … in stack … in a new window` from a doMenu handler).
    let host = MockHost()
    let layer = ScriptLayer(name: "card", source: """
    on doMenu n
      lock screen
      go to card 1 in stack "Zzz" in a new window
    end doMenu
    """)
    _ = try await HyperTalk.execute(messageLine: "doMenu \"Help...\"", along: [layer], host: host)
    #expect(host.destinations.last == .stack(name: "Zzz", card: .number(1)))
    #expect(host.screenLockHistory.first == true)
    #expect(host.screenLockHistory.last == false)
}
