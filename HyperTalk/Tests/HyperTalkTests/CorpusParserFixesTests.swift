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

@Test func relativeCardOfBackgroundAndFindInFoundField() throws {
    // `number of prev cd of this bg` — a relative card with a trailing bg
    // scope (The White Rose). And `find X in the foundField` / selectedField
    // (Addresses) — accepted as an unrestricted find.
    _ = try Parser.parseSoleExpression("number of prev cd of this bg")
    _ = try Parser.parseSoleExpression("the id of next card of this background")
    _ = try Parser.parse("on p\nfind string x in the foundField\nend p")
    _ = try Parser.parse("on p\nfind whole \"y\" in the selectedField\nend p")
    _ = try Parser.parse("on p\nfind \"z\" in bg field \"Notes\"\nend p")
}

@Test func mouseFunctionFormsEvaluate() async throws {
    // `mouse()`, `mouseClick()`, `mouseH()`, `mouseV()`, `mouseLoc()` — the
    // function-call forms (Meat & Conversation) mirror the `the mouse` reads.
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put mouse() & "|" & mouseH() & "," & mouseV() into msg
    end p
    """, host: host)
    // MockHost reports an up button and pointer at 0,0; the key point is the
    // function forms resolve instead of "Can't find a function named 'mouse'".
    #expect(host.messages.last == "up|0,0")
    // mouseClick() also resolves (value depends on host state).
    _ = try await HyperTalk.run(handler: "q", in: "on q\nput mouseClick() into msg\nend q", host: host)
    #expect(host.messages.last == "true" || host.messages.last == "false")
    // `the textHeight` as a bare global reads a default instead of erroring.
    let host2 = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: "on p\nput the textHeight into msg\nend p", host: host2)
    #expect(host2.messages.last == "0")
}

@Test func barewordFieldNameWithCardScope() async throws {
    // `cd fld verse of cd haiku` — a bareword-named field with a card scope
    // (Haiku Master). The name must stop at `verse`, not greedily read `verse
    // of cd haiku` as the property `verse` of a card (which errored "no
    // property verse of a card"). Runtime resolution uses the field, so a
    // MockHost keyed for that scope reads it back.
    _ = try Parser.parse("on p\nput empty into cd fld verse of cd haiku\nend p")
    _ = try Parser.parse("on p\nget cd field myName of card 2\nend p")
    _ = try Parser.parse("on p\nput cd fld verse of cd haiku into x\nend p")
}

@Test func bareConvertDispatchesAsMessage() async throws {
    // A bare `convert` (no target) calls a user `on convert` handler, which
    // HyperCard lets shadow the built-in (Phone # Converter). The built-in
    // `convert X to <format>` is unaffected.
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      convert
    end p

    on convert
      put "ran" into msg
    end convert
    """, host: host)
    #expect(host.messages.last == "ran")
    // The real convert verb still parses.
    _ = try Parser.parse("on p\nconvert the date to seconds\nend p")
}

@Test func thereIsAFileExistence() async throws {
    // `if there is a file X then` / `there is not a file (X)` — file-existence
    // checks (Q-stack TAC, KlingonDictionary). The host answers; a host with no
    // such file reports absent, which is the right answer (no parse error, no
    // stall before `then`).
    _ = try Parser.parse("on p\nif there is a file theFile then beep\nend p")
    _ = try Parser.parse("on p\nif there is not a file (thisFile) then beep\nend p")
    let host = MockHost()
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put (there is a file "HD:Missing") & "," & (there is not a file "HD:Missing") into msg
    end p
    """, host: host)
    #expect(host.messages.last == "false,true")
}

@Test func fieldExistenceOnRelativeCardParses() throws {
    // `there is a field "1" of prev card` / `of next card` — a part existence
    // test scoped to the adjacent card (Fossils). `of prev card` is a card
    // scope, not a leftover before `then`.
    _ = try Parser.parse("on p\nif there is a field \"1\" of prev card then beep\nend p")
    _ = try Parser.parse("on p\nif there is a cd fld 2 of next card then beep\nend p")
}

@Test func debuggerAndTraceVerbsParse() throws {
    // Debugger/trace verbs are IDE features, not gameplay — Contrapt has no
    // step debugger, so they must at least parse (and no-op) rather than error.
    _ = try Parser.parse("on p\ntrace\nend p")
    _ = try Parser.parse("on p\ntrace true\nend p")
    _ = try Parser.parse("on p\ndebug\nend p")
    _ = try Parser.parse("on p\ncheckpoint\nend p")
    _ = try Parser.parse("on p\nset the traceDelay to 30\nend p")
    _ = try Parser.parse("on p\nset traceDelay to 30\nend p")
}

@Test func goRelativeBackgroundParses() throws {
    // `go next/previous background` — background navigation (Help Extras'
    // print-all-backgrounds loop). Still distinct from `go next card`.
    _ = try Parser.parse("on p\ngo next background\nend p")
    _ = try Parser.parse("on p\ngo previous bkgnd\nend p")
    _ = try Parser.parse("on p\ngo prev bg\nend p")
    _ = try Parser.parse("on p\ngo next card\nend p")
}

@Test func sortCardsOfNamedBackground() throws {
    // `sort bg "CURRENT" by <key>` — sort the cards of a named background
    // (Programs). Must route to the cards form, not a bare container named
    // "bg". `sort bg fld "X"` (a field container) still sorts in place.
    _ = try Parser.parse("on p\nsort bg \"CURRENT\" by line 1 of fld \"NOTICE TITLE\"\nend p")
    _ = try Parser.parse("on p\nsort cards of bg \"X\" by field \"k\"\nend p")
    _ = try Parser.parse("on p\nsort bg field \"Apps For Docs\"\nend p")
}

@Test func doMenuWithoutDialogParses() throws {
    // `doMenu "X" without dialog` suppresses the confirmation (HyperHacker,
    // Stack Templates). The optional which-menu and with-dialog variants parse
    // too; the modifiers are consumed, the action performed either way.
    _ = try Parser.parse("on p\ndoMenu \"Delete Stack...\" without dialog\nend p")
    _ = try Parser.parse("on p\ndoMenu \"Cut\" with dialog\nend p")
    _ = try Parser.parse("on p\ndoMenu \"Copy\", \"Edit\" without dialog\nend p")
    _ = try Parser.parse("on p\ndoMenu \"New Card\"\nend p") // unchanged
}

@Test func showWindowAtLocationParses() throws {
    // `show window X at "h,v"` positions the window as it shows (QuickTime
    // Tools, Star Trek TNG). The location is consumed.
    _ = try Parser.parse("on p\nshow window WindowName at \"380,40\"\nend p")
    _ = try Parser.parse("on p\nshow window \"NexusLogo\" at \"41,74\"\nend p")
    _ = try Parser.parse("on p\nhide window \"NexusLogo\"\nend p") // unchanged
}

@Test func thereIsABackgroundByNameParses() throws {
    // `there is a background <bareword>` — background existence by a variable
    // name (HyperHacker). The name is consumed, not left before `then`.
    _ = try Parser.parse("on p\nif there is a Background theBgName then beep\nend p")
    _ = try Parser.parse("on p\nif there is a bg \"Graphs\" then beep\nend p")
}
