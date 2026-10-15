//
//  IndirectObjectParseTests.swift
//  HyperTalk
//
//  Corpus-sweep residual gaps, Apple-authored idioms (Power Tools, Readymade
//  Buttons/Fields, 10th Anniversary): indirect objects through function calls
//  and chunks of calls, find-in-an-indirect-field, ordinal field containers,
//  and `do <expr> as AppleScript`.
//

import Testing
@testable import HyperTalk

private func parses(_ line: String) -> Bool {
    (try? Parser.parse("on x\n\(line)\nend x")) != nil
}

@Test func chunkOfFunctionResultAsObject() {
    // Power Tools: a property of the object NAMED by a chunk of a call result.
    #expect(parses("put the textHeight of item 1 of theFields() into baseLineSize"))
    #expect(parses("put the scroll of last item of theFields() into x"))
}

@Test func functionResultAsIndirectObject() {
    // Readymade Buttons: the call's value is the object descriptor.
    #expect(parses("set visible of fieldData() to not visible of fieldData()"))
    #expect(parses("set hilite of me to visible of fieldData()"))
    #expect(parses("select after text of fieldData()"))
}

@Test func findInIndirectField() {
    // Readymade Fields: theField holds `word 1 to 3 of the long name of me`
    // (a whole descriptor), and the find is restricted to it.
    #expect(parses("find string oldText in theField"))
    #expect(parses("find whole oldText in theField"))
    // The literal field form still parses.
    #expect(parses("find \"x\" in field \"Notes\""))
}

@Test func ordinalFieldAsContainer() {
    // Readymade Buttons: a just-made field addressed by ordinal.
    #expect(parses("put \"Help for\" && the short name of this stack into last bg fld"))
    #expect(parses("put x into first cd fld"))
    #expect(parses("put x into middle field"))
}

@Test func doAsLanguage() {
    // HyperCard 2.2 OSA: `do <expr> as AppleScript` parses; a non-HyperTalk
    // language is an accepted no-op (Contrapt can't run OSA), HyperTalk runs.
    #expect(parses("do cd fld \"mailscript\" as appleScript"))
    #expect(parses("do theCmd as HyperTalk"))
}

@Test func writingToAFunctionResultErrors() async throws {
    // The expressionValue container is read-only.
    #expect(!parses("put x into item 1 of theFields() thenjunk"))
    let source = "on go\nput 5 into item 1 of theFields()\nend go"
    _ = try Parser.parse(source)   // parses (the error is at run time)
}

@Test func ordinalCardScopeAndFindInternationalVariants() {
    // Imitatio Christi: an exact-ordinal card owner on a field container.
    #expect(parses("put bg fld \"marker\" of second cd into cardNO"))
    // 10th Anniversary: the international qualifier after the style word.
    #expect(parses("find string international globalFind"))
}

@Test func buttonContentsParse() {
    // HyperCard 2.x button contents (popup/list text).
    #expect(parses("put btn \"cover3\" into cd fld \"title\""))      // read
    #expect(parses("put empty into bkgnd btn \"Go Back History\" of card 2")) // write
    #expect(parses("put the contents of btn \"cover1\" into thePicts"))
    #expect(parses("select line empty of bkgnd btn \"Go Back History\" of card 2"))
}
