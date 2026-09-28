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
    /// A recognized-but-ignored statement (e.g. `show menuBar`) — parsed so
    /// old stacks don't error on things Contrapt has no concept of.
    case noOp
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
    /// `doMenu <item>` — send a `doMenu` message (so handlers can trap it),
    /// then perform the built-in menu action if nothing traps it.
    case doMenu(Expr)
    /// `click at <h>,<v>` — a synthetic click at a card location. The second
    /// expression is nil when the point arrives as one `"h,v"` value.
    case clickAt(Expr, Expr?)
    /// An unknown command: a message that travels the message path at run
    /// time, e.g. `greet "Bill", 3`.
    case send(String, [Expr])
}

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
    /// `<first|last|N> card of background <name>` — scoped to a background.
    case inBackground(CardRef, background: Expr)
}

indirect enum Container {
    case variable(String)
    case field(FieldRef)
    /// The message box: `put x into message` / `msg`. Writing shows it.
    case messageBox
    /// A chunk of another container: `word 2 of field "X"`.
    case chunk(ChunkKind, ChunkSelector, Container)
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
    case expression(Expr)
    case idExpression(Expr)
    /// `go home` — open the Home stack.
    case home
    /// `go back` — return to the previously viewed card (browser history).
    case back
    /// `go <first|last|N> card of background <name>`.
    case inBackground(GoTarget, background: Expr)
    /// `go [to] stack "X"` or `go card N of stack "X"` — another stack, with
    /// an optional card destination within it (nil = the stack's first card).
    case inStack(name: Expr, card: GoTarget?)
}

indirect enum RepeatKind {
    case forever
    case times(Expr)
    case whileTrue(Expr)
    case untilTrue(Expr)
    case counting(variable: String, from: Expr, to: Expr, descending: Bool)
}

indirect enum Expr {
    case stringLiteral(String)
    case numberLiteral(Double)
    /// Bare identifier: a variable — or, if never assigned, its own name
    /// (HyperTalk's unquoted literal behavior).
    case variable(String)
    case field(FieldRef)
    /// `the <property> of <object>`.
    case property(String, ObjectExpr)
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
