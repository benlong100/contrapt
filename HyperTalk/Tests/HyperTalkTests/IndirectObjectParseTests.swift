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

@Test func batchFourRoundSeven() {
    // Canada/Central Amer. map games: a quoted word as a put destination is
    // the variable of that name.
    #expect(parses("put 0 into \"score\""))
    // Multi-word strings stay errors.
    #expect(!parses("put 0 into \"two words\""))
}

@Test func batchFiveRoundOne() {
    // Japanese returnKey idiom: a menu by ordinal position.
    #expect(parses("if the name of second menu is \"x\" then beep"))
    // Data Transfer Info.: a juxtaposed send argument joins the message.
    #expect(parses("send sendWhenFound lookingFor to this card"))
    // Disk Information: a field indexed by the target's part number.
    #expect(parses("if folders and card field number of the target is not empty then beep"))
    // Drag&Drop: bare `card` before a keyword is this card.
    #expect(parses("if it is not within the rect of card then beep"))
}

@Test func batchFiveRoundTwo() {
    // Annuaire NET: bare `url` before a connector is a variable.
    #expect(parses("repeat with i=1 to the number of chars of URL\nend repeat"))
    // The Delimiter Fixer: bare `field` at the end of the line is a variable.
    #expect(parses("put it into Field"))
    // CheapSequencer: dangling `of card` is the current card.
    #expect(parses("put \"\" into card field \"SoundName\" of card"))
    // Developer Stack: a put whose value was all comment no-ops.
    #expect(parses("if x then put"))
}

@Test func batchFiveRoundThree() {
    // The Delimiter Fixer: `field` as a handler parameter stays a variable
    // before punctuation or a connector-plus-identifier.
    #expect(parses("ConvertToFixedField item i of Field, line i of columns"))
    #expect(parses("put the number of chars in field into FieldChars"))
    // AOL Mail Reader: a connector word still NAMES a field when punctuation
    // follows it.
    #expect(parses("put \"From:\" && field From & return into exportVar"))
}

@Test func batchFiveRoundFour() {
    // Bare punctuation as literal characters (King Arthur, Area:Perimeter,
    // Bunny-Coder, Dartmouth XCMD's).
    #expect(parses("put ? into cd field \"Your Score\""))
    #expect(parses("put . after card field \"answer\""))
    #expect(parses("if char x of cd fld decoder is i then put % into char x of cd fld decoder"))
    #expect(parses("get DelimitedChunk( cd fld \"Dwarves\", \";\", #, false )"))
    // Castle Quest: a trailing period is part of the number.
    #expect(parses("go to card 39."))
    // Click Scripts: of-less set with an object target.
    #expect(parses("set hilite cd btn 3 to false"))
    // Annuaire NET: url before an operator is a variable.
    #expect(parses("put char 1 to typeAdr of URL &HREF into bg fld \"HREF\""))
}

@Test func batchFiveRoundFive() {
    // PAGER PROG#1: a run of the same mark is one literal.
    #expect(parses("put ######### into BEEPERNUM"))
}

@Test func batchSixRoundOne() {
    // Exploring Multimedia: pass with a quoted message name.
    #expect(parses("pass \"opencard\""))
    // Elektra tool stacks: the folder-choose dialog.
    #expect(parses("answer folder \"Choose a folder:\""))
    // Data1/Data4: adjacent answer factors concatenate ("" & Joker & "").
    #expect(parses("answer \"\"Joker\"\""))
    // EditCard: of-marked-cards find scope; next-bg owners best effort.
    #expect(parses("find string HT in bg fld \"Text\" of marked cards"))
    #expect(parses("get the selectedline of bg btn \"- contents -\" of card 1 of next bg"))
    // FastTab: the debugger palettes as absent windows.
    #expect(parses("put the visible of the variable watcher into varVis"))
}

@Test func batchSixRoundTwo() {
    // fate2:6: tempo may follow the notes.
    #expect(parses("play \"Flute\"  \"c2w  e2w d2w a1w\"  tempo 10"))
    // Financial Portfolio: a parenthesized runtime background in a card count.
    #expect(parses("add the number of cds of bg (item x of bgs) to totCds"))
    // Englisch Ninja: a computed visual-effect name.
    #expect(parses("visual effect any line of visEffectData()"))
    // EnglishCalendar: the value IN a container reads like of.
    #expect(parses("put the value in card field \"year\" into Year"))
}

@Test func batchSixRoundThree() {
    // Cool Address Book: a redundant `is` before a comparison operator.
    #expect(parses("IF the userlevel is < 5 then set userlevel to 5"))
    // Demo Stack: bare card before an operator is this card.
    #expect(parses("repeat until (short id of card = StopSave)\nend repeat"))
    // Ez-Mail: a doubled `with` across a continuation.
    #expect(parses("answer \"What?\" with with \"Read\" or \"Delete\""))
    // Cindy's FC HyperAnalyzer: unmark with a background owner.
    #expect(parses("unmark card \"Template\" of bg \"Users\""))
    // FontCard: last-marked-card field owner (approximated by last).
    #expect(parses("put field FontNameSize of last marked cd into NameSize"))
}

@Test func batchSixRoundFour() {
    // HyperCard 10th Anniversary: quoted junk in a handler's parameter slot.
    #expect((try? Parser.parse("on closeCard \"DMikel\"\nbeep\nend closeCard")) != nil)
    // Know Thyself: a number destination is the variable of that spelling.
    #expect(parses("put 100 into 100"))
    // ECM: reversed type args mean type the key with the modifier.
    #expect(parses("if it is \"Quit\" then type commandkey with \"q\""))
    // Ever Be So Humble / Address Ace: putting into the name property renames.
    #expect(parses("put bg field \"Paths\" into the short name of this cd"))
    #expect(parses("put \"registered\" into short name of me"))
    // ExtractIt!: an answer-file type list.
    #expect(parses("answer file \"Select:\" of type \"PICT\",\"PNTG\""))
    // Flying box: go to home card.
    #expect(parses("go to home card"))
}

@Test func batchSixRoundFive() {
    // floppy labeler: print-all with a page-geometry tail.
    #expect(parses("if it is \"Yes\" then print all cards from 57,13 to 476,317"))
    // Forces and Faces: a concat tail after a print field (first field wins).
    #expect(parses("print card field \"odd page\" && return && card field \"even page\""))
    // Sons1: unmark the Nth marked card.
    #expect(parses("if doWhat is \"Unmark\" then unmark marked cd x"))
    // Font Shower: a bare colon as a set value.
    #expect(parses("set the ItemDelimiter to :"))
}

@Test func batchSevenRoundOne() {
    // HyperCard Roundup (a script-library stack full of real idioms):
    #expect(parses("if there is a background button then beep"))
    #expect(parses("put \"opencard\" into line 2 of the script of card button \"Try Me!\""))
    #expect(parses("pop this card into msg"))
    #expect(parses("pop background"))
    #expect(parses("mark all cards where \"Pizza\" is is in field \"Favorite Foods\""))
    #expect(parses("sort this stack by fld 1 ascending"))
    // StackInfo / Deacon Access: • as an inert literal.
    #expect(parses("put • into line 2 of cd fld pref"))
}

@Test func batchSevenRoundTwo() {
    // 9wordsFrench: a loose-text ask default.
    #expect(parses("ask \"What word do you want to find?\" with Type word and enter return."))
    // Frog Mania!: `of the last card` part owner.
    #expect(parses("show cd fld \"aboutFM\" of the last card"))
    // GRANT WRITER: unquoted dotted file names.
    #expect(parses("open file GRANT.TEXT"))
    #expect(parses("write \"SUMMARY\" to file GRANT.TEXT"))
    // Apple ::e File Decoder: return with a command-style call.
    #expect(parses("return EightBitToSixteenBit lo,hi"))
    // Inline-if returns keep their else.
    #expect(parses("if x then return true else return false"))
    // ADMIN: the selectedLine of an explicit field as a destination.
    #expect(parses("put x into the selectedline of bg fld \"Entries\""))
}

@Test func batchSevenRoundThree() {
    // Geoglossary: a doubled article before this-card.
    #expect(parses("get the number of the this card"))
    // GaW loader: an object reference names the stack after of-stack.
    #expect(parses("go to card \"village\" of stack card field \"name\""))
    // Gradebook: a this-background scope at the end of a condition.
    #expect(parses("if the hilite of cd btn 11 of cd 1 of this bkgnd then beep"))
    // Gradebook: a bare close file closes the open one.
    #expect(parses("close file"))
    // storyboard: an additive card index before a background scope.
    #expect(parses("put the short id of cd i-1 of bg story into bg fld \"**prev\""))
    // guitar.stack / elwins-plethoria: do with command-style args dispatches.
    #expect(parses("do showdialog 3, \"510\",  , ,\"Untitled\" , \"7\",,"))
    #expect(parses("do my_RTF format_record"))
}

@Test func batchSevenRoundFour() {
    // HyperCard Roundup: both spellings of the negated contains.
    #expect(parses("if fld 1 doesn't contain \"Roundup\" then print fld 1"))
    #expect(parses("if fld 1 does not contain \"Roundup\" then print fld 1"))
    // StackInfo / AppleOrder / TimeBook: a dangling & concatenates empty.
    #expect(parses("put return & into line 7 of data"))
    // Gradebook: a background object with a scope chain.
    #expect(parses("send mouseUp to bkgnd \"strays\" of cd 1 of this bkgnd"))
}

@Test func batchSevenRoundFive() {
    // ¡0h! (Esp): `is [not] of <field>` as membership, like `is in`.
    #expect(parses("if me is not of bg field \"listado\" then beep"))
    // Plain property-of comparisons stay intact.
    #expect(parses("if x is the name of this card then beep"))
}

@Test func batchEightRoundOne() {
    // Groovy Pad / HyperDecisionTree: a bare Split is a custom message.
    #expect(parses("Split"))
    // HyperBucks: a two-word message name echoed in exit.
    #expect((try? Parser.parse("on new card\nanswer \"no\"\nexit new card\nend new card")) != nil)
    // DataBase Engine: show with a text chunk (marquee shim) is ignored.
    #expect(parses("show item i of theItems"))
    // Roland: a cursor resource sourced from a named stack.
    #expect(parses("set cursor to Hand from stack \"Roland\""))
    // Another Organizer: a doubled domain qualifier reads as its first word.
    #expect(parses("put the ID of bkgnd card button \"List\" into x"))
}

@Test func batchEightRoundTwo() {
    // Help Stack Builder: length-of as a chunk-range end under suppression.
    #expect(parses("get char offset(\">\",me)+2 to length of me of me"))
    // Apple's Home card: a dangling find does nothing.
    #expect(parses("find string"))
    // HomeWork!: adjacent ask-prompt strings concatenate.
    #expect(parses("ask \"How many?\" \"Note: stuff.\" \"ie: more.\""))
    // House of Multiplication Horror: computed effect name AND speed.
    #expect(parses("visual effect thisEffect thisSpeed to thisImage"))
    // HB LIBRARY: pass tolerates trailing junk.
    #expect(parses("pass closeCard cd btn \"HyperField\""))
    // HAN / Apple ::e: BASIC-style assignments read as put-into.
    #expect(parses("x = x + 1"))
}

@Test func batchEightRoundThree() {
    // Japanese waffle game: trunc-of as a chunk index under suppression.
    #expect(parses("put \"A\" into char trunc of(YOKO/32+2) of line trunc of((trunc of(TATE/32)*2+2) + 25*(GAMEN-1)) of MAP"))
    // Lucky Penny: a quoted flip-through count.
    #expect(parses("show \"65\" cards"))
    // HyperReference: a doubled to in send.
    #expect(parses("send mouseUp to to button \"Help\""))
    // hyperDesktop II: version numbers and bangs join go names.
    #expect(parses("if it = 3 then go HyperTerm 1.7"))
    #expect(parses("if it = 12 then go to Great Scott!"))
}

@Test func batchEightRoundFour() {
    // Roland / Caliban / HS Grouper: lines of only inert punctuation no-op.
    #expect(parses("."))
    #expect(parses("..."))
    // Japanese waffle sequel: the selection reader names a field.
    #expect(parses("put cd fld selectedtext of me into cd fld \"x\""))
}

@Test func batchNineRoundOne() {
    // Hypertype / Sampletype: bare this vs an ordinal card, compared by id.
    #expect(parses("if this is the first card then beep"))
    // Intercom: a menu by position in a menuItem read.
    #expect(parses("if menuItem 1 of last menu contains hyperName then exit repeat"))
    // Apple ::e File Decoder: part as a field-or-button container word.
    #expect(parses("put cccc into card part 1"))
    #expect(parses("repeat with x=1 to the number of words in card part prtNm\nend repeat"))
    // HyperHome: version numbers join unquoted stack names in qualifiers.
    #expect(parses("go to card id 11751 in stack HyperHome v1.4"))
}

@Test func batchNineRoundTwo() {
    // Hyper Expert: bkg as a background word.
    #expect(parses("get line theLineNumber of bkg fld \"Scripts\""))
    // HyperHome: `in to` split across words reads as into.
    #expect(parses("put the long date in to card field \"date\""))
    // HyperGASP: an ordinal chunk as a bare go destination.
    #expect(parses("go to last line of parentCard"))
    #expect(parses("go to last card"))
    // HyperGatekeeper: inverted/trademark marks as inert literals.
    #expect(parses("put (¡) ≠ word 3 of line bSig of BS into item 1 of yup"))
    // HyperPiece: a property of a name expression resolves indirectly.
    #expect(parses("put TMP & return & \"x\" & visible of name of cd btn t into TMP"))
    // FrankUnSchtein: part stays a variable in comparisons.
    #expect(parses("if part is \"A\" then beep"))
}

@Test func batchNineRoundThree() {
    // HyperScience: strings ride along in loose set values.
    #expect(parses("set cursor to loc \"0,0\""))
    // HyperSherlock: an ordinal field with a card scope, in a chunk base.
    #expect(parses("put char 1 to 50 of first field of this card into summary"))
    // HyperTalk e-Book: a selection reader's `of` stays with the outer chunk
    // under suppression.
    #expect(parses("put line 1 to the selectedText of cd btn \"a\" of cd \"b\" of bg btn \"c\" into bg btn \"c\""))
    // Japanese launcher / HyperXchange: disk and program existence kinds.
    #expect(parses("if there is not a disk theDisk then beep"))
    #expect(parses("if there is a program otherHC then beep"))
    // ICL3.1: adjacent strings separate answer buttons.
    #expect(parses("answer \"Print All Labels?\" with \"Yes\" \"cancel\""))
}

@Test func batchTenRoundOne() {
    // KARATEstack: a sound literally named "the" (22 kiai scripts).
    #expect(parses("play the"))
    // Ivory Towers: a bare answer does nothing.
    #expect(parses("answer"))
    // Learn Kana: a bare of-bg scope stops before then.
    #expect(parses("if it is the number of first card of bg then beep"))
    // InvoiceMaker Plus: decorated handler names (on AddBlanks...MM).
    #expect((try? Parser.parse("on AddBlanks...MM\nbeep\nend AddBlanks...MM")) != nil)
}

@Test func batchTenRoundTwo() {
    // LaboratoryToolbox / LottoGlueck: a missing into before a field.
    #expect(parses("put empty  field \"event\""))
    #expect(parses("put empty card field Zufall"))
    // Legal Power: a card count in a bg named by id variable.
    #expect(parses("get the number of cards in bg id searchBg"))
    // To Do: a bare of-stack qualifier is the current stack.
    #expect(parses("if it = 1 then go last card of stack"))
    // Letter Learner / LinksBase: @ and macron as inert literals.
    #expect(parses("put @ into lastLetter"))
    // Lines&Kinetics: the short target.
    #expect(parses("if the short target is \"New X\" then beep"))
    // Listoid: is-less not-in membership.
    #expect(parses("if WName not in \"Message Memory,Find\"\nthen put WName\nelse beep"))
    // Logo 2.1: a field named to.
    #expect(parses("repeat until line i of fld to is empty or line i of fld to is \"end\"\nend repeat"))
    // LOGO POWER: unquoted multiword names after go-to-stack.
    #expect(parses("go to stack Address Book"))
}

@Test func batchTenRoundThree() {
    // MacChef: sort the cards of this stack.
    #expect(parses("sort the cards of this stack by bg field \"Recipe Title\""))
}
