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
    /// `visual [effect] <effect> [<direction>] [<speed>]` — queues a screen
    /// transition for the next `go`.
    case visualEffect(ScreenEffect)
    /// `wait <n> [seconds|ticks]`, `wait until <cond>`, `wait while <cond>`.
    case wait(WaitKind)
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
}

indirect enum Container {
    case variable(String)
    case field(FieldRef)
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

enum GoTarget {
    case next
    case previous
    case first
    case last
    case expression(Expr)
    case idExpression(Expr)
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
    /// A function call in an expression: `myFunc(a, b)`, `length(x)`.
    case call(String, [Expr])
    /// `the result` — the value returned by the last command/function.
    case result
    /// A global (object-less) property, e.g. `the itemDelimiter`.
    case globalProperty(String)
    /// `the date`, `the long time`, `the seconds`, etc.
    case clock(ClockField)
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
    case part(kind: String, domain: HyperTalkObject.PartDomain, name: Expr)
    case partByID(kind: String, domain: HyperTalkObject.PartDomain, id: Expr)
    case card(Expr)
    case cardByID(Expr)
    case thisCard
    case thisBackground
    case thisStack
    /// `me` — the object whose script is currently running.
    case me
    /// `the target` — the object the current message was first sent to.
    case target
}

enum BinaryOp {
    case add, subtract, multiply, divide, intDivide, modulo, power
    case concat, concatWithSpace
    case equal, notEqual, less, greater, lessOrEqual, greaterOrEqual
    case contains
    case and, or
}

enum UnaryOp {
    case minus
    case not
}
