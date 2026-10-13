//
//  AskAITests.swift
//  HyperTalk
//
//  `ask <prompt> with ai` — send a prompt to the host's AI provider; reply
//  in `it`, errors in `the result`. A runtime gathering source. The plain
//  `ask … with <default>` form must keep its meaning.
//

import Testing
@testable import HyperTalk

@Test func askWithAIPutsReplyInIt() async throws {
    let host = MockHost()
    host.aiReply = "A stack is a document of cards."
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      ask "What is a stack?" with ai
      put it into msg
    end p
    """, host: host)
    #expect(host.aiPrompts == ["What is a stack?"])
    #expect(host.messages.last == "A stack is a document of cards.")
}

@Test func askWithAIEvaluatesThePromptExpression() async throws {
    let host = MockHost()
    host.aiReply = "ok"
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put "cards" into topic
      ask "Explain" && topic with ai
    end p
    """, host: host)
    #expect(host.aiPrompts == ["Explain cards"])
}

@Test func askWithAIReportsErrorsInTheResult() async throws {
    let host = MockHost()
    host.aiError = "No AI key set."
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      ask "anything" with ai
      put the result into msg
    end p
    """, host: host)
    #expect(host.messages.last == "No AI key set.")
}

@Test func askWithAIClearsTheResultOnSuccess() async throws {
    let host = MockHost()
    host.aiReply = "fine"
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      ask "x" with ai
      put the result into msg
    end p
    """, host: host)
    #expect(host.messages.last == "")
}

@Test func plainAskWithDefaultStillWorks() async throws {
    // `with <expr>` remains the default answer — only a bare `with ai` is
    // the AI form.
    let host = MockHost()
    host.askResponse = "Marmot"
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      ask "Your name?" with "Marmot"
      put it into msg
    end p
    """, host: host)
    #expect(host.aiPrompts.isEmpty)        // the AI provider was never called
    #expect(host.askPrompts.last == "Your name?") // the ordinary ask ran
    #expect(host.messages.last == "Marmot")
}
