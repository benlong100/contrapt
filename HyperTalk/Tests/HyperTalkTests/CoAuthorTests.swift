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

// MARK: write-side

@Test func writeRequestCarriesInstructionAndCurrentScript() {
    let req = CoAuthor.request(for: .writeScript(objectLabel: "card button \"Go\"",
                                                 instruction: "beep twice when clicked",
                                                 currentScript: "on mouseUp\nend mouseUp"))
    #expect(req.prompt.contains("beep twice when clicked"))
    #expect(req.prompt.contains("on mouseUp"))
    #expect(req.prompt.contains("card button \"Go\""))
    // The model must return code only — no prose, no fences.
    #expect(req.instructions.lowercased().contains("only"))
    #expect(req.instructions.lowercased().contains("fence") || req.instructions.lowercased().contains("markdown"))
}

@Test func writeInstructionsSteerTowardFieldIdioms() {
    // Guards the common LiveCode-ism: `set field "X" to ...` isn't HyperTalk.
    let req = CoAuthor.request(for: .writeScript(objectLabel: "x", instruction: "fill the fields", currentScript: ""))
    let lower = req.instructions.lowercased()
    #expect(lower.contains("put") && lower.contains("into field"))
}

@Test func writePromptMarksAnEmptyCurrentScript() {
    let req = CoAuthor.request(for: .writeScript(objectLabel: "x", instruction: "add a mouseUp", currentScript: "   "))
    #expect(req.prompt.contains("(empty)"))
}

@Test func writeIsActionableOnlyWithAnInstruction() {
    #expect(CoAuthor.isActionable(.writeScript(objectLabel: "x", instruction: "  ", currentScript: "beep")) == false)
    #expect(CoAuthor.isActionable(.writeScript(objectLabel: "x", instruction: "do a thing", currentScript: "")) == true)
}

@Test func sanitizeStripsCodeFences() {
    let fenced = "```hypertalk\non mouseUp\n  beep\nend mouseUp\n```"
    #expect(CoAuthor.sanitizeGeneratedScript(fenced) == "on mouseUp\n  beep\nend mouseUp")
    let bare = "on mouseUp\n  beep\nend mouseUp"
    #expect(CoAuthor.sanitizeGeneratedScript(bare) == bare)
    #expect(CoAuthor.sanitizeGeneratedScript("  \n```\nbeep\n```\n ") == "beep")
}

@Test func sanitizedGeneratedScriptPassesTheParseGuard() throws {
    // The write-side only applies output that parses; a sanitized, valid script
    // clears HyperTalk.check (the guard the app runs before offering Apply).
    let script = CoAuthor.sanitizeGeneratedScript("```\non mouseUp\n  answer \"hi\"\nend mouseUp\n```")
    try HyperTalk.check(script)   // throws if invalid
}

@Test func malformedGeneratedScriptFailsTheParseGuard() {
    let bad = CoAuthor.sanitizeGeneratedScript("on mouseUp\n  repeat\n  -- never closed\nend mouseUp")
    #expect(throws: (any Error).self) { try HyperTalk.check(bad) }
}
