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
    case binary(BinaryOp, Expr, Expr)
    case unary(UnaryOp, Expr)
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
