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

// MARK: - IA batch 1 gaps (2026-10-15)

@Test func emptyCallArgumentSlots() {
    // Empty slots are empty arguments, as HyperCard passes them.
    #expect(parses("ShowDialog 3,531,\"\",\"\",,4"))                       // ColorPaint
    #expect(parses("playPICS fld PICSPath,128,,0,0,cd fld frames,1,true")) // E-Z Animate
    #expect(parses("put SectionName(,theCard) into x"))                    // Dracula
}

@Test func clickLineAndSelectedChunkAsContainers() {
    #expect(parses("put \"• \" before the clickLine"))                   // FontIndexer
    #expect(parses("set the textStyle of the clickLine to holder"))
    #expect(parses("put tab & return after the selectedChunk"))          // War of the Worlds
    #expect(parses("put noEOL(selTx) into the selectedChunk"))           // EmailLog
    #expect(parses("if the textstyle of item 1 of the clickLine is plain then beep"))  // TimeBook
}

@Test func readAtOffsetParses() {
    #expect(parses("read from file filename at 0 until end"))     // Cloze Text
    #expect(parses("read from file filename at 00000 for 30000"))
}

@Test func quotedGlobalsAndWindowPoints() {
    #expect(parses("global \"mapper\""))                 // GeoDraw
    #expect(parses("show window \"tools\" at 527,10"))   // DoodlePaint
    #expect(parses("if there is a menuitem p+1 of menu \"Go To\" then beep"))  // <- GoTo ->
    #expect(parses("if there is no application thePath then beep"))            // EmailLog
}

// MARK: - IA batch 1, round 2 (2026-10-15)

@Test func askPasswordAndPrintWith() {
    #expect(parses("Ask password clear \"What is the password?\""))         // EnDec
    #expect(parses("print field \"Name\" with appName"))                    // Documents
    #expect(parses("doMenu \"Home\" in a new window"))                      // 1997 Calendar
}

@Test func quotedWordStatementSendsMessage() {
    // A lone quoted word dispatches as a message — Chicxulub's "flash"
    // reaches the Flash shim; Meal Time's "SuperSearch" its handler.
    #expect(parses("\"flash\""))
    #expect(parses("\"SuperSearch\""))
    // Multi-word or mid-line strings stay errors (author typos).
    #expect(!parses("\"do something here\""))
}

@Test func markedOrdinalsAndIndirectSelectedButton() {
    #expect(parses("if the id of this cd is the id of the first marked cd then beep"))   // BookMaker
    #expect(parses("put the short name of the selectedButton of bg family 1 into x"))    // TimeClock
    #expect(parses("get the script of \"Home\""))                                        // ColorPaint
    #expect(parses("if the short number of this cd is 1 then pass opencard"))            // Fifty Filters
}

@Test func buttonContentsWithBareAndChunkNames() {
    #expect(parses("put empty into bg btn koumoku"))
    #expect(parses("put line 1 of cd fld \"iconIdList\" into btn item 2 of numList"))
    #expect(parses("if cd btn i is k then put the id of cd btn i into ak"))
}

@Test func beepLeavesInlineElse() {
    #expect(parses("if x then beep else play \"boing\""))   // 3C Timer
    #expect(parses("put the number of cards of this bg & return into menu"))  // Billing: menu as variable
}

@Test func playAdjacentQuotedNotesAndPrintGeometry() {
    #expect(parses("play \"Tick.rev\" tempo 140 \"Ce\" \"C\" \"C\" \"C\""))   // Tech Support TimeSaver
    #expect(parses("print bkgnd field \"3\" cards from 0,0 to 510,714"))       // Fossils
}

@Test func fieldSourceAfterChunkRangeIsNotACardOwner() {
    // `the number of lines of cd fld "a"` inside a range end, followed by the
    // REAL `of cd fld "a"` — the card-owner parse must not eat `of cd fld` as
    // `of card <fld…>` (a Japanese icon utility's list rotation).
    #expect(parses("put line 2 to the number of lines of cd fld \"a\" of cd fld \"a\" into y"))
    #expect(parses("put x into line 1 + the number of lines of cd fld \"data\" of cd fld \"data\""))
    // The legitimate card-owner form still parses.
    #expect(parses("put bg fld \"marker\" of card 2 into y"))
    #expect(parses("put field \"x\" of next card into y"))
}

// MARK: - IA batch 2 (2026-10-15)

@Test func negativeTempoAndQuotedCommandArgs() {
    #expect(parses("play yikes tempo -24 w."))                       // Tarot Reader
    #expect(parses("\"Picture\"  \"JOHN WOLF\",  resource"))         // Alliance Redwoods
    #expect(parses("\"Picture\"  \"Good time\",  resource,roundrect"))
}

@Test func chunkKeywordAsPlainVariableName() {
    // `item` is the loop variable, not a chunk — `after` can't start an index.
    #expect(parses("put cd fld item after list"))                    // AFI Catalog
    #expect(parses("put cd fld item before list"))
    // Real chunks keep parsing.
    #expect(parses("put item 2 of x after list"))
}

@Test func selectedLineAsContainer() {
    #expect(parses("put \"Other…\" into the selectedLine of me"))    // ArrayMaster
    #expect(parses("put x into the selectedLine"))
}

@Test func macSymbolLettersInIdentifiers() {
    #expect(parses("put offset (∆,line (c) of readTour)-1 into editTour"))  // Aloun-Madu
    #expect(parses("put 5 into ∆"))
}

@Test func parenthesizedHandlerParamsAndVisualTail() {
    #expect((try? Parser.parse("on grebe (old)\nput old\nend grebe")) != nil)   // Achievement of Arms
    #expect(parses("visual scrollAlong (that)"))                                 // Tarot Reader
}

@Test func batchTwoRoundThree() {
    #expect(parses("sort bg button \"section\""))                              // Address Ace: contents sort
    #expect(parses("doMenu \"Copy Card\" with OptionKey"))                     // PR
    #expect(parses("put the number of the last marked card into q"))           // AOL Mail Reader
    #expect(parses("put the contents of me into bg field mapItem of bg LocalMaps"))  // Apollo 11
    #expect(parses("put there is a scriptingLanguage AppleScript into g"))     // Annuaire NET
    #expect(parses("set cantmodify this stack to false"))                      // In the Raindrop
    #expect(parses("if menuItem X of menu \"Application\" contains \"AOL\" then beep"))  // Tarot AOL
    #expect(parses("put menuItem 2 of menu \"F\" into x"))
}

@Test func batchTwoRoundFour() {
    #expect(parses("put content into last cd btn"))                           // Codebits: ordinal button contents
    #expect(parses("put \"You're here.\" in background field \"message\""))   // Adventstation: put-in
    #expect(parses("put theNewText into the selectedfield"))                  // AFI Catalog
    #expect(parses("put x into bg fld \"page\" of card laPremiere + i - 1"))  // Archivist: additive card owner
    #expect(parses("hide fieldText \"Top Field\""))                           // Animals & Sound: XCMD noun
    #expect(parses("set menuMessage of menuItem 1 of menu \"Apple\" to send mouseUp to bg btn \"Uss\""))  // HyperDark
    #expect(parses("set the menuMsg of menuItem \"Save...\" of menu \"File\" to doMenu \"Save a Copy...\""))  // AOL Mail
}

// MARK: - IA batch 3 (2026-10-15)

@Test func batchThreeRoundOne() {
    #expect(parses("put \"\" into bg fld \"measured\" of card \"analysis\"&i"))  // Beauty for All
    #expect(parses("find word 1 of choosen in bg fld \"jnum\""))                  // BlinkBill: chunk, not style
    #expect(parses("find chars \"ego\" in field \"notes\""))                      // style stays a style
    #expect(parses("get card field \"X\" of card \"About\" of stack \"Copy\""))   // Biorhythm: cross-stack scope
    #expect(parses("select selectedchunk()"))                                     // Book Reporter's Guild
    #expect(parses("select selectedline()"))
    #expect(parses("if selectedchunk() ≠ empty then beep"))
}

@Test func batchThreeRoundTwo() {
    #expect(parses("sort items in line 1 of cd fld ID 142 ascending numeric"))   // Balls!
    #expect(parses("answer \"Please fill in \"\"Lotto 5 / ___\"\" field in Prefs\"")) // doubled quotes
    #expect(parses("put \"\" into x"))                                            // empty string unharmed
    #expect(parses("select clickline()"))                                         // Book Reporter's Guild
    #expect(parses("if theLine is not a text then beep"))                         // Broker's Bailiwick
    #expect(parses("set numberformat to 0.###"))
    #expect(parses("set the numberformat to .#"))
    #expect(parses("put return & accntID after the foundline"))
    #expect(parses("if line 1 of me ≠ line 1 of fld ID then beep"))               // field named "ID"
    #expect(parses("show name of btn stackName"))                                 // BSA Troop Tracker
    #expect(parses("hide the name of btn 3"))
}

@Test func batchThreeRoundThree() {
    #expect(parses("show window id gFindWindow"))                        // BulkChange
    #expect(parses("find whole it in fld \"notes\" in marked cards"))    // Caesar
    #expect(parses("mark it"))                                           // Caesar: card by value
    #expect(parses("if the number of the next card is not 1 then go next card"))  // Broker's
}

@Test func paramAsChunkIndex() {
    // Clinton Issues: `the param of N` inside a chunk index position.
    #expect(parses("put the param of 3 into item 1 of line param of 2 of cd fld \"whatToPrint\""))
}

@Test func batchFourRoundOne() {
    // College Savings Plus: a multi-word unquoted set value reads as text.
    #expect(parses("set the cursor to browse tool"))
    #expect(parses("set textFont of fld 1 to New York"))
    // box monitor / CCVSF.ORG: file-system existence kinds.
    #expect(parses("if there is a document \"intromid\" then put true into x"))
    #expect(parses("if there is not a folder pPath then createFolder pPath"))
    // Real expression errors still fail.
    #expect(!parses("set the cursor to 3 + "))
}

@Test func batchFourRoundTwo() {
    // Buy It Try It: an ordinal chunk as a go destination name.
    #expect(parses("go cd last line of allMarked"))
    // Cindy's Newsmailer: post without `to url` is a custom message.
    #expect(parses("post fileName"))
    #expect(parses("post theData to url theURL"))
    // Cindy's Recipes: `in` scopes the cards sort like `of`.
    #expect(parses("sort cds in this bg by bg fld \"Name\""))
}

@Test func batchFourRoundThree() {
    // HyperDark / Cheese.Cake: menuMessage as raw command text in put-into-menu.
    #expect(parses("put \"Sleep Now...\" into menu \"File\" with menuMessage send mouseUp to bg btn \"Sleep\""))
    #expect(parses("put \"January\" after menu \"Calendar\" with menumsg send mouseup to bg button jan"))
    // Color Tools' comma list still parses as expressions.
    #expect(parses("put theItems into menu \"Tools\" with menuMsg \"AC_Undo\",\"\",\"AddColorDelete\""))
    // CD Stack: the clickLine is complete without `of`; the chunk keeps it.
    #expect(parses("get line word 2 of the clickline of fld \"Card id\""))
}

@Test func batchFourRoundFour() {
    // Annuaire NET: a bare `url` at end of line is a variable, not the container.
    #expect(parses("put line 2 of bg fld \"comments\" into url"))
    // Colorizing HC Aids: this-card scope after an ordinal part is identity.
    #expect(parses("put the id of the last btn of this cd into iden"))
    // Coyote's Functions: a chunk expression names the background; ordinal
    // menuItem put with raw menuMsg text.
    #expect(parses("put short name of bkgnd item 2 of x into y"))
    #expect(parses("put \"Asia\" after the third menuItem of menu \"Regions\" with MenuMsg go to card \"Asia\""))
}

@Test func batchFourRoundFive() {
    // Compiler Data / ColorPaint EMaker: a lone number line is a message send.
    #expect(parses("111"))
    // Verb Conjugation: hyphenated bare words in a go stack shorthand.
    #expect(parses("go to French-English Translator"))
    // calvin-game: the command modifier spelled as two words.
    #expect(parses("type \"Q\" with command key"))
    // SportsArena: card-then-stack with no card named goes to the stack.
    #expect(parses("go to card stack \"book\""))
}

@Test func batchFourRoundSix() {
    // AFI Catalog: the clickChunk as a container.
    #expect(parses("put theNewText after the clickchunk"))
    // Celestial Wind Carillons: unquoted multi-word stack name (with a
    // trademark sign) after `in stack`.
    #expect(parses("go to card \"first\" in stack Celestial Wind Carillons\u{00AE}"))
    // The windowed form keeps its modifier.
    #expect(parses("go to card 1 in stack \"Sean's World II Help\" in a new window"))
}
