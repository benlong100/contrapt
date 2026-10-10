//
//  CoAuthorTests.swift
//  HyperTalk
//
//  The co-author's prompt construction (read-side / explain). The model call is
//  app-side; these lock the shared prompt shape the app feeds it.
//

import Testing
@testable import HyperTalk

@Test func explainRequestCarriesScriptAndOwner() {
    let task = CoAuthorTask.explainScript(objectLabel: "card button \"Save\"",
                                          script: "on mouseUp\n  answer \"Hi\"\nend mouseUp")
    let req = CoAuthor.request(for: task)
    #expect(req.prompt.contains("on mouseUp"))
    #expect(req.prompt.contains("card button \"Save\""))
    // The system instructions orient the model on HyperTalk.
    #expect(req.instructions.contains("HyperTalk"))
}

@Test func explainPromptOmitsOwnerPhraseWhenUnnamed() {
    let req = CoAuthor.request(for: .explainScript(objectLabel: "", script: "on mouseUp\nend mouseUp"))
    #expect(!req.prompt.contains("from "))
    #expect(req.prompt.contains("on mouseUp"))
}

@Test func emptyScriptIsNotActionable() {
    #expect(CoAuthor.isActionable(.explainScript(objectLabel: "x", script: "   \n  ")) == false)
    #expect(CoAuthor.isActionable(.explainScript(objectLabel: "x", script: "on mouseUp\nend mouseUp")) == true)
}

@Test func explainInstructionsDiscourageInvention() {
    let req = CoAuthor.request(for: .explainScript(objectLabel: "x", script: "beep"))
    // Guards against the model hallucinating behavior the script doesn't have.
    #expect(req.instructions.lowercased().contains("do not invent")
            || req.instructions.lowercased().contains("only describe"))
}
