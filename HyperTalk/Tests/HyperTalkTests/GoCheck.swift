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
