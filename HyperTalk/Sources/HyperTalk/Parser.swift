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
        var functions: [String: Handler] = [:]
        while true {
            skipNewlines()
            if current.kind == .endOfScript { break }
            if consumeWord("on") {
                let handler = try parseHandler(keyword: "on")
                if handlers[handler.name] != nil {
                    throw ScriptError(line: handler.line, message: "There is more than one handler named '\(handler.name)'.")
                }
                handlers[handler.name] = handler
            } else if consumeWord("function") {
                let function = try parseHandler(keyword: "function")
                if functions[function.name] != nil {
                    throw ScriptError(line: function.line, message: "There is more than one function named '\(function.name)'.")
                }
                functions[function.name] = function
            } else {
                throw ScriptError(line: current.line, message: "Expected 'on <handlerName>' or 'function <name>' here, but found \(describe(current)).")
            }
        }
        return ParsedScript(handlers: handlers, functions: functions)
    }

    private mutating func parseHandler(keyword: String) throws -> Handler {
        let startLine = current.line
        guard let name = peekIdentifier() else {
            throw ScriptError(line: current.line, message: "Expected a name after '\(keyword)'.")
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
        case "global":
            advance()
            var names: [String] = []
            while let name = peekIdentifier() {
                advance()
                names.append(name)
                if !consumeSymbol(",") { break }
            }
            guard !names.isEmpty else {
                throw ScriptError(line: line, message: "Expected one or more variable names after 'global'.")
            }
            try expectNewline()
            return Stmt(kind: .declareGlobals(names), line: line)
        case "return":
            advance()
            let value: Expr? = (current.kind == .newline || current.kind == .endOfScript)
                ? nil : try parseExpression()
            try expectNewline()
            return Stmt(kind: .returnStatement(value), line: line)
        case "beep":
            advance()
            var count: Expr?
            if current.kind != .newline, current.kind != .endOfScript {
                count = try parseExpression()
            }
            try expectNewline()
            return Stmt(kind: .beep(count), line: line)
        case "get":
            advance()
            let expression = try parseExpression()
            try expectNewline()
            return Stmt(kind: .get(expression), line: line)
        case "set":
            advance()
            _ = consumeWord("the")
            guard let property = peekIdentifier() else {
                throw ScriptError(line: line, message: "Expected a property name after 'set'.")
            }
            advance()
            guard consumeWord("of") else {
                throw ScriptError(line: line, message: "Expected 'of' after the property name, like: set the width of button \"OK\" to 200.")
            }
            let object = try parseObjectExpr()
            guard consumeWord("to") else {
                throw ScriptError(line: line, message: "Expected 'to' and a value at the end of 'set'.")
            }
            let value = try parseExpression()
            try expectNewline()
            return Stmt(kind: .set(property: property.lowercased(), object: object, value: value), line: line)
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

        let container = try parseContainer(line: line)
        try expectNewline()
        return Stmt(kind: .put(value, mode, container), line: line)
    }

    /// A put destination: a chunk of a container (`word 2 of field "X"`),
    /// a field, or a variable.
    private mutating func parseContainer(line: Int) throws -> Container {
        if let word = peekIdentifier(), let kind = Self.chunkKinds[word] {
            advance()
            let start = try parsePrimary()
            let selector: ChunkSelector = consumeWord("to")
                ? .range(start, try parsePrimary())
                : .index(start)
            guard consumeWord("of") else {
                throw ScriptError(line: line, message: "Expected 'of' after '\(word)' in a put destination.")
            }
            return .chunk(kind, selector, try parseContainer(line: line))
        }
        let ordinalOffset = peekIdentifier() == "the" ? 1 : 0
        if let ordinalWord = peekIdentifier(ordinalOffset),
           let selector = Self.ordinalSelector(ordinalWord),
           let kindWord = peekIdentifier(ordinalOffset + 1), let kind = Self.chunkKinds[kindWord] {
            if ordinalOffset == 1 { advance() } // the
            advance() // ordinal
            advance() // kind
            guard consumeWord("of") else {
                throw ScriptError(line: line, message: "Expected 'of' after '\(ordinalWord) \(kindWord)'.")
            }
            return .chunk(kind, selector, try parseContainer(line: line))
        }
        if let fieldRef = try parseFieldRefIfPresent() {
            return .field(fieldRef)
        }
        if let name = peekIdentifier() {
            advance()
            return .variable(name)
        }
        throw ScriptError(line: line, message: "Expected a variable, field, or chunk here.")
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
            if consumeWord("id") {
                target = .idExpression(try parseExpression())
            } else {
                target = .expression(try parseExpression())
            }
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

    /// A field-contents reference if one begins here: `field <ref>`,
    /// `card field <ref>`, `background field <ref>`, each with optional
    /// `id`. Returns nil (consuming nothing) otherwise.
    private mutating func parseFieldRefIfPresent() throws -> FieldRef? {
        let domain: HyperTalkObject.PartDomain
        if peekIdentifier() == "field" {
            domain = .any
            advance()
        } else if peekIdentifier() == "card", peekIdentifier(1) == "field" {
            domain = .card
            advance()
            advance()
        } else if peekIdentifier() == "background" || peekIdentifier() == "bg",
                  peekIdentifier(1) == "field" {
            domain = .background
            advance()
            advance()
        } else {
            return nil
        }
        let isID = consumeWord("id")
        return FieldRef(domain: domain, isID: isID, expr: try parsePrimary())
    }

    /// An object reference: typed part (`button "OK"`), `card 3`, or
    /// `this card` / `this background` / `this stack`.
    private mutating func parseObjectExpr() throws -> ObjectExpr {
        let line = current.line
        if consumeWord("this") {
            if consumeWord("card") { return .thisCard }
            if consumeWord("background") { return .thisBackground }
            if consumeWord("stack") { return .thisStack }
            throw ScriptError(line: line, message: "Expected 'card', 'background', or 'stack' after 'this'.")
        }
        let partKinds = ["button", "field", "label", "image"]

        // Domain qualifier: `card field 1` / `background button "OK"`.
        var domain = HyperTalkObject.PartDomain.any
        if peekIdentifier() == "card", let next = peekIdentifier(1), partKinds.contains(next) {
            advance()
            domain = .card
        } else if peekIdentifier() == "background" || peekIdentifier() == "bg",
                  let next = peekIdentifier(1), partKinds.contains(next) {
            advance()
            domain = .background
        }

        if let kind = peekIdentifier(), partKinds.contains(kind) {
            advance()
            if consumeWord("id") {
                return .partByID(kind: kind, domain: domain, id: try parsePrimary())
            }
            return .part(kind: kind, domain: domain, name: try parsePrimary())
        }
        if consumeWord("card") {
            if consumeWord("id") {
                return .cardByID(try parsePrimary())
            }
            return .card(try parsePrimary())
        }
        throw ScriptError(line: line, message: "Expected an object here, like button \"OK\", field \"Name\", card 2, or this card.")
    }

    static let chunkKinds: [String: ChunkKind] = [
        "char": .character, "character": .character, "chars": .character, "characters": .character,
        "word": .word, "words": .word,
        "item": .item, "items": .item,
        "line": .line, "lines": .line,
    ]

    private static let ordinals: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5,
        "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10,
    ]

    /// Parses a clock field if one begins here (after `the`), else nil
    /// without consuming: `date`, `long date`, `time`, `seconds`, `ticks`.
    private mutating func parseClockField() -> ClockField? {
        let first = peekIdentifier()
        let adjectives: Set<String> = ["long", "short", "abbreviated", "abbrev", "abbr"]
        let adjective = adjectives.contains(first ?? "") ? first : nil
        let noun = adjective != nil ? peekIdentifier(1) : first

        switch noun {
        case "date":
            if adjective != nil { advance() }
            advance()
            switch adjective {
            case "long": return .longDate
            case "abbreviated", "abbrev", "abbr": return .abbreviatedDate
            default: return .shortDate
            }
        case "time":
            if adjective != nil { advance() }
            advance()
            return adjective == "long" ? .longTime : .shortTime
        case "seconds", "secs":
            advance()
            return .seconds
        case "ticks":
            advance()
            return .ticks
        default:
            return nil
        }
    }

    /// Maps an ordinal word (or last/middle) to a chunk selector.
    static func ordinalSelector(_ word: String) -> ChunkSelector? {
        if let n = ordinals[word] { return .index(.numberLiteral(Double(n))) }
        if word == "last" { return .last }
        if word == "middle" { return .middle }
        return nil
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
        case .identifier("field"), .identifier("card"), .identifier("background"), .identifier("bg"):
            if let fieldRef = try parseFieldRefIfPresent() {
                return .field(fieldRef)
            }
            // "card"/"background" not followed by "field": fall through to
            // the unquoted-literal behavior.
            if case .identifier(let word) = current.kind {
                advance()
                return .variable(word)
            }
            throw ScriptError(line: current.line, message: "Expected a value here.")
        case .identifier("the"):
            advance()
            // `the result` — the last command/function return value.
            if peekIdentifier() == "result" {
                advance()
                return .result
            }
            // `the [long|short|abbreviated] date/time`, `the seconds/ticks`.
            if let field = parseClockField() {
                return .clock(field)
            }
            // `the length of X` → character count.
            if peekIdentifier() == "length", peekIdentifier(1) == "of" {
                advance() // length
                advance() // of
                return .call("length", [try parsePrimary()])
            }
            // `the number of words of X` → chunk count (but not
            // `the number of this card`, which is a card property).
            if peekIdentifier() == "number", peekIdentifier(1) == "of",
               let kindWord = peekIdentifier(2), let kind = Self.chunkKinds[kindWord] {
                advance() // number
                advance() // of
                advance() // kind
                guard consumeWord("of") else {
                    throw ScriptError(line: line, message: "Expected 'of' after 'the number of \(kindWord)'.")
                }
                return .chunkCount(kind, try parsePrimary())
            }
            // `the first word of X`, `the last line of X`, etc.
            if let ordinalWord = peekIdentifier(),
               let selector = Self.ordinalSelector(ordinalWord),
               let kindWord = peekIdentifier(1), let kind = Self.chunkKinds[kindWord] {
                advance() // ordinal
                advance() // kind
                guard consumeWord("of") else {
                    throw ScriptError(line: line, message: "Expected 'of' after '\(ordinalWord) \(kindWord)'.")
                }
                return .chunk(kind, selector, try parsePrimary())
            }
            // `the <property> of <object>`; otherwise "the" is a noise
            // word before a value ("the date" → the unquoted literal).
            if peekIdentifier() != nil, peekIdentifier(1) == "of" {
                let property = peekIdentifier()!
                advance() // property
                advance() // of
                return .property(property.lowercased(), try parseObjectExpr())
            }
            return try parsePrimary()
        case .identifier(let word) where Self.chunkKinds[word] != nil:
            // `word 2 of X`, `char 1 to 5 of X`.
            let kind = Self.chunkKinds[word]!
            advance()
            let start = try parsePrimary()
            let selector: ChunkSelector = consumeWord("to")
                ? .range(start, try parsePrimary())
                : .index(start)
            guard consumeWord("of") else {
                throw ScriptError(line: line, message: "Expected 'of' after '\(word)', like: \(word) 2 of field \"Notes\".")
            }
            return .chunk(kind, selector, try parsePrimary())
        case .identifier(let word):
            advance()
            // `name(args)` — a function call. Otherwise a plain variable.
            if case .symbol("(") = current.kind {
                advance()
                var arguments: [Expr] = []
                if case .symbol(")") = current.kind {} else {
                    repeat {
                        arguments.append(try parseExpression())
                    } while consumeSymbol(",")
                }
                guard consumeSymbol(")") else {
                    throw ScriptError(line: line, message: "This function call is missing its closing ')'.")
                }
                return .call(word, arguments)
            }
            return .variable(word)
        default:
            throw ScriptError(line: line, message: "Expected a value here, but found \(describe(current)).")
        }
    }
}
