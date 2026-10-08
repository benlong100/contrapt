//
//  CorpusParserFixesTests.swift
//  Parser gaps found by the corpus-wide runtime audit (164 stacks): chunk
//  keywords used as plain variables, `select text in`, and comma-separated
//  `with menuMsg` lists.
//

import Testing
@testable import HyperTalk

@Test func chunkKeywordAsVariableParses() async throws {
    // `item`/`line`/`word`/`char` are plain variables when not followed by an
    // index + `of` — the `doMenu item` parameter idiom (Insults, The Bee, and
    // dozens more). A real chunk expression still parses.
    let host = MockHost()
    let layer = ScriptLayer(name: "card", source: """
    on doMenu item
      if item is "New Card" then
        put "trapped" into msg
      else
        put item & "!" into msg
      end if
    end doMenu
    """)
    _ = try await HyperTalk.send("doMenu", arguments: ["Quit"], along: [layer], host: host)
    #expect(host.messages.last == "Quit!")

    // A genuine chunk still works after the disambiguation.
    let host2 = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put item 2 of "a,b,c" into msg
    end p
    """, host: host2)
    #expect(host2.messages.last == "b")
}

@Test func selectTextInIsOfSynonym() throws {
    // `select text in <field>` parses (Confusing Words) — `in` == `of`.
    _ = try Parser.parse("on p\nselect text in background field \"temp\"\nend p")
    _ = try Parser.parse("on p\nselect text of card field \"temp\"\nend p")
}

@Test func putIntoMenuWithCommaMenuMsgList() async throws {
    // `put … into menu "X" with menuMsg "a","b","c"` — a comma-separated
    // message list, one per item (Color Tools' Edit menu).
    let host = try await run("""
    on p
      put "Cut,Copy,Paste" into menu "Edit" with menuMsg "doCut","doCopy","doPaste"
    end p
    """, handler: "p")
    let menus = host.menuBarSnapshot()
    #expect(menus.first?.name == "Edit")
    #expect(menus.first?.items.map(\.name) == ["Cut", "Copy", "Paste"])
    #expect(menus.first?.items.map(\.menuMessage) == ["doCut", "doCopy", "doPaste"])
}

@Test func ordinalCardInExpressionsParse() throws {
    // Ordinal card refs in object/qualifier position (Tubers, Journal): `in
    // background` is an of-synonym, and `of first cd` / `of this cd` don't
    // swallow a following comparison.
    _ = try Parser.parseSoleExpression(
        "the number of the first card in background \"X\" is the number of this card")
    _ = try Parser.parseSoleExpression(
        "the visible of cd fld \"Info\" of first cd is true")
    _ = try Parser.parseSoleExpression(
        "the visible of cd fld \"Info\" of this cd is true")
    // Named/numbered card scopes still parse (no regression).
    _ = try Parser.parseSoleExpression("field \"X\" of cd 2 is \"y\"")
    _ = try Parser.parseSoleExpression("field \"X\" of cd id 20 is \"y\"")
}

@Test func trailingCommaInFunctionCall() async throws {
    // `foo(a,b,)` — a trailing comma is an empty final argument (Tubers'
    // selectType("Extras",62,63,157,142,)).
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put joinThree("a","b",) into msg
    end p

    function joinThree x,y,z
      return x & y & z
    end joinThree
    """, host: host)
    #expect(host.messages.last == "ab")
}
