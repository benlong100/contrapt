//
//  AST.swift
//  HyperTalk
//

import Foundation

struct ParsedScript {
    /// Handlers keyed by lowercased name.
    let handlers: [String: Handler]
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
    /// `beep` or `beep <count>`.
    case beep(Expr?)
    /// `get <expr>` — evaluates into the variable `it`.
    case get(Expr)
    /// `set [the] <property> of <object> to <value>`.
    case set(property: String, object: ObjectExpr, value: Expr)
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

enum Container {
    case variable(String)
    case field(FieldRef)
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
}

enum BinaryOp {
    case add, subtract, multiply, divide, intDivide, modulo
    case concat, concatWithSpace
    case equal, notEqual, less, greater, lessOrEqual, greaterOrEqual
    case contains
    case and, or
}

enum UnaryOp {
    case minus
    case not
}
