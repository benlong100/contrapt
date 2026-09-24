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

enum Container {
    case variable(String)
    case field(Expr)
}

enum GoTarget {
    case next
    case previous
    case first
    case last
    case expression(Expr)
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
    case field(Expr)
    /// `the <property> of <object>`.
    case property(String, ObjectExpr)
    case binary(BinaryOp, Expr, Expr)
    case unary(UnaryOp, Expr)
}

/// An object reference in source: `button "OK"`, `card 3`, `this card`.
indirect enum ObjectExpr {
    case part(kind: String, name: Expr)
    case card(Expr)
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
