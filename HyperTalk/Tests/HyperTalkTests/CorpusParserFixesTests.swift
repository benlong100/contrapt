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
