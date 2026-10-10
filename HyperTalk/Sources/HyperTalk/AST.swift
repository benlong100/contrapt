//
//  AST.swift
//  HyperTalk
//

import Foundation

struct ParsedScript {
    /// Message handlers (`on …`) and user functions (`function …`), each
    /// keyed by lowercased name.
    let handlers: [String: Handler]
    let functions: [String: Handler]
}

struct Handler {
    let name: String
    let parameters: [String]
    let body: [Stmt]
    let line: Int
}

/// The scripted-menu statements (see StmtKind.menuCommand).
enum MenuCommand {
    case createMenu(Expr)
    case deleteMenu(Expr)
    case deleteMenuItem(MenuItemSelector, menu: Expr)
    case putIntoMenu(menu: Expr, items: Expr, mode: PutMode, messages: Expr?)
    case setEnabled(menu: Expr, item: MenuItemSelector?, enabled: Bool)
    case resetMenuBar
}

/// How a menu item is addressed: by name/number expression or an ordinal.
enum MenuItemSelector {
    case expr(Expr)
    case ordinal(Ordinal)
}

struct Stmt {
    let kind: StmtKind
    let line: Int
}

indirect enum StmtKind {
    case put(Expr, PutMode, Container?)
    case go(GoTarget)
    case ifThen(condition: Expr, then: [Stmt], otherwise: [Stmt])
    case repeatLoop(RepeatKind, body: [Stmt])
    case exitRepeat
    case nextRepeat
    case exitHandler
    /// `exit to HyperCard` — abort the entire handler chain, back to idle.
    case exitToHyperCard
    /// `global a, b` — declares names global for the enclosing handler.
    case declareGlobals([String])
    /// `return <expr>` — exits the handler/function, yielding a value.
    case returnStatement(Expr?)
    /// `beep` or `beep <count>`.
    case beep(Expr?)
    /// `get <expr>` — evaluates into the variable `it`.
    case get(Expr)
    /// `set [the] <property> of <object> to <value>`.
    case set(property: String, object: ObjectExpr, value: Expr)
    /// `set the textStyle/textFont/textSize of <chunk> of <field> to …` —
    /// per-run styled text written from script (import already carries runs).
    case setChunkProperty(property: String, chunk: Container, value: Expr)
    /// `set the itemDelimiter to <value>` — a global (object-less) property.
    case setGlobalProperty(String, Expr)
    /// `convert <target> [from <format>] to <format>` — reformats a date or
    /// time. A container is rewritten in place; a bare value lands in `it`.
    case convert(ConvertTarget, from: [ConvertFormat], to: [ConvertFormat])
    /// `do <expr>` — evaluate a string and run it as HyperTalk statements in
    /// the current handler's context.
    case doCommand(Expr)
    /// `answer <prompt> [with <b1> [or <b2> [or <b3>]]]` — a modal choice;
    /// the clicked button's label lands in `it`.
    case answer(Expr, buttons: [Expr])
    /// `ask <prompt> [with <default>]` — a modal text prompt; the entered
    /// text (empty if cancelled) lands in `it`.
    case ask(Expr, initialAnswer: Expr?)
    /// `answer file <prompt> [of type <filter>]` — a file-open dialog. Contrapt
    /// can't present one mid-script, so it simulates a cancel (empty `it`, the
    /// result "Cancel"), which stacks treat as "no file chosen".
    case answerFile(Expr, type: Expr?)
    /// `visual [effect] <effect> [<direction>] [<speed>]` — queues a screen
    /// transition for the next `go`.
    case visualEffect(ScreenEffect)
    /// `wait <n> [seconds|ticks]`, `wait until <cond>`, `wait while <cond>`.
    case wait(WaitKind)
    /// `find [chars|word|whole|string] <text> [in <field>]` — full-text
    /// search across the stack, boxing and navigating to the first match.
    case find(FindMode, text: Expr, inField: FieldRef?)
    /// `push [this] card` — remember the current card for a later `pop`.
    case pushCard
    /// `pop card [into <container>]` — return to (or read) the pushed card.
    case popCard(Container?)
    /// `lock screen` / `unlock screen` — while the screen is locked, a
    /// cross-window `go home`/`go stack` defers to unlock (the classic
    /// invisible peek-and-pop at Home). In-stack navigation is unaffected.
    case setScreenLocked(Bool)
    /// A recognized-but-ignored statement (e.g. `show menuBar`) — parsed so
    /// old stacks don't error on things Contrapt has no concept of.
    case noOp
    /// `delete <chunk> of <container>` — removes the chunk and its
    /// delimiter (delete item 2 of "a,b,c" is "a,c"). Always a `.chunk`.
    case deleteChunk(Container)
    /// Custom menus: `create menu X`, `delete menu X`, `delete menuItem I of
    /// menu X`, `put <items> into menu X [with menuMessages <msgs>]`,
    /// `enable/disable menu X / menuItem I of menu X`, `reset menubar`.
    case menuCommand(MenuCommand)
    /// File I/O — `open file f`, `read from file f until d / for n`,
    /// `write x to file f [at eof/N]`, `close file f`. Failures report via
    /// `the result` (not script errors), as in HyperCard. `read` fills `it`.
    case openFile(Expr)
    case closeFile(Expr)
    case readFile(file: Expr, until: Expr?, count: Expr?)
    case writeFile(value: Expr, file: Expr, atEOF: Bool, at: Expr?)
    /// `pass <message>` — stop this handler and let the message continue down
    /// the object path to the next handler.
    case passMessage
    /// `send <message> to <object>` — dispatch a message starting at a
    /// specific object's layer (then down the path from there).
    case sendMessage(Expr, to: ObjectExpr)
    /// `add`/`subtract`/`multiply`/`divide` — arithmetic commands that update a
    /// container in place (`add 1 to x`, `subtract 5 from field "n"`).
    case arithmetic(BinaryOp, amount: Expr, container: Container)
    /// `sort [cards] [ascending|descending] [text|numeric] by <expr>` — reorder
    /// the stack's cards by a key evaluated on each card.
    case sortCards(ascending: Bool, numeric: Bool, key: Expr)
    /// `sort [lines|items of] <container> [ascending|descending]
    /// [text|numeric] [by <expr>]` — sort a container's lines or items in
    /// place. A nil key sorts by the element itself; in the key expression,
    /// `each` names the element being ranked.
    case sortContainer(items: Bool, container: Container, ascending: Bool, numeric: Bool, key: Expr?)
    /// `split <container> by <delim>` — turn the container's delimited text
    /// into an associative array keyed 1…n; `combine <container> by <delim>`
    /// — join an array's values back into delimited text (Contrapt structured
    /// data). The delimiter defaults to comma.
    case splitContainer(container: Container, delimiter: Expr?)
    case combineContainer(container: Container, delimiter: Expr?)
    /// `post <data> to url <expr>` — HTTP POST; the reply lands in `it` and
    /// errors in `the result`. `delete url <expr>` — HTTP DELETE.
    case postToURL(data: Expr, url: Expr)
    case deleteURL(Expr)
    /// `mark`/`unmark` a card's `marked` property: `mark card N`, `mark all
    /// cards`, `mark cards where <condition>` (and the `unmark` forms).
    case setMarked(mark: Bool, MarkTarget)
    /// `start using stack <name>` / `stop using stack <name>` — add/remove an
    /// auxiliary stack from the message hierarchy, so its handlers/functions
    /// are reachable from the current stack.
    case startUsing(Expr)
    case stopUsing(Expr)
    /// `doMenu <item>` — send a `doMenu` message (so handlers can trap it),
    /// then perform the built-in menu action if nothing traps it.
    case doMenu(Expr)
    /// `play <voice> [tempo <n>] [<notes>]` — play a named sound, optionally
    /// as a melody (see PlayNotes for the notes-string grammar).
    case play(voice: Expr, tempo: Expr?, notes: Expr?)
    /// `play stop` — silence the current sound.
    case playStop
    /// `click at <h>,<v>` — a synthetic click at a card location. The second
    /// expression is nil when the point arrives as one `"h,v"` value.
    case clickAt(Expr, Expr?)
    /// `drag from h,v to h,v [with key…]` — scripted painting's stroke (and
    /// HyperCard's input synthesis; modifier keys are accepted and ignored).
    case drag(fromH: Expr, fromV: Expr?, toH: Expr, toV: Expr?)
    /// `reset paint` — paint globals back to defaults.
    case resetPaint
    /// `open printing [with dialog]` — start a print session batching every
    /// `print card` until `close printing`.
    case openPrinting(withDialog: Bool)
    // (PrintCardSelection is declared at file scope below StmtKind.)
    case closePrinting
    /// `print [this] card` / `print all cards` / `print marked cards` /
    /// `print <n> cards`.
    case printCards(PrintCardSelection)
    /// `print [card|bkgnd] field <ref>` — the field's text.
    case printField(ObjectExpr)
    /// `type <expr> [with commandKey]` — keystrokes at the insertion point
    /// (the script selection); with commandKey it's a shortcut, not text.
    case typeText(Expr, withCommandKey: Bool)
    /// `choose <name> tool` — switch the scripting tool. With the button or
    /// field tool chosen, `click at` *selects* the part under the point (for
    /// `doMenu "Clear Button"`) instead of clicking it; `choose browse tool`
    /// restores normal clicking. Paint tools are accepted and ignored.
    case chooseTool(String)
    /// `select …` — set (or clear) the script selection in a field: `select
    /// empty`, `select [the] text of field 1`, `select before/after text of
    /// field 1` (a collapsed selection at an end), `select line 2 of field 1`
    /// (any chunk-of-field container).
    case select(SelectTarget)
    /// An unknown command: a message that travels the message path at run
    /// time, e.g. `greet "Bill", 3`.
    case send(String, [Expr])
}

/// What a `select` statement selects.
indirect enum SelectTarget {
    case empty
    case textOf(FieldRef)
    case beforeText(FieldRef)
    case afterText(FieldRef)
    /// A chunk-of-field container (`line 2 of field 1`, `char 3 to 9 of
    /// line 2 of field "Topics"`).
    case chunk(Container)
    /// `select [before|after] text of <container>` where the container isn't a
    /// plain field ref — `me`, `the target`, or a variable holding a field
    /// descriptor (`select text of me`, `select after text of myField`).
    /// Resolves the container to its field and selects the whole text, or
    /// collapses to the start/end.
    case textOfContainer(Container, edge: TextEdge)
    /// `select the clickLine` / `select the selectedLine` — an expression
    /// whose *value* is a chunk descriptor, re-parsed at run time.
    case descriptor(Expr)
}

/// Which end of a field's text `select [before|after] text of …` lands on.
enum TextEdge { case whole, before, after }

enum PutMode {
    case into
    case after
    case before
}

/// A field addressed for its *contents* — `field "Name"`, `card field 1`,
/// `background field id 6` — in expressions and as a put container.
struct FieldRef {
    var domain: HyperTalkObject.PartDomain
    var isID: Bool
    var expr: Expr
    /// `field "X" of <card>` — which card the field lives on (nil = current).
    var card: CardRef? = nil
}

/// A card named as the owner of a field: `field "X" of prev card`,
/// `field 1 of card "About"`.
indirect enum CardRef {
    case current
    case next
    case previous
    case first
    case last
    /// `card <expr>` — a number or a name, decided at run time.
    case expression(Expr)
    /// `card id <expr>`.
    case idExpression(Expr)
    /// `<first|last|N> card of background <name>` — scoped to a background;
    /// a nil name (`of bkgnd` bare, `of this bkgnd`) means the current one.
    case inBackground(CardRef, background: Expr?)
    /// `marked card <expr>` — the Nth marked card (`field "X" of marked card n`).
    case markedCard(Expr)
}

/// What a `mark`/`unmark` command applies to.
indirect enum MarkTarget {
    /// `mark [this] card` / `mark card N` — one card (nil = the current card).
    case card(CardRef?)
    /// `mark all cards`.
    case allCards
    /// `mark cards where <condition>` — every card the condition is true on.
    case cardsWhere(Expr)
}

indirect enum Container {
    case variable(String)
    case field(FieldRef)
    /// `me` as a container in a field's script — the field's contents
    /// (`put empty into me` in a closeField handler).
    case me
    /// `[the] target` as a container — the contents of the field the current
    /// message was dispatched to (`select line 2 of the target`).
    case target
    /// The message box: `put x into message` / `msg`. Writing shows it.
    case messageBox
    /// `[the] selection` — the currently selected text. Reading gives the
    /// selected text; writing replaces it (`put X into the selection`). Resolved
    /// at run time to the selected field and character range.
    case selection
    /// `[the] foundChunk` as a container — the chunk the last `find` matched
    /// (`put X after the foundChunk` / `delete the foundChunk`, the search-and-
    /// replace idiom). Resolved at run time to the found field + char range.
    case foundChunk
    /// A chunk of another container: `word 2 of field "X"`.
    case chunk(ChunkKind, ChunkSelector, Container)
    /// An associative-array element as a destination: `put x into a["k"]`.
    /// The base is the array container; writes decode → set key → re-encode.
    case element(key: Expr, base: Container)
    /// `url "https://…"` as a destination — `put <body> into url "…"` is an
    /// HTTP PUT. Errors land in `the result`.
    case url(Expr)
    /// `stackData` as a destination — the stack's persistent key-value store
    /// (an associative array backed by disk). Usually written through an
    /// element (`stackData["k"]`); writing the base replaces the whole store.
    case persistent
}

/// What `convert` operates on: a container (rewritten in place) or a bare
/// source expression like `the date` (whose result lands in `it`).
indirect enum ConvertTarget {
    case container(Container)
    case expression(Expr)
}

/// How long / until what a `wait` command pauses.
indirect enum WaitKind {
    case duration(Expr, WaitUnit)
    case untilTrue(Expr)
    case whileTrue(Expr)
}

enum WaitUnit {
    case seconds, ticks // a tick is 1/60 second
}

indirect enum GoTarget {
    case next
    case previous
    case first
    case last
    /// `go to any card` — a random card in the stack.
    case any
    /// `go [to] this card` — re-navigate to the current card (a stay/refresh,
    /// common in an `else` branch: "do nothing, stay here").
    case current
    case expression(Expr)
    case idExpression(Expr)
    /// `go home` — open the Home stack.
    case home
    /// `go back` — return to the previously viewed card (browser history).
    case back
    /// `go <first|last|N> card of background <name>`; a nil name (`of
    /// bkgnd` bare, `of this bkgnd`) means the current background.
    case inBackground(GoTarget, background: Expr?)
    /// `go [to] stack "X"` or `go card N of stack "X"` — another stack, with
    /// an optional card destination within it (nil = the stack's first card).
    case inStack(name: Expr, card: GoTarget?)
    /// `go [to] marked card <expr>` — the Nth marked card.
    case markedCard(Expr)
    /// `go next/previous marked card` — the next/previous marked card from the
    /// current one, wrapping around.
    case relativeMarked(forward: Bool)
    /// `go first/last/middle/any marked card` — a positional marked card,
    /// resolved against the live marked-card count.
    case markedCardOrdinal(Ordinal)
    /// `go next/previous background` — the first card of the adjacent
    /// background (in stack order, wrapping). Resolved to a concrete card by
    /// the host so no new `GoDestination` case is needed.
    case relativeBackground(forward: Bool)
}

indirect enum RepeatKind {
    case forever
    case times(Expr)
    case whileTrue(Expr)
    case untilTrue(Expr)
    case counting(variable: String, from: Expr, to: Expr, descending: Bool)
    /// `repeat for each key K in <array>` / `repeat for each element E in
    /// <array>` — iterate an associative array's keys or values (Contrapt
    /// structured data).
    case forEachKey(variable: String, array: Expr)
    case forEachElement(variable: String, array: Expr)
}

indirect enum Expr {
    /// `the number of menus` / `the number of menuItems of menu <name>` —
    /// counted against the host's scripted menu bar.
    case menuCount
    case menuItemCount(Expr)
    case stringLiteral(String)
    case numberLiteral(Double)
    /// Bare identifier: a variable — or, if never assigned, its own name
    /// (HyperTalk's unquoted literal behavior).
    case variable(String)
    case field(FieldRef)
    /// `the <property> of <object>`.
    case property(String, ObjectExpr)
    /// `the textStyle of line 2 of field "X"` — a text-run property (textFont,
    /// textSize, textStyle) of a chunk of a field. The container resolves to a
    /// field and a character range; the run property is read over that range
    /// (uniform value, or "mixed").
    case chunkProperty(String, Container)
    /// `array[key]` — an associative-array element read (Contrapt's structured
    /// data). The base evaluates to an encoded array; the key selects an
    /// element (empty when absent). Nests: `data["a"]["b"]`.
    case element(key: Expr, base: Expr)
    /// `url "https://…"` — an HTTP GET; the response body. Errors land in
    /// `the result` (empty on success). Pairs with JSONDecode.
    case urlContent(Expr)
    /// `stackData` — the stack's persistent key-value store as an associative
    /// array. Read whole, or indexed (`stackData["k"]`) via `.element`.
    case persistentData
    /// `the keys of <array>` — the element keys, one per line.
    case arrayKeys(Expr)
    /// `the number of elements of <array>` — how many top-level elements.
    case elementCount(Expr)
    /// A chunk of text: `word 2 of X`, `char 1 to 5 of X`, `the last line of X`.
    case chunk(ChunkKind, ChunkSelector, Expr)
    /// `the number of words of X` — how many chunks of a kind are in X.
    case chunkCount(ChunkKind, Expr)
    /// `the number of (<expr>)` — a count whose noun is computed at run time,
    /// e.g. Power Tools' `the number of (item i of list & "s")` → "cd btns".
    /// The value is re-parsed as a countable when evaluated.
    case countDynamic(Expr)
    /// `the number of cards / fields / [card|bkgnd] buttons`, etc.
    case count(Countable)
    /// `the number of cds of bg <expr>` where the background is named by a
    /// runtime expression (a variable) — `the number of cds of bg bgNum`. The
    /// static-scope forms (`of bg "X"`, `of bg 2`, `of this bg`) stay `.count`.
    case cardCountInBackground(Expr)
    /// A function call in an expression: `myFunc(a, b)`, `length(x)`.
    case call(String, [Expr])
    /// `the result` — the value returned by the last command/function.
    case result
    /// A global (object-less) property, e.g. `the itemDelimiter`.
    case globalProperty(String)
    /// `the date`, `the long time`, `the seconds`, etc.
    case clock(ClockField)
    /// `the foundText` / `foundChunk` / `foundLine` / `foundField`.
    case found(FoundField)
    /// `the selectedLine` / `selectedText` / `selectedChunk` / `selectedField`.
    case selected(SelectionComponent)
    /// Bare `me` as a value: a field's script reads its own contents
    /// (HyperCard 2.x); any other object falls back to its name.
    case meValue
    /// `[the] message [box|window]` / `msg` read as a value — the message box's
    /// current contents.
    case messageBoxValue
    /// `the clickLine` / `the clickText` — the host's last locked-field click.
    case click(ClickField)
    /// `X is [not] a[n] <type>` — a type test (number, integer, point, rect,
    /// logical). Result is true/false.
    case isType(Expr, String, negated: Bool)
    /// `there is a[n] <object>` / `there is no <object>` — an existence test.
    case exists(ObjectExpr, negated: Bool)
    case binary(BinaryOp, Expr, Expr)
    case unary(UnaryOp, Expr)
}

/// The units a chunk expression addresses.
enum ChunkKind {
    case character, word, item, line
}

/// Which unit(s) a chunk selects.
indirect enum ChunkSelector {
    case index(Expr)            // word 2  (ordinals first…tenth become a literal)
    case range(Expr, Expr)      // word 2 to 4
    case last
    case middle
    case any                    // `any item of X` — a random chunk
}

/// An object reference in source: `button "OK"`, `card field 1`,
/// `button id 6`, `card 3`, `card id 12`, `this card`.
indirect enum ObjectExpr {
    /// `card` scopes the part to another card (`cd btn id 8 of cd "Stack
    /// Menus"`); nil means the current card.
    case part(kind: String, domain: HyperTalkObject.PartDomain, name: Expr, card: CardRef?)
    case partByID(kind: String, domain: HyperTalkObject.PartDomain, id: Expr, card: CardRef?)
    case card(Expr)
    case cardByID(Expr)
    /// A card object scoped to a background: `card "Color" of bkgnd "Content"`,
    /// `card 2 of bg "Paths"`. `base` is one of the card object cases above; a
    /// nil background means `of this bkgnd` (the current card's). Resolves to a
    /// `GoDestination` carrying the scope, like `go cd X of bkgnd "Y"`.
    case cardInScope(base: ObjectExpr, background: Expr?)
    /// A card relative to the current one as an object — `the id of next card`,
    /// `the short name of prev card`. Resolved to a concrete card at run time.
    case cardRelative(CardRef)
    /// `marked card <expr>` as an object — `the short name of marked card 2`.
    case markedCard(Expr)
    case thisCard
    case thisBackground
    case thisStack
    /// `me` — the object whose script is currently running.
    case me
    /// `the target` — the object the current message was first sent to.
    case target
    /// `menu "X"` / `menuItem N of menu "X"` — HyperCard menus, which Contrapt
    /// doesn't model. Parses so `there is a menu …` (false) and `delete menu …`
    /// (no-op) don't break old stacks that manage their own menus.
    case menu(Expr)
    /// `menuItem <sel> of menu <name>` — a custom menu's item, for property
    /// reads/sets (name, enabled, checkMark, menuMessage).
    case menuItem(MenuItemSelector, menu: Expr)
    /// `the message box` / `msg` / `message window` — HyperCard's message box.
    /// Contrapt shows it via `put` with no destination but doesn't model its
    /// `visible` property, so `visible of msg box` reads false and setting it
    /// is a no-op — enough for stacks that save/restore it around a task.
    case messageBox
    /// `window "Tools"`, `card window`, `tool window` — HyperCard palette and
    /// document windows, which Contrapt doesn't model. Parses so old stacks
    /// that save/restore or reposition their windows (`the visible of window
    /// "X"`, `set the loc of window "AddColor" to …`) import and run: the
    /// property reads empty and setting it is a no-op.
    case window(Expr)
    /// `last cd btn`, `middle field`, `any button` — a part by a positional
    /// keyword (`first`…`tenth` are exact and parse to `.part` with a numeric
    /// index instead). Resolved against the live count when evaluated.
    case partByOrdinal(kind: String, domain: HyperTalkObject.PartDomain, ordinal: Ordinal)
    /// `last card`, `middle cd` — a card by a positional keyword.
    case cardByOrdinal(Ordinal)
    /// A container whose *value* names the object — `set loc of theButton to …`
    /// where `theButton` holds "cd btn id 34". The value is re-parsed as an
    /// object descriptor when evaluated (HyperCard's indirect reference).
    case indirect(Expr)
    /// `stack "Audio Help"` / `stack Home` — a stack other than the current
    /// one. Contrapt doesn't resolve arbitrary stacks as objects, so it reads
    /// as absent (`there is a stack X` → false) with name-echoing properties.
    case stackNamed(Expr)
    /// `file <expr>` — a disk file named by a classic path, used in
    /// `there is a[ not] file theFile` (existence). Only meaningful in an
    /// existence test; the host answers whether the file is present.
    case file(Expr)
}

/// A positional keyword that resolves against a live count: `last`, `middle`,
/// `any`. Exact positions (`first`…`tenth`) don't need this — they parse to a
/// plain numeric index.
enum Ordinal: Equatable {
    case last, middle, any
}

enum BinaryOp {
    case add, subtract, multiply, divide, intDivide, modulo, power
    case within
    case concat, concatWithSpace
    case equal, notEqual, less, greater, lessOrEqual, greaterOrEqual
    case contains
    case and, or
}

enum UnaryOp {
    case minus
    case not
}

/// Which cards `print` renders.
public enum PrintCardSelection: Sendable, Equatable {
    case current
    case all
    case marked
    /// This card and the next n-1 in order.
    case count(Int)
}
