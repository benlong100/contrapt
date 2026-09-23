//
//  Parser.swift
//  HyperTalk
//

import Foundation

/// Recursive-descent parser producing a `ParsedScript` of handlers.
/// Error messages name what was expected and where — friendly script
/// errors are a founding requirement.
struct Parser {
    private let tokens: [Token]
    private var index = 0

    init(tokens: [Token]) {
        self.tokens = tokens
    }

    static func parse(_ source: String) throws -> ParsedScript {
        var parser = Parser(tokens: try Tokenizer.tokenize(source))
        return try parser.parseScript()
    }

    /// Parses loose statements outside any handler — a message box line.
    static func parseLooseStatements(_ source: String) throws -> [Stmt] {
        var parser = Parser(tokens: try Tokenizer.tokenize(source))
        return try parser.parseLooseStatements()
    }

    /// Parses the whole source as a single expression — a message box line
    /// like `2 + 3` or `field "Name"` that evaluates to a displayed value.
    static func parseSoleExpression(_ source: String) throws -> Expr {
        var parser = Parser(tokens: try Tokenizer.tokenize(source))
        return try parser.parseSoleExpression()
    }

    private mutating func parseLooseStatements() throws -> [Stmt] {
        var statements: [Stmt] = []
        while true {
            skipNewlines()
            if current.kind == .endOfScript { return statements }
            statements.append(try parseStatement(handlerName: "messageBox"))
        }
    }

    private mutating func parseSoleExpression() throws -> Expr {
        skipNewlines()
        let expression = try parseExpression()
        skipNewlines()
        guard current.kind == .endOfScript else {
            throw ScriptError(line: current.line, message: "Expected the end of the line here, but found \(describe(current)).")
        }
        return expression
    }

    // MARK: - Token access

    private var current: Token { tokens[index] }

    private func peekIdentifier(_ offset: Int = 0) -> String? {
        guard index + offset < tokens.count,
              case .identifier(let word) = tokens[index + offset].kind else { return nil }
        return word
    }

    private func peekWords(_ words: [String]) -> Bool {
        for (offset, word) in words.enumerated() where peekIdentifier(offset) != word {
            return false
        }
        return true
    }

    private mutating func advance() {
        if index < tokens.count - 1 { index += 1 }
    }

    private mutating func consumeWord(_ word: String) -> Bool {
        if peekIdentifier() == word {
            advance()
            return true
        }
        return false
    }

    private mutating func consumeSymbol(_ symbol: String) -> Bool {
        if case .symbol(symbol) = current.kind {
            advance()
            return true
        }
        return false
    }

    private mutating func skipNewlines() {
        while current.kind == .newline { advance() }
    }

    private mutating func expectNewline() throws {
        switch current.kind {
        case .newline:
            advance()
        case .endOfScript:
            break
        default:
            throw ScriptError(line: current.line, message: "Expected the end of the line here, but found \(describe(current)).")
        }
    }

    private func describe(_ token: Token) -> String {
        switch token.kind {
        case .identifier(let word): "'\(word)'"
        case .number(let value): "the number \(Value.string(from: value))"
        case .string(let text): "\"\(text)\""
        case .symbol(let symbol): "'\(symbol)'"
        case .newline: "the end of the line"
        case .endOfScript: "the end of the script"
        }
    }

    // MARK: - Script and handlers

    private mutating func parseScript() throws -> ParsedScript {
        var handlers: [String: Handler] = [:]
        while true {
            skipNewlines()
            if current.kind == .endOfScript { break }
            guard consumeWord("on") else {
                throw ScriptError(line: current.line, message: "Expected 'on <handlerName>' here, but found \(describe(current)).")
            }
            let handler = try parseHandler()
            if handlers[handler.name] != nil {
                throw ScriptError(line: handler.line, message: "There is more than one handler named '\(handler.name)'.")
            }
            handlers[handler.name] = handler
        }
        return ParsedScript(handlers: handlers)
    }

    private mutating func parseHandler() throws -> Handler {
        let startLine = current.line
        guard let name = peekIdentifier() else {
            throw ScriptError(line: current.line, message: "Expected a handler name after 'on'.")
        }
        advance()

        var parameters: [String] = []
        while let parameter = peekIdentifier() {
            advance()
            parameters.append(parameter)
            if !consumeSymbol(",") { break }
        }
        try expectNewline()

        let body = try parseStatements(handlerName: name, stopBefore: [["end", name]], blockDescription: "handler '\(name)'", blockLine: startLine)
        advance() // "end"
        advance() // handler name
        try expectNewline()
        return Handler(name: name, parameters: parameters, body: body, line: startLine)
    }

    // MARK: - Statements

    /// Parses statements until one of `stopBefore` word sequences begins a
    /// line. The terminator is left unconsumed.
    private mutating func parseStatements(handlerName: String, stopBefore: [[String]], blockDescription: String, blockLine: Int) throws -> [Stmt] {
        var statements: [Stmt] = []
        while true {
            skipNewlines()
            if current.kind == .endOfScript {
                let expected = stopBefore.map { "'\($0.joined(separator: " "))'" }.joined(separator: " or ")
                throw ScriptError(line: blockLine, message: "The \(blockDescription) is missing its \(expected).")
            }
            if stopBefore.contains(where: { peekWords($0) }) {
                return statements
            }
            // A different 'end ...' (or a stray 'else') here means this block
            // was never closed — point at the block, not the stray word.
            if peekIdentifier() == "end" || peekIdentifier() == "else" {
                let expected = stopBefore.map { "'\($0.joined(separator: " "))'" }.joined(separator: " or ")
                throw ScriptError(line: blockLine, message: "The \(blockDescription) is missing its \(expected).")
            }
            statements.append(try parseStatement(handlerName: handlerName))
        }
    }

    private mutating func parseStatement(handlerName: String) throws -> Stmt {
        let line = current.line
        guard let word = peekIdentifier() else {
            throw ScriptError(line: line, message: "Expected a command here, but found \(describe(current)).")
        }
        switch word {
        case "put":
            advance()
            return try parsePut(line: line)
        case "go":
            advance()
            return try parseGo(line: line)
        case "if":
            advance()
            return try parseIf(handlerName: handlerName, line: line)
        case "repeat":
            advance()
            return try parseRepeat(handlerName: handlerName, line: line)
        case "exit":
            advance()
            if consumeWord("repeat") {
                try expectNewline()
                return Stmt(kind: .exitRepeat, line: line)
            }
            if consumeWord(handlerName) {
                try expectNewline()
                return Stmt(kind: .exitHandler, line: line)
            }
            throw ScriptError(line: line, message: "'exit' must be followed by 'repeat' or the handler name '\(handlerName)'.")
        case "next":
            advance()
            guard consumeWord("repeat") else {
                throw ScriptError(line: line, message: "'next' must be followed by 'repeat'.")
            }
            try expectNewline()
            return Stmt(kind: .nextRepeat, line: line)
        default:
            // An unknown word is a message send: it travels the message
            // path at run time (HyperCard semantics), so `doGreeting "Bill"`
            // can reach a handler defined on the card, background, or stack.
            advance()
            var arguments: [Expr] = []
            if current.kind != .newline, current.kind != .endOfScript {
                repeat {
                    arguments.append(try parseExpression())
                } while consumeSymbol(",")
            }
            guard current.kind == .newline || current.kind == .endOfScript else {
                throw ScriptError(line: line, message: "Can't understand '\(word)'.")
            }
            try expectNewline()
            return Stmt(kind: .send(word, arguments), line: line)
        }
    }

    private mutating func parsePut(line: Int) throws -> Stmt {
        let value = try parseExpression()
        var mode: PutMode?
        if consumeWord("into") { mode = .into }
        else if consumeWord("after") { mode = .after }
        else if consumeWord("before") { mode = .before }

        guard let mode else {
            try expectNewline()
            return Stmt(kind: .put(value, .into, nil), line: line)
        }

        let container: Container
        if consumeWord("field") {
            container = .field(try parsePrimary())
        } else if let name = peekIdentifier() {
            advance()
            container = .variable(name)
        } else {
            throw ScriptError(line: line, message: "Expected a variable or field after '\(String(describing: mode) == "into" ? "into" : "after/before")'.")
        }
        try expectNewline()
        return Stmt(kind: .put(value, mode, container), line: line)
    }

    private mutating func parseGo(line: Int) throws -> Stmt {
        _ = consumeWord("to")
        _ = consumeWord("the")
        let target: GoTarget
        if consumeWord("next") {
            _ = consumeWord("card")
            target = .next
        } else if consumeWord("previous") || consumeWord("prev") {
            _ = consumeWord("card")
            target = .previous
        } else if consumeWord("first") {
            _ = consumeWord("card")
            target = .first
        } else if consumeWord("last") {
            _ = consumeWord("card")
            target = .last
        } else if consumeWord("card") {
            target = .expression(try parseExpression())
        } else {
            throw ScriptError(line: line, message: "Expected a destination after 'go', like 'next card' or 'card 3'.")
        }
        try expectNewline()
        return Stmt(kind: .go(target), line: line)
    }

    private mutating func parseIf(handlerName: String, line: Int) throws -> Stmt {
        let condition = try parseExpression()
        guard consumeWord("then") else {
            throw ScriptError(line: line, message: "Expected 'then' after the condition of 'if'.")
        }

        // Block form: "if <cond> then" followed by a newline.
        if current.kind == .newline {
            advance()
            let thenBody = try parseStatements(handlerName: handlerName, stopBefore: [["else"], ["end", "if"]], blockDescription: "'if' on line \(line)", blockLine: line)
            var elseBody: [Stmt] = []
            if peekWords(["end", "if"]) {
                advance(); advance()
                try expectNewline()
            } else {
                advance() // "else"
                elseBody = try parseElse(handlerName: handlerName, line: line)
            }
            return Stmt(kind: .ifThen(condition: condition, then: thenBody, otherwise: elseBody), line: line)
        }

        // Single-line form: "if <cond> then <statement>", optionally followed
        // by an "else" line.
        let thenBody = [try parseStatement(handlerName: handlerName)]
        var elseBody: [Stmt] = []
        let saved = index
        skipNewlines()
        if consumeWord("else") {
            elseBody = try parseElse(handlerName: handlerName, line: line)
        } else {
            index = saved
        }
        return Stmt(kind: .ifThen(condition: condition, then: thenBody, otherwise: elseBody), line: line)
    }

    /// Parses what follows an already-consumed 'else': a chained 'if', a
    /// block terminated by 'end if', or a single statement.
    private mutating func parseElse(handlerName: String, line: Int) throws -> [Stmt] {
        if peekIdentifier() == "if" {
            let chainLine = current.line
            advance()
            return [try parseIf(handlerName: handlerName, line: chainLine)]
        }
        if current.kind == .newline {
            advance()
            let body = try parseStatements(handlerName: handlerName, stopBefore: [["end", "if"]], blockDescription: "'else' of the 'if' on line \(line)", blockLine: line)
            advance(); advance() // "end" "if"
            try expectNewline()
            return body
        }
        let body = [try parseStatement(handlerName: handlerName)]
        // A single-line else may still be followed by a stray "end if"; accept it.
        let saved = index
        skipNewlines()
        if peekWords(["end", "if"]) {
            advance(); advance()
            try expectNewline()
        } else {
            index = saved
        }
        return body
    }

    private mutating func parseRepeat(handlerName: String, line: Int) throws -> Stmt {
        let kind: RepeatKind
        if current.kind == .newline || consumeWord("forever") {
            kind = .forever
        } else if consumeWord("while") {
            kind = .whileTrue(try parseExpression())
        } else if consumeWord("until") {
            kind = .untilTrue(try parseExpression())
        } else if consumeWord("with") {
            guard let variable = peekIdentifier() else {
                throw ScriptError(line: line, message: "Expected a variable name after 'repeat with'.")
            }
            advance()
            guard consumeSymbol("=") else {
                throw ScriptError(line: line, message: "Expected '=' after the variable in 'repeat with'.")
            }
            let from = try parseExpression()
            var descending = false
            if consumeWord("down") {
                descending = true
            }
            guard consumeWord("to") else {
                throw ScriptError(line: line, message: "Expected 'to' in 'repeat with'.")
            }
            kind = .counting(variable: variable, from: from, to: try parseExpression(), descending: descending)
        } else {
            _ = consumeWord("for")
            let count = try parseExpression()
            _ = consumeWord("times")
            kind = .times(count)
        }
        try expectNewline()
        let body = try parseStatements(handlerName: handlerName, stopBefore: [["end", "repeat"]], blockDescription: "'repeat' on line \(line)", blockLine: line)
        advance(); advance() // "end" "repeat"
        try expectNewline()
        return Stmt(kind: .repeatLoop(kind, body: body), line: line)
    }

    // MARK: - Expressions (lowest to highest precedence)

    private mutating func parseExpression() throws -> Expr {
        try parseOr()
    }

    private mutating func parseOr() throws -> Expr {
        var left = try parseAnd()
        while consumeWord("or") {
            left = .binary(.or, left, try parseAnd())
        }
        return left
    }

    private mutating func parseAnd() throws -> Expr {
        var left = try parseComparison()
        while consumeWord("and") {
            left = .binary(.and, left, try parseComparison())
        }
        return left
    }

    private mutating func parseComparison() throws -> Expr {
        var left = try parseConcatenation()
        while true {
            if consumeSymbol("=") {
                left = .binary(.equal, left, try parseConcatenation())
            } else if consumeSymbol("<>") {
                left = .binary(.notEqual, left, try parseConcatenation())
            } else if consumeSymbol("<=") {
                left = .binary(.lessOrEqual, left, try parseConcatenation())
            } else if consumeSymbol(">=") {
                left = .binary(.greaterOrEqual, left, try parseConcatenation())
            } else if consumeSymbol("<") {
                left = .binary(.less, left, try parseConcatenation())
            } else if consumeSymbol(">") {
                left = .binary(.greater, left, try parseConcatenation())
            } else if peekIdentifier() == "is" {
                advance()
                if consumeWord("not") {
                    left = .binary(.notEqual, left, try parseConcatenation())
                } else {
                    left = .binary(.equal, left, try parseConcatenation())
                }
            } else if peekIdentifier() == "contains" {
                advance()
                left = .binary(.contains, left, try parseConcatenation())
            } else {
                return left
            }
        }
    }

    private mutating func parseConcatenation() throws -> Expr {
        var left = try parseAdditive()
        while true {
            if consumeSymbol("&&") {
                left = .binary(.concatWithSpace, left, try parseAdditive())
            } else if consumeSymbol("&") {
                left = .binary(.concat, left, try parseAdditive())
            } else {
                return left
            }
        }
    }

    private mutating func parseAdditive() throws -> Expr {
        var left = try parseMultiplicative()
        while true {
            if consumeSymbol("+") {
                left = .binary(.add, left, try parseMultiplicative())
            } else if consumeSymbol("-") {
                left = .binary(.subtract, left, try parseMultiplicative())
            } else {
                return left
            }
        }
    }

    private mutating func parseMultiplicative() throws -> Expr {
        var left = try parseUnary()
        while true {
            if consumeSymbol("*") {
                left = .binary(.multiply, left, try parseUnary())
            } else if consumeSymbol("/") {
                left = .binary(.divide, left, try parseUnary())
            } else if peekIdentifier() == "div" {
                advance()
                left = .binary(.intDivide, left, try parseUnary())
            } else if peekIdentifier() == "mod" {
                advance()
                left = .binary(.modulo, left, try parseUnary())
            } else {
                return left
            }
        }
    }

    private mutating func parseUnary() throws -> Expr {
        if consumeSymbol("-") {
            return .unary(.minus, try parseUnary())
        }
        if peekIdentifier() == "not" {
            advance()
            return .unary(.not, try parseUnary())
        }
        return try parsePrimary()
    }

    private mutating func parsePrimary() throws -> Expr {
        let line = current.line
        switch current.kind {
        case .number(let value):
            advance()
            return .numberLiteral(value)
        case .string(let text):
            advance()
            return .stringLiteral(text)
        case .symbol("("):
            advance()
            let inner = try parseExpression()
            guard consumeSymbol(")") else {
                throw ScriptError(line: line, message: "This '(' is missing its closing ')'.")
            }
            return inner
        case .identifier("field"):
            advance()
            return .field(try parsePrimary())
        case .identifier(let word):
            advance()
            return .variable(word)
        default:
            throw ScriptError(line: line, message: "Expected a value here, but found \(describe(current)).")
        }
    }
}
