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
    /// While parsing a chunk's index/range (`line <here> of …`), a trailing
    /// `of` belongs to the chunk, not to a bare-property access, so the
    /// `<identifier> of` shortcut is suppressed.
    private var suppressBarePropertyOf = false
    /// Expression-nesting depth, bounded to keep a pathologically nested or
    /// malformed script (deeply parenthesized, runaway operators) from
    /// overflowing the recursive-descent parser's stack and crashing. Real
    /// scripts nest only a handful deep; the limit is far above that.
    private var expressionDepth = 0
    // A backstop against runaway recursion (infinite/absurd nesting) that would
    // overflow the recursive-descent parser's stack. Real scripts DO nest deep
    // — e.g. a 96-level block-form if/else time dispatcher (BMUG's
    // AppointmentMaster) — so the limit is generous; it only trips on clearly
    // pathological input. (Parsing runs on a normal 8MB stack in the app.)
    private static let maxExpressionDepth = 500

    init(tokens: [Token]) {
        self.tokens = tokens
    }

    static func parse(_ source: String) throws -> ParsedScript {
        var parser = Parser(tokens: try Tokenizer.tokenize(source))
        return try parser.parseScript()
    }

    /// Parses a script handler-by-handler, skipping any handler that fails
    /// rather than failing the whole script — HyperCard's per-handler
    /// compilation. Used for in-use auxiliary stacks (big shared libraries),
    /// so one unsupported construct doesn't disable the whole library. Returns
    /// an empty script if the source can't even be tokenized.
    static func parseLenient(_ source: String) -> ParsedScript {
        guard let tokens = try? Tokenizer.tokenize(source) else {
            return ParsedScript(handlers: [:], functions: [:])
        }
        var parser = Parser(tokens: tokens)
        return (try? parser.parseScript(lenient: true)) ?? ParsedScript(handlers: [:], functions: [:])
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

    /// Parses the whole source as a single object descriptor — used to resolve
    /// an indirect reference (`set loc of theButton …` where `theButton` holds
    /// "cd btn id 34") by re-parsing the container's value at run time.
    static func parseSoleObject(_ source: String) throws -> ObjectExpr {
        var parser = Parser(tokens: try Tokenizer.tokenize(source))
        return try parser.parseSoleObject()
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

    private mutating func parseSoleObject() throws -> ObjectExpr {
        skipNewlines()
        let object = try parseObjectExpr()
        skipNewlines()
        guard current.kind == .endOfScript else {
            throw ScriptError(line: current.line, message: "Expected the end of the line here, but found \(describe(current)).")
        }
        return object
    }

    // MARK: - Token access

    private var current: Token { tokens[index] }

    private func peekIdentifier(_ offset: Int = 0) -> String? {
        guard index + offset < tokens.count,
              case .identifier(let word) = tokens[index + offset].kind else { return nil }
        return word
    }

    /// Whether a chunk keyword (`item`/`word`/`line`/`char`) at the current
    /// token is actually starting a chunk expression, versus being used as a
    /// plain variable. HyperCard lets these words name variables (the `doMenu
    /// item` parameter, a `line` counter), so `item is "New Card"` / `put line`
    /// treat the word as a variable. It's a chunk only when the next token can
    /// begin an index — a number, string, `(`, or an index variable/`the` —
    /// not an operator, keyword connector, or line end.
    private func chunkKeywordStartsChunk() -> Bool {
        guard index + 1 < tokens.count else { return false }
        switch tokens[index + 1].kind {
        case .number, .string: return true
        case .symbol(let s): return s == "("
        case .identifier(let w): return !Self.expressionConnectors.contains(w)
        default: return false // newline, end of script, etc.
        }
    }

    private func peekWords(_ words: [String]) -> Bool {
        for (offset, word) in words.enumerated() {
            if peekIdentifier(offset) == word { continue }
            // A quoted handler name also closes its handler: `end "CreditSubs"`
            // matches `["end", "creditsubs"]` (Checking & Savings demo).
            if index + offset < tokens.count,
               case .string(let text) = tokens[index + offset].kind,
               text.lowercased() == word { continue }
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
            // A single-line `if … then <stmt> else <stmt>` ends the then-clause
            // at `else` (and a clause may butt against `end if`) with no newline
            // between — tolerate those without consuming them.
            if peekIdentifier() == "else" || peekIdentifier() == "end" { return }
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

    private mutating func parseScript(lenient: Bool = false) throws -> ParsedScript {
        var handlers: [String: Handler] = [:]
        var functions: [String: Handler] = [:]
        while true {
            skipNewlines()
            if current.kind == .endOfScript { break }
            if consumeWord("on") {
                do {
                    let handler = try parseHandler(keyword: "on")
                    // A duplicate handler is unreachable in HyperCard — message
                    // dispatch scans top-to-bottom, so the FIRST definition wins
                    // and the later one is dead code. Keep the first; don't error
                    // (Cultural Almanac ships with a duplicate closeCard).
                    if handlers[handler.name] == nil { handlers[handler.name] = handler }
                } catch let error as ScriptError {
                    if !lenient { throw error }
                    skipToNextHandler() // a library handler we can't parse — skip it
                }
            } else if consumeWord("function") {
                do {
                    let function = try parseHandler(keyword: "function")
                    if functions[function.name] == nil { functions[function.name] = function }
                } catch let error as ScriptError {
                    if !lenient { throw error }
                    skipToNextHandler()
                }
            } else {
                // Loose text outside any handler — decorative banners, notes,
                // the "MESSAGE HANDLERS IN THIS SCRIPT" comment blocks common in
                // Apple's stacks. HyperCard ignores it; skip the line and go on.
                while current.kind != .newline, current.kind != .endOfScript { advance() }
                if current.kind == .newline { advance() }
            }
        }
        return ParsedScript(handlers: handlers, functions: functions)
    }

    /// Lenient-parse recovery: skip forward to the start of the next handler
    /// (a line beginning `on`/`function`) or the end of the script, so a
    /// handler that failed to parse doesn't take the rest of the library with it.
    private mutating func skipToNextHandler() {
        while current.kind != .endOfScript {
            if current.kind == .newline {
                advance()
                if let word = peekIdentifier(), word == "on" || word == "function" { return }
            } else {
                advance()
            }
        }
    }

    private mutating func parseHandler(keyword: String) throws -> Handler {
        let startLine = current.line
        // The handler name is usually an identifier, but some stacks quote it
        // (`on "CreditSubs" … end "CreditSubs"`) — accept a string too, keyed
        // lowercased like any other handler name.
        let name: String
        if let word = peekIdentifier() {
            name = word
        } else if case .string(let text) = current.kind {
            name = text.lowercased()
        } else {
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
        // Tolerate trailing tokens after `end <name>` — Apple's Home writes
        // `end doMenu which` (echoing the parameter).
        while current.kind != .newline, current.kind != .endOfScript { advance() }
        try expectNewline()
        return Handler(name: name, parameters: parameters, body: body, line: startLine)
    }

    // MARK: - Statements

    /// Parses statements until one of `stopBefore` word sequences begins a
    /// line. The terminator is left unconsumed.
    private mutating func parseStatements(handlerName: String, stopBefore: [[String]], blockDescription: String, blockLine: Int) throws -> [Stmt] {
        // Nested blocks (if/repeat within if/repeat) recurse here; bound the
        // depth so a pathologically nested handler can't overflow the stack.
        expressionDepth += 1
        defer { expressionDepth -= 1 }
        guard expressionDepth <= Self.maxExpressionDepth else {
            throw ScriptError(line: current.line, message: "This handler is nested too deeply.")
        }
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
            // `exit to HyperCard` — abort every running handler, back to idle.
            if consumeWord("to") {
                while current.kind != .newline, current.kind != .endOfScript { advance() }
                try expectNewline()
                return Stmt(kind: .exitToHyperCard, line: line)
            }
            if consumeWord(handlerName) {
                try expectNewline()
                return Stmt(kind: .exitHandler, line: line)
            }
            // `exit "mouseUp"` — a quoted handler name (Checking & Savings demo).
            // Any handler name exits the current handler, so accept a string that
            // matches (case-insensitively), as HyperCard does.
            if case .string(let name) = current.kind, name.caseInsensitiveCompare(handlerName) == .orderedSame {
                advance()
                try expectNewline()
                return Stmt(kind: .exitHandler, line: line)
            }
            throw ScriptError(line: line, message: "'exit' must be followed by 'repeat', 'to HyperCard', or the handler name '\(handlerName)'.")
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
        case "do":
            advance()
            let expression = try parseExpression()
            try expectNewline()
            return Stmt(kind: .doCommand(expression), line: line)
        case "answer":
            advance()
            // `answer file <prompt> [of type <filter>]` — a file-open dialog.
            if consumeWord("file") {
                let savedSuppress = suppressBarePropertyOf
                suppressBarePropertyOf = true // so `prompt of type …` doesn't read as a property
                let prompt = try parseExpression()
                suppressBarePropertyOf = savedSuppress
                var type: Expr?
                if consumeWord("of") {
                    _ = consumeWord("type")
                    type = try parseExpression()
                }
                try expectNewline()
                return Stmt(kind: .answerFile(prompt, type: type), line: line)
            }
            // `answer program <prompt> [of type <type>]` — a PPC program-browser
            // dialog (AppleEvents). No other app is reachable, so it behaves as
            // cancelled: `it` comes back empty.
            if consumeWord("program") {
                let savedSuppress = suppressBarePropertyOf
                suppressBarePropertyOf = true
                _ = try parseExpression() // the prompt (ignored)
                suppressBarePropertyOf = savedSuppress
                if consumeWord("of") { _ = consumeWord("type"); _ = try parseExpression() }
                try expectNewline()
                return Stmt(kind: .put(.stringLiteral(""), .into, .variable("it")), line: line)
            }
            let prompt = try parseExpression()
            var buttons: [Expr] = []
            if consumeWord("with") {
                // Buttons are separated by `or` (parsed below it so `or` isn't
                // swallowed as the boolean operator); some stacks use commas
                // instead (`answer "…" with "No","Yes"`).
                buttons.append(try parseConcatenation())
                while consumeWord("or") || consumeSymbol(",") { buttons.append(try parseConcatenation()) }
            }
            try expectNewline()
            return Stmt(kind: .answer(prompt, buttons: buttons), line: line)
        case "ask":
            advance()
            // `ask file <prompt> [with <default>]` (a save-file dialog) and
            // `ask password <prompt>` degrade to a plain text ask — Contrapt
            // has no file/password dialog, so the default (or empty) comes
            // back in `it`, and the stack's own `if it is empty` guard copes.
            _ = consumeWord("file") || consumeWord("password")
            let prompt = try parseExpression()
            var initialAnswer: Expr?
            if consumeWord("with") { initialAnswer = try parseExpression() }
            try expectNewline()
            return Stmt(kind: .ask(prompt, initialAnswer: initialAnswer), line: line)
        case "visual":
            advance()
            _ = consumeWord("effect")
            let effect = try parseVisualEffect(line: line)
            try expectNewline()
            return Stmt(kind: .visualEffect(effect), line: line)
        case "lock", "unlock":
            // `lock screen` / `unlock screen [with visual effect …]` is modeled
            // (see `.setScreenLocked`): Contrapt doesn't batch screen redraws,
            // but it DOES use the lock to defer a cross-window `go home`/`go
            // stack` so the classic invisible peek-and-pop at Home doesn't yank
            // the window order. lock/unlock messages|recent|menus|errorDialogs
            // stay no-ops. Any trailing `with visual effect …` is swallowed.
            let locking = word == "lock"
            advance()
            let isScreen = consumeWord("screen")
            while current.kind != .newline, current.kind != .endOfScript { advance() }
            try expectNewline()
            return Stmt(kind: isScreen ? .setScreenLocked(locking) : .noOp, line: line)
        case "wait":
            advance()
            let kind: WaitKind
            if consumeWord("until") {
                kind = .untilTrue(try parseExpression())
            } else if consumeWord("while") {
                kind = .whileTrue(try parseExpression())
            } else {
                _ = consumeWord("for") // optional: `wait for 2 seconds`
                let amount = try parseExpression()
                var unit: WaitUnit = .ticks // bare number is ticks, as in HyperCard
                if consumeWord("seconds") || consumeWord("second") || consumeWord("secs") || consumeWord("sec") {
                    unit = .seconds
                } else if consumeWord("ticks") || consumeWord("tick") {
                    unit = .ticks
                }
                kind = .duration(amount, unit)
            }
            try expectNewline()
            return Stmt(kind: .wait(kind), line: line)
        case "find":
            advance()
            return try parseFind(line: line)
        case "convert":
            advance()
            // A bare `convert` (nothing after) is a message send to a user
            // `on convert` handler, which HyperCard lets shadow the built-in
            // (Phone # Converter's button calls `convert`). The built-in form
            // always has a target + `to <format>`.
            if current.kind == .newline || current.kind == .endOfScript {
                try expectNewline()
                return Stmt(kind: .send("convert", []), line: line)
            }
            let target = try parseConvertTarget(line: line)
            var from: [ConvertFormat] = []
            if consumeWord("from") { from = try parseConvertFormat(line: line) }
            guard consumeWord("to") else {
                throw ScriptError(line: line, message: "Expected 'to <format>' in 'convert', like: convert the date to seconds.")
            }
            let to = try parseConvertFormat(line: line)
            try expectNewline()
            return Stmt(kind: .convert(target, from: from, to: to), line: line)
        case "add":
            advance()
            let amount = try parseExpression()
            guard consumeWord("to") else {
                throw ScriptError(line: line, message: "Expected 'to <container>' in 'add', like: add 1 to counter.")
            }
            let container = try parseContainer(line: line)
            try expectNewline()
            return Stmt(kind: .arithmetic(.add, amount: amount, container: container), line: line)
        case "subtract":
            advance()
            let amount = try parseExpression()
            guard consumeWord("from") else {
                throw ScriptError(line: line, message: "Expected 'from <container>' in 'subtract', like: subtract 1 from counter.")
            }
            let container = try parseContainer(line: line)
            try expectNewline()
            return Stmt(kind: .arithmetic(.subtract, amount: amount, container: container), line: line)
        case "multiply":
            advance()
            let container = try parseContainer(line: line)
            guard consumeWord("by") else {
                throw ScriptError(line: line, message: "Expected 'by <value>' in 'multiply', like: multiply total by 2.")
            }
            let amount = try parseExpression()
            try expectNewline()
            return Stmt(kind: .arithmetic(.multiply, amount: amount, container: container), line: line)
        case "divide":
            advance()
            let container = try parseContainer(line: line)
            guard consumeWord("by") else {
                throw ScriptError(line: line, message: "Expected 'by <value>' in 'divide', like: divide total by 2.")
            }
            let amount = try parseExpression()
            try expectNewline()
            return Stmt(kind: .arithmetic(.divide, amount: amount, container: container), line: line)
        case "pass":
            advance()
            // `pass <messageName>` — the name (usually the handler's own) is
            // accepted; the current message is what continues down the path.
            if peekIdentifier() != nil { advance() }
            try expectNewline()
            return Stmt(kind: .passMessage, line: line)
        case "send":
            advance()
            // `send <message> [to <object>]` — dispatch a message. With no `to`,
            // it goes to the current card (`send openCard`, `send "calc" && x`),
            // travelling the normal card→background→stack path from there.
            let message = try parseExpression()
            guard consumeWord("to") else {
                try expectNewline()
                return Stmt(kind: .sendMessage(message, to: .thisCard), line: line)
            }
            // `send <expr> to program <app> [with/without reply]` — an AppleEvent
            // to another application. Contrapt can't reach other apps, so the
            // whole line is accepted and no-op'd.
            if consumeWord("program") {
                while current.kind != .newline, current.kind != .endOfScript { advance() }
                try expectNewline()
                return Stmt(kind: .noOp, line: line)
            }
            let object = try parseObjectExpr()
            try expectNewline()
            return Stmt(kind: .sendMessage(message, to: object), line: line)
        case "request", "reply":
            // AppleEvent verbs — `request <expr> from program <app>`, `reply
            // <expr>` / `reply error <expr>` (answering an `appleEvent`). No
            // other app is reachable, so accept and no-op the whole line.
            advance()
            while current.kind != .newline, current.kind != .endOfScript { advance() }
            try expectNewline()
            return Stmt(kind: .noOp, line: line)
        case "print":
            // `print [this] card`, `print all/marked cards`, `print <n> cards`,
            // `print [card|bkgnd] field <ref>` — real printing. Anything else
            // (`print <document> with <app>`) is accepted and ignored.
            advance()
            if peekIdentifier() == "all", peekIdentifier(1) == "cards" {
                advance(); advance()
                try expectNewline()
                return Stmt(kind: .printCards(.all), line: line)
            }
            if peekIdentifier() == "marked", peekIdentifier(1) == "cards" {
                advance(); advance()
                try expectNewline()
                return Stmt(kind: .printCards(.marked), line: line)
            }
            if case .number(let n) = current.kind, peekIdentifier(1) == "cards" {
                advance(); advance()
                try expectNewline()
                return Stmt(kind: .printCards(.count(max(1, Int(n)))), line: line)
            }
            if let word = peekIdentifier(),
               ["field", "fld"].contains(word)
                || (["card", "cd", "background", "bkgnd", "bg"].contains(word)
                    && ["field", "fld"].contains(peekIdentifier(1) ?? "")) {
                let object = try parseObjectExpr()
                try expectNewline()
                return Stmt(kind: .printField(object), line: line)
            }
            if peekIdentifier() == "this" || peekIdentifier() == "card" || peekIdentifier() == "cd" {
                _ = consumeWord("this")
                _ = consumeWord("card") || consumeWord("cd")
                if current.kind == .newline || current.kind == .endOfScript {
                    try expectNewline()
                    return Stmt(kind: .printCards(.current), line: line)
                }
            }
            while current.kind != .newline, current.kind != .endOfScript { advance() }
            try expectNewline()
            return Stmt(kind: .noOp, line: line)
        case "open":
            // `open file <path>` starts file I/O; `open printing [with dialog]`
            // starts a print session. Other opens (`open <doc> with <app>`)
            // are accepted and ignored.
            advance()
            if consumeWord("file") {
                let path = try parseExpression()
                try expectNewline()
                return Stmt(kind: .openFile(path), line: line)
            }
            if consumeWord("printing") {
                var withDialog = false
                if consumeWord("with") { withDialog = consumeWord("dialog") }
                try expectNewline()
                return Stmt(kind: .openPrinting(withDialog: withDialog), line: line)
            }
            while current.kind != .newline, current.kind != .endOfScript { advance() }
            try expectNewline()
            return Stmt(kind: .noOp, line: line)
        case "close":
            // `close file <path>`; `close printing` ends (and prints) the
            // session; `close window …` no-ops.
            advance()
            if consumeWord("file") {
                let path = try parseExpression()
                try expectNewline()
                return Stmt(kind: .closeFile(path), line: line)
            }
            if consumeWord("printing") {
                try expectNewline()
                return Stmt(kind: .closePrinting, line: line)
            }
            if consumeWord("window") {
                // `close window "Tuber"` removes a scripted palette window.
                let name = (current.kind == .newline || current.kind == .endOfScript)
                    ? Expr.stringLiteral("") : try parsePrimary()
                while current.kind != .newline, current.kind != .endOfScript { advance() }
                try expectNewline()
                return Stmt(kind: .set(property: "close", object: .window(name), value: .stringLiteral("")), line: line)
            }
            while current.kind != .newline, current.kind != .endOfScript { advance() }
            try expectNewline()
            return Stmt(kind: .noOp, line: line)
        case "read":
            // `read from file <path> [until <char>|for <count>]` — into `it`.
            advance()
            _ = consumeWord("from")
            guard consumeWord("file") else {
                while current.kind != .newline, current.kind != .endOfScript { advance() }
                try expectNewline()
                return Stmt(kind: .noOp, line: line)
            }
            let path = try parseExpression()
            var until: Expr? = nil
            var count: Expr? = nil
            if consumeWord("until") { until = try parseExpression() }
            else if consumeWord("for") { count = try parseExpression() }
            try expectNewline()
            return Stmt(kind: .readFile(file: path, until: until, count: count), line: line)
        case "write":
            // `write <expr> to file <path> [at end|eof|<pos>]`.
            advance()
            let value = try parseExpression()
            guard consumeWord("to"), consumeWord("file") else {
                while current.kind != .newline, current.kind != .endOfScript { advance() }
                try expectNewline()
                return Stmt(kind: .noOp, line: line)
            }
            let path = try parseExpression()
            var atEOF = false
            var at: Expr? = nil
            if consumeWord("at") {
                if consumeWord("end") || consumeWord("eof") { atEOF = true }
                else { at = try parseExpression() }
            }
            try expectNewline()
            return Stmt(kind: .writeFile(value: value, file: path, atEOF: atEOF, at: at), line: line)
        case "delete":
            // `delete <chunk> of <container>` removes the chunk and its
            // delimiter (oracle-verified against HC 2.3 — the old assumption
            // that "no sample uses chunk deletion" silently no-op'd it).
            // `delete menu "X"` / `delete button …` (object deletion) stay
            // accepted-and-ignored so menu-managing stacks don't error.
            do {
                let saved = self
                advance()
                if consumeWord("menu") {
                    let name = try parsePrimary()
                    try expectNewline()
                    return Stmt(kind: .menuCommand(.deleteMenu(name)), line: line)
                }
                if let w = peekIdentifier(),
                   w == "menuitem" || ((Self.ordinals[w] != nil || Self.ordinalKeyword(w) != nil) && peekIdentifier(1) == "menuitem") {
                    let selector = try parseMenuItemSelector()
                    if consumeWord("of") || consumeWord("from") || consumeWord("in"), consumeWord("menu") {
                        let name = try parsePrimary()
                        try expectNewline()
                        return Stmt(kind: .menuCommand(.deleteMenuItem(selector, menu: name)), line: line)
                    }
                    self = saved
                    advance()
                }
                if let container = try? parseContainer(line: line),
                   isDeletableContainer(container),
                   current.kind == .newline || current.kind == .endOfScript {
                    try expectNewline()
                    return Stmt(kind: .deleteChunk(container), line: line)
                }
                self = saved
            }
            advance()
            while current.kind != .newline, current.kind != .endOfScript { advance() }
            try expectNewline()
            return Stmt(kind: .noOp, line: line)
        case "choose":
            // `choose <name> tool` — a real statement: the button/field tools
            // arm click-to-select for `doMenu "Clear Button"/"Clear Field"`,
            // browse restores clicking, and paint tools no-op in the host.
            // Other `choose` forms (`choose tool 3`) are accepted and ignored.
            advance()
            if let tool = peekIdentifier(), tool != "tool", peekIdentifier(1) == "tool" {
                advance(); advance() // <name> tool
                try expectNewline()
                return Stmt(kind: .chooseTool(tool), line: line)
            }
            while current.kind != .newline, current.kind != .endOfScript { advance() }
            try expectNewline()
            return Stmt(kind: .noOp, line: line)
        case "drag", "type", "reset", "dial", "create":
            // `create menu "X"`, `reset menubar`, `drag from…to…` and `reset
            // paint` are REAL (custom menus; scripted painting); the rest is
            // automation Contrapt doesn't model — `type`, `dial` (telephony),
            // `create stack` — accepted and ignored so scripts don't error.
            let verb = word
            advance()
            if verb == "create", consumeWord("menu") {
                let name = try parsePrimary()
                try expectNewline()
                return Stmt(kind: .menuCommand(.createMenu(name)), line: line)
            }
            if verb == "reset", consumeWord("menubar") {
                try expectNewline()
                return Stmt(kind: .menuCommand(.resetMenuBar), line: line)
            }
            if verb == "reset", consumeWord("paint") {
                try expectNewline()
                return Stmt(kind: .resetPaint, line: line)
            }
            if verb == "type", current.kind != .newline, current.kind != .endOfScript {
                let value = try parseExpression()
                var withCommand = false
                if consumeWord("with") {
                    while let modifier = peekIdentifier() {
                        advance()
                        if modifier == "commandkey" || modifier == "cmdkey" { withCommand = true }
                        if !consumeSymbol(",") { break }
                    }
                }
                try expectNewline()
                return Stmt(kind: .typeText(value, withCommandKey: withCommand), line: line)
            }
            if verb == "drag", consumeWord("from") {
                let fromH = try parseExpression()
                let fromV = consumeSymbol(",") ? try parseExpression() : nil
                if consumeWord("to") {
                    let toH = try parseExpression()
                    let toV = consumeSymbol(",") ? try parseExpression() : nil
                    // `with shiftKey…` modifiers: accepted, ignored.
                    while current.kind != .newline, current.kind != .endOfScript { advance() }
                    try expectNewline()
                    return Stmt(kind: .drag(fromH: fromH, fromV: fromV, toH: toH, toV: toV), line: line)
                }
            }
            while current.kind != .newline, current.kind != .endOfScript { advance() }
            try expectNewline()
            return Stmt(kind: .noOp, line: line)
        case "enable", "disable":
            // `enable`/`disable <button|field>` set the part's `enabled`
            // property (grayed + non-responsive). Menus/menu bar aren't modeled,
            // so `disable menu "File"` is a no-op.
            let enabled = word == "enable"
            advance()
            _ = consumeWord("the")
            if peekIdentifier() == "menu" {
                advance()
                let name = try parsePrimary()
                try expectNewline()
                return Stmt(kind: .menuCommand(.setEnabled(menu: name, item: nil, enabled: enabled)), line: line)
            }
            if let w = peekIdentifier(),
               w == "menuitem" || ((Self.ordinals[w] != nil || Self.ordinalKeyword(w) != nil) && peekIdentifier(1) == "menuitem") {
                let selector = try parseMenuItemSelector()
                guard consumeWord("of") || consumeWord("in"), consumeWord("menu") else {
                    while current.kind != .newline, current.kind != .endOfScript { advance() }
                    try expectNewline()
                    return Stmt(kind: .noOp, line: line)
                }
                let name = try parsePrimary()
                try expectNewline()
                return Stmt(kind: .menuCommand(.setEnabled(menu: name, item: selector, enabled: enabled)), line: line)
            }
            if peekIdentifier() == "menubar" {
                while current.kind != .newline, current.kind != .endOfScript { advance() }
                try expectNewline()
                return Stmt(kind: .noOp, line: line)
            }
            let object = try parseObjectExpr()
            try expectNewline()
            return Stmt(kind: .set(property: "enabled", object: object,
                                   value: .stringLiteral(enabled ? "true" : "false")), line: line)
        case "click":
            advance()
            _ = consumeWord("at")
            let h = try parseExpression()
            let v = consumeSymbol(",") ? try parseExpression() : nil
            // Ignore any trailing modifiers (`with shiftKey`, etc.).
            while current.kind != .newline, current.kind != .endOfScript { advance() }
            try expectNewline()
            return Stmt(kind: .clickAt(h, v), line: line)
        case "domenu":
            advance()
            return Stmt(kind: .doMenu(try parseMenuItem()), line: line)
        case "play":
            advance()
            // `play stop` silences; `play <voice> [tempo <n>] [<notes>]` plays
            // a named sound, optionally as a melody (see PlayNotes).
            if consumeWord("stop") {
                try expectNewline()
                return Stmt(kind: .playStop, line: line)
            }
            let voice = try parsePrimary()
            var tempo: Expr?
            if consumeWord("tempo") { tempo = try parsePrimary() }
            var notes: Expr?
            if current.kind != .newline, current.kind != .endOfScript {
                notes = try parsePlayNotes()
            }
            try expectNewline()
            return Stmt(kind: .play(voice: voice, tempo: tempo, notes: notes), line: line)
        case "start", "stop":
            // `start using stack "X"` / `stop using stack "X"` adds/removes an
            // auxiliary stack from the message-passing hierarchy (HyperCard
            // 2.x), so its handlers/functions are reachable from any stack. Only
            // the `using` form is ours; anything else stays a message send.
            if peekIdentifier(1) == "using" {
                let starting = word == "start"
                advance() // start/stop
                advance() // using
                // `start using this stack` — the current stack is already in the
                // message path, so adding/removing it is a no-op here.
                if consumeWord("this") {
                    _ = consumeWord("stack")
                    try expectNewline()
                    return Stmt(kind: .noOp, line: line)
                }
                _ = consumeWord("stack")
                let name = try parseExpression()
                // Tolerate any trailing tokens, as the old whole-line form did.
                while current.kind != .newline, current.kind != .endOfScript { advance() }
                try expectNewline()
                return Stmt(kind: starting ? .startUsing(name) : .stopUsing(name), line: line)
            }
            return try parseMessageSend(word: word, line: line)
        case "mark", "unmark":
            advance()
            return try parseMark(mark: word == "mark", line: line)
        case "sort":
            advance()
            return try parseSort(line: line)
        case "show", "hide":
            advance()
            return try parseShowHide(visible: word == "show", line: line)
        case "select":
            advance()
            // `select empty` clears; `select [the|before|after] text of <fld>`
            // selects all or collapses at an end; otherwise a chunk-of-field
            // container (`select line 2 of field 1`, `select char 3 to 9 of
            // line 2 of fld "Topics"`).
            _ = consumeWord("the")
            if consumeWord("empty") {
                try expectNewline()
                return Stmt(kind: .select(.empty), line: line)
            }
            // `select the clickLine` / `the selectedLine` — the reader's value
            // is a descriptor like `line 2 of card field id 20`, re-parsed as
            // a container at run time. (HyperCard's classic list one-liner.)
            if let click = Self.clickFields[peekIdentifier() ?? ""] {
                advance()
                try expectNewline()
                return Stmt(kind: .select(.descriptor(.click(click))), line: line)
            }
            if let component = Self.selectionFields[peekIdentifier() ?? ""] {
                advance()
                try expectNewline()
                return Stmt(kind: .select(.descriptor(.selected(component))), line: line)
            }
            let edge = consumeWord("before") ? "before" : (consumeWord("after") ? "after" : nil)
            if consumeWord("text") {
                // `in` is a synonym for `of` here (`select text in background
                // field "temp"`, Confusing Words).
                guard consumeWord("of") || consumeWord("in") else {
                    throw ScriptError(line: line, message: "Expected 'of' after 'select text'.")
                }
                // `select text of the foundField` / `… the selectedField` — the
                // value is a field descriptor (`card field id 5`), re-parsed at
                // run time; select the whole field's text.
                let savedDescriptor = index
                if consumeWord("the") {
                    if let found = Self.foundFields[peekIdentifier() ?? ""] {
                        advance()
                        try expectNewline()
                        return Stmt(kind: .select(.descriptor(.found(found))), line: line)
                    }
                    if let component = Self.selectionFields[peekIdentifier() ?? ""] {
                        advance()
                        try expectNewline()
                        return Stmt(kind: .select(.descriptor(.selected(component))), line: line)
                    }
                    index = savedDescriptor
                }
                if let fieldRef = try parseFieldRefIfPresent() {
                    try expectNewline()
                    let target: SelectTarget = edge == "before" ? .beforeText(fieldRef)
                        : edge == "after" ? .afterText(fieldRef) : .textOf(fieldRef)
                    return Stmt(kind: .select(target), line: line)
                }
                // Not a plain field ref — `select text of me`, `… of the target`,
                // `… of someFieldVar`. Parse a container; the runtime resolves it
                // to a field and selects the whole text (or collapses to an end).
                let container = try parseContainer(line: line)
                try expectNewline()
                let textEdge: TextEdge = edge == "before" ? .before : edge == "after" ? .after : .whole
                return Stmt(kind: .select(.textOfContainer(container, edge: textEdge)), line: line)
            }
            // A field/chunk container (or a variable holding a field
            // descriptor): the runtime selects text when it bottoms out in a
            // field. If the whole line parses as one container, use it.
            let saved = index
            if let container = try? parseContainer(line: line),
               current.kind == .newline || current.kind == .endOfScript {
                try expectNewline()
                return Stmt(kind: .select(.chunk(container)), line: line)
            }
            // Otherwise it selects a non-field object — `select cd btn id 17`,
            // `select line 0 of bkgnd btn "X"` (a popup button's list). That
            // drives HyperCard's edit tools, which Contrapt doesn't model, so
            // accept and no-op the line rather than failing the handler.
            index = saved
            while current.kind != .newline, current.kind != .endOfScript { advance() }
            try expectNewline()
            return Stmt(kind: .noOp, line: line)

        case "push":
            advance()
            // `push [this|recent] card` — the object is optional/ignored; the
            // current card is what's remembered.
            _ = consumeWord("this"); _ = consumeWord("recent")
            _ = consumeWord("card") || consumeWord("cd")
            // HyperCard also allows pushing a *named* card (`push card "X"`,
            // `push myCard`). Contrapt remembers the current card, so any such
            // descriptor is accepted and skipped rather than resolved.
            while current.kind != .newline, current.kind != .endOfScript { advance() }
            try expectNewline()
            return Stmt(kind: .pushCard, line: line)
        case "pop":
            advance()
            _ = consumeWord("card") || consumeWord("cd")
            var container: Container?
            if consumeWord("into") { container = try parseContainer(line: line) }
            try expectNewline()
            return Stmt(kind: .popCard(container), line: line)
        case "set":
            advance()
            _ = consumeWord("the")
            guard let property = peekIdentifier() else {
                // A dynamic property name — `set (TheProperty) of window X to …`
                // / `set "thePercent" of window X to …` (QuickTime Tools, Movie
                // Nudes): the property to set is computed. Contrapt doesn't model
                // dynamic property sets (the corpus targets are unmodeled
                // windows), so accept and no-op the line rather than failing the
                // handler — matching the other unmodeled-set paths below.
                while current.kind != .newline, current.kind != .endOfScript { advance() }
                try expectNewline()
                return Stmt(kind: .noOp, line: line)
            }
            advance()
            if consumeWord("of") {
                // A modeled object target (`set loc of btn "X" to …`). If it
                // parses cleanly up to `to`, keep it.
                let saved = index
                if let object = try? parseObjectExpr(), peekIdentifier() == "to" {
                    advance() // to
                    let value = try parseSetValue()
                    try expectNewline()
                    return Stmt(kind: .set(property: property.lowercased(), object: object, value: value), line: line)
                }
                // A chunk-of-field target: `set textStyle of line 2 of fld
                // "X" to bold` — a real per-run style write.
                index = saved
                if ["textstyle", "textfont", "textsize"].contains(property.lowercased()),
                   let container = try? parseContainer(line: line),
                   case .chunk = container,
                   peekIdentifier() == "to" {
                    advance() // to
                    let value = try parseSetValue()
                    try expectNewline()
                    return Stmt(kind: .setChunkProperty(property: property.lowercased(), chunk: container, value: value), line: line)
                }
                // Other unmodeled targets — a menu item (`set name of last
                // menuItem of menu "Y"`) or a function result (`set topLeft of
                // popObject() to …`). Accept and no-op the whole line rather
                // than failing the handler, as with other unmodeled sets.
                index = saved
                while current.kind != .newline, current.kind != .endOfScript { advance() }
                try expectNewline()
                return Stmt(kind: .noOp, line: line)
            }
            // Object-less property: `set the itemDelimiter to ";"`.
            guard consumeWord("to") else {
                throw ScriptError(line: line, message: "Expected 'of <object> to …' or 'to …' after 'set the \(property)'.")
            }
            let value = try parseSetValue()
            try expectNewline()
            return Stmt(kind: .setGlobalProperty(property.lowercased(), value), line: line)
        default:
            // An unknown word is a message send: it travels the message
            // path at run time (HyperCard semantics), so `doGreeting "Bill"`
            // can reach a handler defined on the card, background, or stack.
            return try parseMessageSend(word: word, line: line)
        }
    }

    /// A command word Contrapt doesn't recognize — dispatched as a message
    /// along the object path at run time (HyperCard semantics). Bespoke
    /// argument syntax that won't parse as expressions is skipped to the end
    /// of the line rather than failing the whole handler. `word` is the as-yet
    /// unconsumed command keyword.
    private mutating func parseMessageSend(word: String, line: Int) throws -> Stmt {
        advance()
        var arguments: [Expr] = []
        if current.kind != .newline, current.kind != .endOfScript {
            repeat {
                arguments.append(try parseExpression())
            } while consumeSymbol(",")
        }
        while current.kind != .newline, current.kind != .endOfScript { advance() }
        try expectNewline()
        return Stmt(kind: .send(word, arguments), line: line)
    }

    /// A `set … to <value>` value, allowing a comma list for points and
    /// rects (`set rect of btn "X" to 10,20,110,60`), joined with commas.
    private mutating func parseSetValue() throws -> Expr {
        var value = try parseExpression()
        while consumeSymbol(",") {
            let next = try parseExpression()
            value = .binary(.concat, .binary(.concat, value, .stringLiteral(",")), next)
        }
        return value
    }

    private mutating func parsePut(line: Int) throws -> Stmt {
        let value = try parseExpression()
        // `put <expr> to program <app> [without reply]` — an AppleEvent to
        // another application (HyperBattleship's networked play). Contrapt can't
        // reach other apps, so accept and no-op the whole line.
        if peekIdentifier() == "to", peekIdentifier(1) == "program" {
            while current.kind != .newline, current.kind != .endOfScript { advance() }
            try expectNewline()
            return Stmt(kind: .noOp, line: line)
        }

        var mode: PutMode?
        if consumeWord("into") { mode = .into }
        else if consumeWord("after") { mode = .after }
        else if consumeWord("before") { mode = .before }

        guard let mode else {
            try expectNewline()
            return Stmt(kind: .put(value, .into, nil), line: line)
        }

        // `put … into menu "X" [with menuMessages …]` populates a custom
        // menu. (`put … into <sel> menuItem of menu N` renames one item.)
        if peekIdentifier() == "menu" {
            advance()
            let menuName = try parsePrimary()
            var messages: Expr? = nil
            if consumeWord("with") {
                _ = consumeWord("menumessages"); _ = consumeWord("menumessage"); _ = consumeWord("menumsgs"); _ = consumeWord("menumsg")
                // The messages are a comma-separated list, one per item
                // (`with menuMsg "AC_Undo","","AddColorDelete",…` — Color
                // Tools), joined with commas to match the interpreter's split.
                var msgs = try parseExpression()
                while consumeSymbol(",") {
                    let next = try parseExpression()
                    msgs = .binary(.concat, .binary(.concat, msgs, .stringLiteral(",")), next)
                }
                messages = msgs
            }
            try expectNewline()
            return Stmt(kind: .menuCommand(.putIntoMenu(menu: menuName, items: value, mode: mode ?? .into, messages: messages)), line: line)
        }
        if let w = peekIdentifier(),
           w == "menuitem" || w == "menubar"
           || ((Self.ordinals[w] != nil || Self.ordinalKeyword(w) != nil) && peekIdentifier(1) == "menuitem") {
            // Renaming one item / writing the menu bar — accept and ignore
            // (rare forms; `set the name of menuItem …` is the modeled path).
            while current.kind != .newline, current.kind != .endOfScript { advance() }
            try expectNewline()
            return Stmt(kind: .noOp, line: line)
        }

        let container = try parseContainer(line: line)
        try expectNewline()
        return Stmt(kind: .put(value, mode, container), line: line)
    }

    /// `[the] <ordinal>|<expr> menuItem` selector for menu-item addressing.
    private mutating func parseMenuItemSelector() throws -> MenuItemSelector {
        _ = consumeWord("the")
        if let w = peekIdentifier(), let n = Self.ordinals[w] {
            // Exact ordinals (`first`…`tenth`) resolve to their number.
            advance()
            _ = consumeWord("menuitem")
            return .expr(.numberLiteral(Double(n)))
        }
        if let w = peekIdentifier(), let ordinal = Self.ordinalKeyword(w) {
            // Positional ordinals (last/middle/any).
            advance()
            _ = consumeWord("menuitem")
            return .ordinal(ordinal)
        }
        _ = consumeWord("menuitem")
        let value = try parsePrimary()
        return .expr(value)
    }

    /// A put destination: a chunk of a container (`word 2 of field "X"`),
    /// a field, or a variable.
    /// Containers `delete` can remove a chunk/range of: an explicit chunk, or
    /// the runtime-resolved foundChunk/selection (search-and-replace idioms).
    private func isDeletableContainer(_ container: Container) -> Bool {
        switch container {
        case .chunk, .foundChunk, .selection: return true
        default: return false
        }
    }

    private mutating func parseContainer(line: Int) throws -> Container {
        // A parenthesized container — the Home stack's list idiom puts the
        // base chunk in parens: `select char 1 to n of (line 2 of the target)`.
        if consumeSymbol("(") {
            let container = try parseContainer(line: line)
            guard consumeSymbol(")") else {
                throw ScriptError(line: line, message: "Expected ')' after a parenthesized container.")
            }
            return container
        }
        // `me` in a field's script is the field's contents.
        if peekIdentifier() == "me" {
            advance()
            return .me
        }
        // `[the] target` — the contents of the field the message was sent to.
        let targetOffset = peekIdentifier() == "the" ? 1 : 0
        if peekIdentifier(targetOffset) == "target" {
            if targetOffset == 1 { advance() } // the
            advance() // target
            return .target
        }
        if let word = peekIdentifier(), let kind = Self.chunkKinds[word], chunkKeywordStartsChunk() {
            advance()
            let savedSuppress = suppressBarePropertyOf
            suppressBarePropertyOf = true
            // The index is an arithmetic expression (`item (x mod 12)+1 of …`)
            // — parse at the additive level so it stops before `of`/`to`/`&`.
            let start = try parseAdditive()
            let selector: ChunkSelector = consumeWord("to")
                ? .range(start, try parseAdditive())
                : .index(start)
            suppressBarePropertyOf = savedSuppress
            guard consumeWord("of") || consumeWord("in") else {
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
            guard consumeWord("of") || consumeWord("in") else {
                throw ScriptError(line: line, message: "Expected 'of' after '\(ordinalWord) \(kindWord)'.")
            }
            return .chunk(kind, selector, try parseContainer(line: line))
        }
        // `msg` / `message [box|window]` / `the message box` — the message box
        // as a destination (`put x into message`). Without this it would fall
        // through to a variable named "message" and silently write nothing.
        let messageOffset = peekIdentifier() == "the" ? 1 : 0
        if let word = peekIdentifier(messageOffset), word == "msg" || word == "message" {
            if messageOffset == 1 { advance() } // the
            advance() // msg / message
            if let next = peekIdentifier(), next == "box" || next == "window" { advance() }
            return .messageBox
        }
        // `[the] selection` as a destination — `put X into the selection`
        // replaces the selected text.
        let selectionOffset = peekIdentifier() == "the" ? 1 : 0
        if peekIdentifier(selectionOffset) == "selection" {
            if selectionOffset == 1 { advance() } // the
            advance() // selection
            return .selection
        }
        // `[the] foundChunk` as a destination — the last find match, usable as
        // a container (`put X after the foundChunk` / `delete the foundChunk`).
        let foundOffset = peekIdentifier() == "the" ? 1 : 0
        if peekIdentifier(foundOffset) == "foundchunk" {
            if foundOffset == 1 { advance() } // the
            advance() // foundChunk
            return .foundChunk
        }
        if let fieldRef = try parseFieldRefIfPresent() {
            return try containerBrackets(.field(fieldRef), line: line)
        }
        if let name = peekIdentifier() {
            advance()
            return try containerBrackets(.variable(name), line: line)
        }
        throw ScriptError(line: line, message: "Expected a variable, field, or chunk here.")
    }

    /// Wrap a base container in any trailing array-index postfixes, so
    /// `put x into a["k"]` / `a["x"]["y"]` address an associative-array element.
    private mutating func containerBrackets(_ base: Container, line: Int) throws -> Container {
        var container = base
        while consumeSymbol("[") {
            let key = try parseExpression()
            guard consumeSymbol("]") else {
                throw ScriptError(line: line, message: "Expected ']' after an array key.")
            }
            container = .element(key: key, base: container)
        }
        return container
    }

    /// The thing `convert` acts on. Clear container forms (a field, a chunk,
    /// or a lone variable followed by `from`/`to`) are rewritten in place;
    /// anything else (`the date`, a function, a literal) is a source
    /// expression whose result lands in `it`.
    private mutating func parseConvertTarget(line: Int) throws -> ConvertTarget {
        if startsConvertContainer() {
            return .container(try parseContainer(line: line))
        }
        return .expression(try parseExpression())
    }

    /// True when the tokens here begin a container `convert` can rewrite.
    private func startsConvertContainer() -> Bool {
        // A chunk expression: `word 2 of …`.
        if let word = peekIdentifier(), Self.chunkKinds[word] != nil { return true }
        // An ordinal chunk, optionally led by `the`: `the last word of …`.
        let ordinalOffset = peekIdentifier() == "the" ? 1 : 0
        if let ordinalWord = peekIdentifier(ordinalOffset), Self.ordinalSelector(ordinalWord) != nil,
           let kindWord = peekIdentifier(ordinalOffset + 1), Self.chunkKinds[kindWord] != nil {
            return true
        }
        // A field reference: `field …`, `card field …`, `background field …`.
        if peekIdentifier() == "field" { return true }
        if (peekIdentifier() == "card" || peekIdentifier() == "background" || peekIdentifier() == "bg"),
           peekIdentifier(1) == "field" {
            return true
        }
        // A lone variable, e.g. `convert myDate to seconds` — the whole
        // target is one identifier followed immediately by `from`/`to`.
        if let name = peekIdentifier(), name != "the",
           peekIdentifier(1) == "from" || peekIdentifier(1) == "to" {
            return true
        }
        return false
    }

    /// A `convert` format phrase: one or more units joined by `and`, e.g.
    /// `seconds`, `dateItems`, `short date`, `long date and long time`.
    private mutating func parseConvertFormat(line: Int) throws -> [ConvertFormat] {
        var formats: [ConvertFormat] = []
        repeat {
            formats.append(try parseConvertFormatUnit(line: line))
        } while consumeWord("and")
        return formats
    }

    private mutating func parseConvertFormatUnit(line: Int) throws -> ConvertFormat {
        if consumeWord("seconds") || consumeWord("secs") { return .seconds }
        if consumeWord("dateitems") { return .dateItems }

        let adjectives: Set<String> = ["long", "short", "abbreviated", "abbrev", "abbr"]
        let adjective = adjectives.contains(peekIdentifier() ?? "") ? peekIdentifier() : nil
        if adjective != nil { advance() }

        if consumeWord("date") {
            switch adjective {
            case "long": return .longDate
            case "abbreviated", "abbrev", "abbr": return .abbreviatedDate
            default: return .shortDate
            }
        }
        if consumeWord("time") {
            return adjective == "long" ? .longTime : .shortTime
        }
        throw ScriptError(line: line, message: "Expected a date/time format here, like seconds, dateItems, short date, or long time.")
    }

    /// Parses `<kind> [<direction>] [[very] <speed>]` after `visual effect`,
    /// e.g. `dissolve`, `wipe left`, `iris open slowly`, `zoom out very fast`.
    /// The note specification after `play <voice> [tempo N]`. A quoted string,
    /// a field, or a parenthesized expression is evaluated; a bare note sequence
    /// (`b3 c#4 d e f# r g4`) is taken literally — reconstructed from its tokens
    /// so `#`, dots, and octave digits stay attached to their note letter.
    private mutating func parsePlayNotes() throws -> Expr {
        if case .string = current.kind { return try parseExpression() }
        if case .symbol("(") = current.kind { return try parseExpression() }
        if let w = peekIdentifier(),
           ["field", "fld", "card", "cd", "background", "bkgnd", "bg", "the"].contains(w) {
            return try parseExpression()
        }
        var text = ""
        while current.kind != .newline, current.kind != .endOfScript {
            let piece: String
            let continuesNote: Bool // true → no leading space (#, ., octave digit)
            switch current.kind {
            case .identifier(let word): piece = word; continuesNote = false
            case .string(let string): piece = string; continuesNote = false
            case .number(let value): piece = Value.string(from: value); continuesNote = true
            case .symbol(let symbol): piece = symbol; continuesNote = true
            default: piece = ""; continuesNote = true
            }
            if !text.isEmpty, !continuesNote { text += " " }
            text += piece
            advance()
        }
        return .stringLiteral(text)
    }

    /// An optional `to <image>` clause is tolerated but ignored for now.
    private mutating func parseVisualEffect(line: Int) throws -> ScreenEffect {
        // The effect name is usually a keyword, but some stacks quote it
        // (`visual effect "CheckerBoard"`) — accept a string too (lowercased so
        // it matches the keyword cases).
        let first: String
        if let word = peekIdentifier() {
            first = word
        } else if case .string(let text) = current.kind {
            first = text.lowercased()
        } else {
            throw ScriptError(line: line, message: "Expected an effect after 'visual effect', like dissolve or wipe left.")
        }
        advance()
        let kind: ScreenEffect.Kind
        switch first {
        case "dissolve": kind = .dissolve
        case "wipe": kind = .wipe
        case "scroll", "push": kind = .scroll // push is a push-reveal ≈ scroll
        case "zoom": kind = .zoom
        case "iris": kind = .iris
        case "checkerboard": kind = .checkerboard
        case "plain": kind = .plain
        case "barn":
            guard consumeWord("door") else {
                throw ScriptError(line: line, message: "Expected 'door' after 'barn'.")
            }
            kind = .barnDoor
        case "venetian":
            guard consumeWord("blinds") else {
                throw ScriptError(line: line, message: "Expected 'blinds' after 'venetian'.")
            }
            kind = .venetianBlinds
        case "shrink", "stretch":
            // HyperCard's `shrink to top/center/bottom` and `stretch from …` —
            // rendered as the closest modeled effect (a zoom close/open); the
            // position word is consumed and ignored.
            _ = consumeWord("to") || consumeWord("from")
            if let w = peekIdentifier(), w == "top" || w == "center" || w == "bottom" { advance() }
            kind = .zoom
            return try finishVisualEffect(kind: kind, direction: first == "shrink" ? .close : .open)
        default:
            // The effect name is a variable (`visual effect theEffect`) or an
            // effect Contrapt doesn't model — can't be resolved at parse time.
            // The transition is cosmetic, so fall back to a dissolve and still
            // consume any direction/speed tail, rather than failing the handler.
            kind = .dissolve
        }

        var direction: ScreenEffect.Direction?
        if let word = peekIdentifier(), let parsed = ScreenEffect.Direction(rawValue: word) {
            advance()
            direction = parsed
        }
        return try finishVisualEffect(kind: kind, direction: direction)
    }

    /// The `[[very] fast/slow]` tail and optional `to <image>` clause shared by
    /// every effect form.
    private mutating func finishVisualEffect(kind: ScreenEffect.Kind, direction: ScreenEffect.Direction?) throws -> ScreenEffect {
        var speed: ScreenEffect.Speed = .normal
        if consumeWord("very") {
            if consumeWord("fast") { speed = .veryFast }
            else if consumeWord("slow") || consumeWord("slowly") { speed = .verySlow }
        } else if consumeWord("fast") {
            speed = .fast
        } else if consumeWord("slow") || consumeWord("slowly") {
            speed = .slow
        }

        // `visual effect dissolve to white` — accept and ignore the target.
        if consumeWord("to") { _ = peekIdentifier().map { _ in advance() } }

        return ScreenEffect(kind: kind, direction: direction, speed: speed)
    }

    private mutating func parseFind(line: Int) throws -> Stmt {
        // `find [international|normal] [chars|word|whole|string] <text> [in <field>]`.
        if peekIdentifier() == "international" || peekIdentifier() == "normal" { advance() }
        var mode: FindMode = .wordPrefix
        switch peekIdentifier() {
        case "chars", "characters": advance(); mode = .chars
        case "word": advance(); mode = .wholeWord
        case "whole": advance(); mode = .wholePhrase
        case "string": advance(); mode = .string
        default: break
        }
        let text = try parseExpression()
        var field: FieldRef?
        if consumeWord("in") {
            // `find X in the foundField` / `… the selectedField` — restrict to
            // the last find's / the selection's field (Addresses). We don't
            // resolve that field reference statically, so search unrestricted
            // (best effort — identical for one-field-per-card stacks).
            let fieldOffset = peekIdentifier() == "the" ? 1 : 0
            if let w = peekIdentifier(fieldOffset), w == "foundfield" || w == "selectedfield" {
                if fieldOffset == 1 { advance() } // the
                advance() // foundField / selectedField
            } else {
                guard let reference = try parseFieldRefIfPresent() else {
                    throw ScriptError(line: line, message: "Expected a field after 'in', like: find \"x\" in field \"Notes\".")
                }
                field = reference
            }
        }
        try expectNewline()
        return Stmt(kind: .find(mode, text: text, inField: field), line: line)
    }

    /// A `doMenu` item: a quoted string or single variable is an expression
    /// (`doMenu "New Card"`, `doMenu menuItem`); bare multi-word text is the
    /// literal menu name (`doMenu Select All`, `doMenu clear picture`).
    private mutating func parseMenuItem() throws -> Expr {
        // `doMenu <item> [, <menuName>] [with|without dialog]` — the optional
        // which-menu and the dialog modifier (`doMenu "Delete Stack…" without
        // dialog`) are consumed; Contrapt performs the action either way.
        func consumeMenuTrailers() {
            if consumeSymbol(",") { _ = try? parseExpression() }
            if peekIdentifier() == "with" || peekIdentifier() == "without" {
                advance(); _ = consumeWord("dialog")
            }
        }
        if case .string = current.kind {
            let item = try parseExpression()
            consumeMenuTrailers()
            try expectNewline()
            return item
        }
        var words: [String] = []
        while current.kind != .newline, current.kind != .endOfScript {
            // Stop before a trailing `with/without dialog` so it isn't read as
            // part of a bare multi-word menu name.
            if (peekIdentifier() == "with" || peekIdentifier() == "without"), peekIdentifier(1) == "dialog" { break }
            if let word = peekIdentifier() { words.append(word) }
            else if case .string(let text) = current.kind { words.append(text) }
            else if case .number(let value) = current.kind { words.append(Value.string(from: value)) }
            advance()
        }
        consumeMenuTrailers()
        try expectNewline()
        // A lone bare word is a variable holding the item; multiple words are
        // the literal menu name.
        if words.count == 1 { return .variable(words[0]) }
        return .stringLiteral(words.joined(separator: " "))
    }

    /// `mark`/`unmark [this] card`, `… card N`, `… all cards`, `… cards where
    /// <condition>`. The `… cards by finding …` form isn't modeled — accepted
    /// and no-op'd.
    private mutating func parseMark(mark: Bool, line: Int) throws -> Stmt {
        _ = consumeWord("the")
        if consumeWord("all") {
            _ = consumeCardWord()
            try expectNewline()
            return Stmt(kind: .setMarked(mark: mark, .allCards), line: line)
        }
        if let w = peekIdentifier(), Self.cardWords.contains(w) || w == "cards" || w == "cds" {
            if peekIdentifier(1) == "where" {
                advance() // cards
                advance() // where
                let condition = try parseExpression()
                try expectNewline()
                return Stmt(kind: .setMarked(mark: mark, .cardsWhere(condition)), line: line)
            }
            if peekIdentifier(1) == "by" {
                // `mark cards by finding "x" [in field "y"]` — not modeled.
                while current.kind != .newline, current.kind != .endOfScript { advance() }
                try expectNewline()
                return Stmt(kind: .noOp, line: line)
            }
        }
        // A single card: `mark [this] card [N | "name" | id N]` (bare = current).
        _ = consumeWord("this")
        guard consumeCardWord() else {
            try expectNewline()
            return Stmt(kind: .setMarked(mark: mark, .card(nil)), line: line)
        }
        let cardRef: CardRef?
        if current.kind == .newline || current.kind == .endOfScript {
            cardRef = nil // `mark card` / `mark this card` → the current card
        } else if consumeWord("id") {
            cardRef = .idExpression(try parsePrimary())
        } else {
            cardRef = .expression(try parsePrimary())
        }
        try expectNewline()
        return Stmt(kind: .setMarked(mark: mark, .card(cardRef)), line: line)
    }

    /// `sort [this stack] [marked] [cards] [of …] [ascending|descending]
    /// [text|numeric|international|dateTime] by <expr>` — reorders the stack's
    /// cards. Contrapt sorts the whole stack; qualifiers it doesn't model
    /// (marked, of a background) are accepted and ignored.
    private mutating func parseSort(line: Int) throws -> Stmt {
        // Container sort — `sort [the] [lines|items of] <container>` (the Home
        // stack's `sort bg fld "Apps For Docs"`) sorts a field's or variable's
        // text in place, as opposed to the cards sort below. An explicit
        // `lines of`/`items of`, or a field reference, marks this form. Must
        // be detected before the cards form eats a `cd` field qualifier.
        var sortItems = false
        var isContainerSort = false
        let theOffset = peekIdentifier() == "the" ? 1 : 0
        if let unit = peekIdentifier(theOffset), unit == "lines" || unit == "items",
           peekIdentifier(theOffset + 1) == "of" {
            if theOffset == 1 { advance() } // the
            sortItems = unit == "items"
            advance() // lines / items
            advance() // of
            isContainerSort = true
        } else if startsFieldContainer() {
            isContainerSort = true
        } else if startsBareContainerSort() {
            // `sort it`, `sort list`, `sort dataList descending numeric` — a
            // bare variable/`it` container (no `cards`/`this stack`/`by` yet),
            // sorting its lines in place.
            isContainerSort = true
        }
        if isContainerSort {
            let container = try parseContainer(line: line)
            var ascending = true
            var numeric = false
            for _ in 0..<2 {
                if consumeWord("ascending") { ascending = true }
                else if consumeWord("descending") { ascending = false }
                else if consumeWord("numeric") { numeric = true }
                else if consumeWord("text") || consumeWord("international")
                            || consumeWord("datetime") || consumeWord("date") { numeric = false }
            }
            var key: Expr?
            if consumeWord("by") {
                for _ in 0..<2 {
                    if consumeWord("ascending") { ascending = true }
                    else if consumeWord("descending") { ascending = false }
                    else if consumeWord("numeric") { numeric = true }
                    else if consumeWord("text") || consumeWord("international")
                                || consumeWord("datetime") || consumeWord("date") { numeric = false }
                }
                key = try parseExpression()
            }
            try expectNewline()
            return Stmt(kind: .sortContainer(items: sortItems, container: container,
                                             ascending: ascending, numeric: numeric, key: key), line: line)
        }
        _ = consumeWord("this"); _ = consumeWord("stack")
        _ = consumeWord("marked")
        _ = consumeCardWord()
        // An `of <object>` scope, or a direct background reference
        // (`sort bg "CURRENT" by …` — the cards of that background), which
        // Contrapt doesn't model distinctly: skip up to `by` and sort the
        // stack's cards (best effort, as for the `of` scope).
        if peekIdentifier() == "of" || (peekIdentifier().map(Self.backgroundWords.contains) ?? false) {
            while current.kind != .newline, current.kind != .endOfScript,
                  peekIdentifier() != "by" { advance() }
        }
        var ascending = true
        var numeric = false
        // Order and style may appear in either order; accept both.
        for _ in 0..<2 {
            if consumeWord("ascending") { ascending = true }
            else if consumeWord("descending") { ascending = false }
            else if consumeWord("numeric") { numeric = true }
            else if consumeWord("text") || consumeWord("international")
                        || consumeWord("datetime") || consumeWord("date") { numeric = false }
        }
        guard consumeWord("by") else {
            throw ScriptError(line: line, message: "Expected 'by <expression>' in 'sort'.")
        }
        // Direction/style may ALSO follow `by` — `sort by descending field "X"`.
        for _ in 0..<2 {
            if consumeWord("ascending") { ascending = true }
            else if consumeWord("descending") { ascending = false }
            else if consumeWord("numeric") { numeric = true }
            else if consumeWord("text") || consumeWord("international")
                        || consumeWord("datetime") || consumeWord("date") { numeric = false }
        }
        let key = try parseExpression()
        try expectNewline()
        return Stmt(kind: .sortCards(ascending: ascending, numeric: numeric, key: key), line: line)
    }

    /// `show`/`hide <object>` toggles a part's visibility. Targets Contrapt
    /// has no concept of (menu bar, message box, tool/pattern windows, card
    /// pictures, all-cards animation) parse to a no-op so old stacks don't
    /// break. `show <object> at <loc>` accepts and ignores the location.
    private mutating func parseShowHide(visible: Bool, line: Int) throws -> Stmt {
        _ = consumeWord("the")
        // The paint layer: `show/hide [card|bkgnd] picture`, `hide picture of
        // card 1`, `show picture of this card` — a real property write
        // (Adventures of Sean toggles card pictures for its dark rooms).
        if let w = peekIdentifier(), w == "picture" || w == "pict" {
            advance()
            let object: ObjectExpr
            if consumeWord("of") || consumeWord("in") {
                object = try parseObjectExpr()
            } else {
                object = .thisCard
            }
            try expectNewline()
            return Stmt(kind: .set(property: "showpict", object: object,
                                   value: .stringLiteral(visible ? "true" : "false")), line: line)
        }
        if let w = peekIdentifier(),
           Self.cardWords.contains(w) || Self.backgroundWords.contains(w),
           let next = peekIdentifier(1), next == "picture" || next == "pict" {
            let isBackground = Self.backgroundWords.contains(w)
            advance(); advance()
            // `hide bg picture of card 3` — an explicit owner.
            var object: ObjectExpr = isBackground ? .thisBackground : .thisCard
            if consumeWord("of") || consumeWord("in") {
                object = try parseObjectExpr()
            }
            try expectNewline()
            return Stmt(kind: .set(property: isBackground ? "showbgpict" : "showpict", object: object,
                                   value: .stringLiteral(visible ? "true" : "false")), line: line)
        }
        // `show/hide window "X"` toggles a scripted palette's visibility.
        if peekIdentifier() == "window" {
            advance()
            let name = (current.kind == .newline || current.kind == .endOfScript)
                ? Expr.stringLiteral("") : try parsePrimary()
            // `show window "X" at "h,v"` positions the window as it shows; the
            // location is consumed (Contrapt shows it at its registered loc).
            if consumeWord("at") { _ = try? parsePrimary() }
            try expectNewline()
            return Stmt(kind: .set(property: "visible", object: .window(name),
                                   value: .stringLiteral(visible ? "true" : "false")), line: line)
        }
        // Ignorable targets.
        let ignorable = ["menubar", "menu", "titlebar", "message", "msg", "tool",
                         "pattern", "patterns", "picture", "pict", "background",
                         "card", "cd", "bkgnd", "bkgd", "bg", "all", "cards", "cds",
                         "marked", "window", "windows", "groups", "scroll", "variable"]
        if let first = peekIdentifier(), ignorable.contains(first),
           !isPartReference() {
            while current.kind != .newline, current.kind != .endOfScript { advance() }
            try expectNewline()
            return Stmt(kind: .noOp, line: line)
        }
        // `show 10 cards` / `show (number of cards) cards` — the flip-through
        // animation (a count expression before `cards`). Contrapt doesn't
        // animate; accept and no-op. `show all cards` is caught by the list above.
        if case .number = current.kind {} else if case .symbol("(") = current.kind {} else {
            // not a count — fall through to the object case below
            return try finishShowHide(visible: visible, line: line)
        }
        do {
            let saved = index
            if (try? parseExpression()) != nil, let w = peekIdentifier(), w == "cards" || w == "cds" {
                while current.kind != .newline, current.kind != .endOfScript { advance() }
                try expectNewline()
                return Stmt(kind: .noOp, line: line)
            }
            index = saved
        }
        return try finishShowHide(visible: visible, line: line)
    }

    private mutating func finishShowHide(visible: Bool, line: Int) throws -> Stmt {
        let object = try parseObjectExpr()
        // `at h,v` — HyperCard also moves the part; we just show/hide it.
        if consumeWord("at") {
            _ = try parseExpression()
            while consumeSymbol(",") { _ = try parseExpression() }
        }
        try expectNewline()
        return Stmt(kind: .set(property: "visible", object: object,
                               value: .stringLiteral(visible ? "true" : "false")), line: line)
    }

    /// Whether a field reference begins here (`[the] [card|bg] field …`) —
    /// how `sort` tells its container form from its cards form.
    private func startsFieldContainer() -> Bool {
        var offset = peekIdentifier() == "the" ? 1 : 0
        if let w = peekIdentifier(offset),
           Self.cardWords.contains(w) || Self.backgroundWords.contains(w) { offset += 1 }
        guard let w = peekIdentifier(offset) else { return false }
        return w == "field" || w == "fld"
    }

    /// Whether `sort` is followed by a bare container to sort in place
    /// (`sort it`, `sort list`) rather than the cards form. True when the next
    /// word isn't one of the cards-form keywords (`cards`, `this`, `marked`,
    /// an order/style word, or `by`) — i.e. it's a plain variable or `it`.
    private func startsBareContainerSort() -> Bool {
        let offset = peekIdentifier() == "the" ? 1 : 0
        guard let w = peekIdentifier(offset) else { return false }
        let cardsFormKeywords: Set<String> = [
            "cards", "card", "cds", "cd", "marked", "this", "stack", "by",
            "ascending", "descending", "numeric", "text", "international",
            "datetime", "date", "lines", "items",
        ]
        // A background reference (`sort bg "X" by`) is the cards form, not a
        // bare variable named "bg".
        if Self.backgroundWords.contains(w) { return false }
        return !cardsFormKeywords.contains(w)
    }

    /// Whether what's ahead is a part reference like `card button "X"` /
    /// `field 1` (so `show card button…` isn't mistaken for the ignorable
    /// `card picture`).
    private func isPartReference() -> Bool {
        // `picture`/`pict` is the card's paint layer (an ignorable no-op), not
        // an image *part* — exclude it even though `partKindSynonyms` aliases
        // `picture` to `image` for real `image "X"` part references.
        func isKind(_ word: String?) -> Bool {
            guard let word, word != "picture", word != "pict" else { return false }
            return Self.partKindSynonyms[word] != nil
        }
        // A bare part (`btn "X"`, `field 1`) or a domain-qualified one
        // (`cd btn id 5`, `bg field 2`) — synonyms included (btn/fld, cd/bg).
        if isKind(peekIdentifier()) { return true }
        if let w = peekIdentifier(), Self.cardWords.contains(w) || Self.backgroundWords.contains(w),
           isKind(peekIdentifier(1)) { return true }
        return false
    }

    private mutating func parseGo(line: Int) throws -> Stmt {
        // A go destination never uses a bare `<prop> of <obj>` property, but
        // `go card whichSix of stack "X"` would otherwise read `whichSix of …`
        // as one. Suppress the shortcut so the card expr stays a plain value
        // and the trailing `of …` is handled as a qualifier.
        let savedSuppress = suppressBarePropertyOf
        suppressBarePropertyOf = true
        defer { suppressBarePropertyOf = savedSuppress }
        _ = consumeWord("to")
        _ = consumeWord("the")
        var target: GoTarget
        // Marked-card navigation — `go marked card N`, `go first/last/next/
        // previous marked card`. Checked before the plain next/first/last
        // branches, which would otherwise claim the leading keyword.
        if peekIdentifier() == "marked", let c = peekIdentifier(1), Self.cardWords.contains(c) {
            advance() // marked
            advance() // card
            target = .markedCard(try parseExpression())
        } else if let w = peekIdentifier(), peekIdentifier(1) == "marked" {
            advance() // ordinal/relative
            advance() // marked
            _ = consumeCardWord()
            switch w {
            case "next": target = .relativeMarked(forward: true)
            case "previous", "prev": target = .relativeMarked(forward: false)
            case "first": target = .markedCard(.numberLiteral(1))
            case "last": target = .markedCardOrdinal(.last)
            case "middle": target = .markedCardOrdinal(.middle)
            case "any": target = .markedCardOrdinal(.any)
            default: target = .markedCard(.numberLiteral(Double(Self.ordinals[w] ?? 1)))
            }
        } else if consumeWord("next") {
            // `go next background` lands on the adjacent background's first card;
            // `go next card` (or bare `go next`) is the card step.
            if consumeBackgroundWord() { target = .relativeBackground(forward: true) }
            else { _ = consumeCardWord(); target = .next }
        } else if consumeWord("previous") || consumeWord("prev") {
            if consumeBackgroundWord() { target = .relativeBackground(forward: false) }
            else { _ = consumeCardWord(); target = .previous }
        } else if consumeWord("first") {
            _ = consumeCardWord()
            target = .first
        } else if consumeWord("last") {
            _ = consumeCardWord()
            target = .last
        } else if consumeWord("home") {
            target = .home
        } else if consumeWord("back") {
            target = .back
        } else if consumeWord("recent") {
            // `go recent card` — the most recently viewed card, like `go back`.
            _ = consumeCardWord()
            target = .back
        } else if consumeWord("any") {
            // `go [to] any card` — a random card in the stack.
            _ = consumeCardWord()
            target = .any
        } else if consumeWord("this") {
            // `go [to] this card` stays on the current card; `go this bg` goes to
            // the current background's first card.
            if consumeBackgroundWord() {
                target = .inBackground(.first, background: nil)
            } else {
                _ = consumeCardWord() || consumeWord("stack")
                target = .current
            }
        } else if consumeCardWord() {
            if current.kind == .newline || current.kind == .endOfScript {
                target = .current // bare `go [to] card` → the current card
            } else if consumeWord("id") {
                // A dangling `go card id` with no number (a leftover line) stays
                // on the current card rather than failing the handler.
                target = (current.kind == .newline || current.kind == .endOfScript)
                    ? .current : .idExpression(try parseExpression())
            } else {
                target = .expression(try parseExpression())
            }
        } else if consumeBackgroundWord() {
            // `go [to] bg <name>` — the first card of that background, as in
            // HyperCard. (`go bg id N` parses too; the id is matched as a name,
            // best effort.) Power Tools: `if there is not a cd it then go bg it`.
            _ = consumeWord("id")
            target = .inBackground(.first, background: try parseExpression())
        } else if consumeWord("stack") {
            // `go [to] stack "X"` — another stack (opens at its first card).
            target = .inStack(name: try parseExpression(), card: nil)
        } else if current.kind != .newline && current.kind != .endOfScript {
            // A bare `go [to] "Name"` — a card/stack by name/number. An unquoted
            // MULTI-word name (`go to File Index`, `go to Clip Art`, `go to Area
            // Codes`) is HyperCard's shorthand for a stack of that name; join the
            // consecutive bare words. A single bare word stays an expression (it
            // may be a variable holding a destination name). Stops at a trailing
            // qualifier (`of …`, `in a new window`, `without dialog`).
            if case .identifier(let first) = current.kind, isGoNameWord(first),
               let second = peekIdentifier(1), isGoNameWord(second) {
                var words: [String] = []
                while case .identifier(let w) = current.kind, isGoNameWord(w) {
                    words.append(w); advance()
                }
                target = .inStack(name: .stringLiteral(words.joined(separator: " ")), card: nil)
            } else {
                target = .expression(try parseExpression())
            }
        } else {
            throw ScriptError(line: line, message: "Expected a destination after 'go', like 'next card' or 'card 3'.")
        }
        // Trailing qualifiers compose innermost-first, as HyperCard writes them:
        // `go cd X of bkgnd "Paths" of stack "Home"` = (card X in background
        // "Paths") in stack "Home".
        if let qualifier = try parseOfBackground() {
            switch qualifier {
            case .current: target = .inBackground(target, background: nil)
            case .named(let background): target = .inBackground(target, background: background)
            }
        }
        if peekIdentifier() == "of" || peekIdentifier() == "in", peekIdentifier(1) == "stack" {
            // `of stack "X"` / `in stack "X"` (Sean's Help: `go to card 1 in
            // stack "Sean's World II Help" in a new window`).
            advance(); advance()
            target = .inStack(name: try parseExpression(), card: target)
        }
        if peekIdentifier() == "of" {
            // Some other trailing `of …` qualifier we don't model — ignore it.
            while current.kind != .newline, current.kind != .endOfScript { advance() }
        }
        // Window/dialog modifiers Contrapt doesn't model: `go stack "X" in a new
        // window [without dialog]`, `go … without dialog`.
        if peekIdentifier() == "in" || peekIdentifier() == "without" {
            while current.kind != .newline, current.kind != .endOfScript { advance() }
        }
        try expectNewline()
        return Stmt(kind: .go(target), line: line)
    }

    private mutating func parseIf(handlerName: String, line: Int) throws -> Stmt {
        // A long single-line `if … then … else if … else if …` chain recurses
        // parseIf ⇄ parseElse (bypassing parseStatements); bound it here so it
        // can't overflow the stack.
        expressionDepth += 1
        defer { expressionDepth -= 1 }
        guard expressionDepth <= Self.maxExpressionDepth else {
            throw ScriptError(line: line, message: "This 'if' is nested too deeply.")
        }
        let condition = try parseExpression()
        // HyperCard lets `then` begin on the next line(s):
        //   if <cond>
        //   then <statement>
        // Skip a newline before `then`, but only if `then` actually follows.
        if current.kind == .newline {
            let saved = index
            skipNewlines()
            if peekIdentifier() != "then" { index = saved }
        }
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
        // An inline `else <statement>` closes the `if` by itself — whether the
        // then-clause was single-line or a block. A following `end if` belongs
        // to an *enclosing* block, so it's left for that block to consume. This
        // is how Apple's stacks nest a block-then + inline-else inside an outer
        // block-if that owns the sole `end if`:
        //   if outer then
        //     if inner then
        //       …
        //     else oneStatement      -- closes the inner if
        //   end if                   -- closes the outer if
        return [try parseStatement(handlerName: handlerName)]
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
            // `repeat with i = 2 to 6` — Home's STAK writes `is` for `=`.
            guard consumeSymbol("=") || consumeWord("is") else {
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
                let negated = consumeWord("not")
                // `is [not] a[n] <type>` — a type test.
                if peekIdentifier() == "a" || peekIdentifier() == "an",
                   let type = peekIdentifier(1), Self.typeNames.contains(type) {
                    advance() // a / an
                    advance() // type
                    left = .isType(left, type, negated: negated)
                } else if consumeWord("in") {
                    // `A is [not] in B` == B [does not] contains A.
                    let contains = Expr.binary(.contains, try parseConcatenation(), left)
                    left = negated ? .unary(.not, contains) : contains
                } else if consumeWord("within") {
                    // `point is [not] within rect` — point-in-rectangle test.
                    let test = Expr.binary(.within, left, try parseConcatenation())
                    left = negated ? .unary(.not, test) : test
                } else if peekIdentifier() == "greater" || peekIdentifier() == "less" {
                    // `is greater than [or equal to]` / `is less than …`.
                    let isGreater = peekIdentifier() == "greater"
                    advance()
                    _ = consumeWord("than")
                    let orEqual = consumeWord("or")
                    if orEqual { _ = consumeWord("equal"); _ = consumeWord("to") }
                    let op: BinaryOp = isGreater
                        ? (orEqual ? .greaterOrEqual : .greater)
                        : (orEqual ? .lessOrEqual : .less)
                    let comparison = Expr.binary(op, left, try parseConcatenation())
                    left = negated ? .unary(.not, comparison) : comparison
                } else if negated {
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
            // Unary minus binds TIGHTER than ^: -2 ^ 2 is (-2)^2 = 4
            // (oracle-verified, HC 2.3) — so negate the primary, then let a
            // following ^ take the negated value as its base.
            let base = Expr.unary(.minus, try parseNegationOperand())
            if consumeSymbol("^") {
                return .binary(.power, base, try parseUnary())
            }
            return base
        }
        if peekIdentifier() == "not" {
            advance()
            return .unary(.not, try parseUnary())
        }
        return try parsePower()
    }

    /// The operand of a unary minus: another sign, a `not`, or a primary —
    /// but never a power (the minus must bind tighter than `^`).
    private mutating func parseNegationOperand() throws -> Expr {
        if consumeSymbol("-") { return .unary(.minus, try parseNegationOperand()) }
        if peekIdentifier() == "not" { advance(); return .unary(.not, try parseUnary()) }
        return try parsePrimary()
    }

    /// `base ^ exponent`, right-associative and binding tighter than * and /,
    /// as in HyperCard. The right side parses as a unary so `2 ^ -1` works.
    private mutating func parsePower() throws -> Expr {
        let base = try parsePrimary()
        if consumeSymbol("^") {
            return .binary(.power, base, try parseUnary())
        }
        return base
    }

    /// A field-contents reference if one begins here: `field <ref>`,
    /// `card field <ref>`, `background field <ref>`, each with optional
    /// `id`. Returns nil (consuming nothing) otherwise.
    private mutating func parseFieldRefIfPresent() throws -> FieldRef? {
        let fieldWords: Set<String> = ["field", "fld"]
        // An optional leading article: `the field "X"`, `the card field 1`. Undo
        // the `the` if what follows isn't actually a field reference.
        let saved = index
        _ = consumeWord("the")
        let domain: HyperTalkObject.PartDomain
        if let w = peekIdentifier(), fieldWords.contains(w) {
            domain = .any
            advance()
        } else if let w = peekIdentifier(), Self.cardWords.contains(w),
                  let next = peekIdentifier(1), fieldWords.contains(next) {
            domain = .card
            advance()
            advance()
        } else if let w = peekIdentifier(), Self.backgroundWords.contains(w),
                  let next = peekIdentifier(1), fieldWords.contains(next) {
            domain = .background
            advance()
            advance()
        } else {
            index = saved
            return nil
        }
        let isID = consumeWord("id")
        // Parse the name/number with bare `<word> of <object>` property reads
        // suppressed, so a bareword-named field with a card scope — `cd fld
        // verse of cd haiku` (Haiku Master) — stops the name at `verse` and
        // leaves `of cd haiku` for the card-scope parse, instead of greedily
        // reading `verse of cd haiku` as the property `verse` of a card.
        let savedSuppress = suppressBarePropertyOf
        suppressBarePropertyOf = true
        let expr = try parsePrimary()
        suppressBarePropertyOf = savedSuppress
        return FieldRef(domain: domain, isID: isID, expr: expr, card: try parseFieldCardRef())
    }

    /// An optional `of <card>` after a field reference — `field "X" of prev
    /// card`, `field 1 of card "About"`. Returns nil (consuming nothing) when
    /// no card owner follows.
    private mutating func parseFieldCardRef() throws -> CardRef? {
        // `of card N` or, as HyperCard also allows, `in card N`
        // (`put card field "chain" in card 81 into beer`). `into` is a distinct
        // word, so it isn't mistaken for `in`; the reset below undoes a bare
        // `in` that isn't a card scope.
        guard peekIdentifier() == "of" || peekIdentifier() == "in" else { return nil }
        let saved = index
        advance() // of / in
        _ = consumeWord("the")
        let ref: CardRef
        if consumeWord("next") { _ = consumeCardWord(); ref = .next }
        else if consumeWord("previous") || consumeWord("prev") { _ = consumeCardWord(); ref = .previous }
        else if consumeWord("first") { _ = consumeCardWord(); ref = .first }
        else if consumeWord("last") { _ = consumeCardWord(); ref = .last }
        else if consumeWord("this") { _ = consumeCardWord() || consumeBackgroundWord(); ref = .current }
        else if consumeWord("recent") { _ = consumeCardWord(); ref = .previous } // most recent ≈ previous
        else if consumeWord("marked") { _ = consumeCardWord(); ref = .markedCard(try parsePrimary()) }
        else if consumeCardWord() {
            ref = consumeWord("id") ? .idExpression(try parsePrimary()) : .expression(try parsePrimary())
        } else {
            index = saved // not a card owner (e.g. `field "x" of the target`)
            return nil
        }
        // `last card of bkgnd "X"` — scope the card to that background;
        // `of bkgnd` / `of this bkgnd` scope to the current one.
        if let qualifier = try parseOfBackground() {
            switch qualifier {
            case .current: return .inBackground(ref, background: nil)
            case .named(let background): return .inBackground(ref, background: background)
            }
        }
        return ref
    }

    /// Consumes an `of <background> <name>` qualifier, returning the name
    /// expression. Returns nil (consuming nothing) when it isn't present, or
    /// when it's a bare `of <background>` with no name (dropped).
    /// A background scope after a card reference. `.named` carries the name
    /// expression; `.current` is the unnamed forms — `of bkgnd` bare and
    /// `of this bkgnd` — meaning the current card's background (DateBook's
    /// `go to last card of bkgnd` extends *its own* section, not the stack).
    enum BackgroundQualifier {
        case current
        case named(Expr)
    }

    /// Whether a bare word is part of an unquoted multi-word `go` destination
    /// name (`File Index`) rather than a trailing qualifier. Stops the name at
    /// the qualifier keywords HyperCard uses after a destination.
    private func isGoNameWord(_ word: String) -> Bool {
        !["of", "in", "without", "the"].contains(word)
    }

    private mutating func parseOfBackground() throws -> BackgroundQualifier? {
        // `of bkgnd …` or, as HyperCard also allows, `in bkgnd …`
        // (`the first card in background "User Pictures"`).
        guard peekIdentifier() == "of" || peekIdentifier() == "in" else { return nil }
        if let word = peekIdentifier(1), Self.backgroundWords.contains(word) {
            advance() // of / in
            advance() // background word
            _ = consumeWord("id") // `of bg id 9036` — id matched as a name, best effort
            guard current.kind != .newline, current.kind != .endOfScript, peekIdentifier() != "into" else {
                return .current // bare `of bkgnd` — the current background
            }
            return .named(try parsePrimary()) // the background name/number
        }
        if peekIdentifier(1) == "this", let word = peekIdentifier(2), Self.backgroundWords.contains(word) {
            advance(); advance(); advance() // of this <background word>
            return .current
        }
        return nil
    }

    /// Wraps a just-parsed card object in a background scope if a trailing
    /// `of [this] bkgnd [name]` follows (`card "Color" of bkgnd "Content"`,
    /// `card 2 of this bg`). Returns the bare object when there's no scope.
    private mutating func scopeCardObject(_ base: ObjectExpr) throws -> ObjectExpr {
        guard let qualifier = try parseOfBackground() else { return base }
        switch qualifier {
        case .current: return .cardInScope(base: base, background: nil)
        case .named(let background): return .cardInScope(base: base, background: background)
        }
    }

    private mutating func consumeCardWord() -> Bool {
        consumeWord("card") || consumeWord("cd") || consumeWord("cards") || consumeWord("cds")
    }

    /// Consume any background synonym (`background`/`bkgnd`/`bkgd`/`bg`).
    private mutating func consumeBackgroundWord() -> Bool {
        guard let w = peekIdentifier(), Self.backgroundWords.contains(w) else { return false }
        advance()
        return true
    }

    /// An object reference: typed part (`button "OK"`), `card 3`, or
    /// `this card` / `this background` / `this stack`.
    private mutating func parseObjectExpr() throws -> ObjectExpr {
        let line = current.line
        if consumeWord("this") {
            if consumeCardWord() { return .thisCard }
            if consumeBackgroundWord() { return .thisBackground }
            if consumeWord("stack") { return .thisStack }
            throw ScriptError(line: line, message: "Expected 'card', 'background', or 'stack' after 'this'.")
        }
        // `marked card N` as an object — `the short name of marked card 2`.
        if peekIdentifier() == "marked", let c = peekIdentifier(1), Self.cardWords.contains(c) {
            advance() // marked
            advance() // card
            return .markedCard(try parsePrimary())
        }
        // A card relative to the current one, used as an object for a property
        // read: `the id of next card`, `the short name of prev card`. (`go next
        // card` is handled separately in parseGo.)
        if let w = peekIdentifier(), ["next", "previous", "prev", "recent"].contains(w),
           let n = peekIdentifier(1), Self.cardWords.contains(n) {
            advance() // next/previous/prev/recent
            advance() // card word
            // A trailing `of [this] bkgnd` scope (`number of prev cd of this
            // bg` — The White Rose). Relative to the current card already, so
            // consume and ignore the background qualifier (best effort).
            _ = try parseOfBackground()
            return .cardRelative(w == "next" ? .next : .previous)
        }
        // Dispatch identity: `me` and `[the] target`.
        if consumeWord("me") { return .me }
        if peekIdentifier() == "target" || (peekIdentifier() == "the" && peekIdentifier(1) == "target") {
            _ = consumeWord("the")
            advance() // target
            return .target
        }
        // A leading `the` before an object is a noise article (`the last cd
        // btn`, `the moon`); the dispatch words (`me`, `the target`) above are
        // already handled.
        _ = consumeWord("the")
        func isPartKind(_ word: String?) -> Bool {
            guard let word else { return false }
            return Self.partKindSynonyms[word] != nil
        }

        // Windows — `window "Tools"`, `card window`, `tool window`. Contrapt has
        // no window objects; they resolve to an absent object (property reads
        // empty, sets are no-ops) so old stacks that juggle palette/document
        // windows import and run. Checked before the card/part handling below so
        // `card window` isn't read as a card named "window".
        if peekIdentifier() == "window" {
            advance()
            _ = consumeWord("id")
            let name: Expr = current.kind == .newline || current.kind == .endOfScript || peekIdentifier() == "to"
                ? .stringLiteral("") : try parsePrimary()
            return .window(name)
        }
        if let w = peekIdentifier(), Self.windowQualifiers.contains(w), peekIdentifier(1) == "window" {
            advance() // qualifier
            advance() // window
            return .window(.stringLiteral(w))
        }
        // `file <path>` — `there is a file theFile`, `there is not a file
        // (thisFile)`. The path is any expression (literal, variable, or
        // parenthesized); the host answers existence.
        if peekIdentifier() == "file" {
            advance()
            let path: Expr = current.kind == .newline || current.kind == .endOfScript || peekIdentifier() == "to"
                ? .stringLiteral("") : try parsePrimary()
            return .file(path)
        }
        // Button families (HyperCard's radio-button grouping) aren't modeled, so
        // `family N` resolves to an absent object — `the selectedButton of
        // family 1` reads empty — letting stacks that use families import and
        // run. Reuses the window case's absent-object behavior.
        if peekIdentifier() == "family" {
            advance()
            _ = consumeWord("id")
            let name: Expr = current.kind == .newline || current.kind == .endOfScript || peekIdentifier() == "to"
                ? .stringLiteral("") : try parsePrimary()
            // `selectedButton of family 1 of first card` — a family scoped to a
            // card. Still unmodeled; consume and ignore the owning card.
            if consumeWord("of") { _ = try? parseObjectExpr() }
            return .window(name)
        }

        // A leading ordinal before `menuItem` — `last menuItem of menu 3`,
        // `first menuItem of menu "File"` — a custom menu's item object.
        if let w = peekIdentifier(), Self.ordinals[w] != nil || Self.ordinalKeyword(w) != nil,
           peekIdentifier(1) == "menuitem" {
            let selector: MenuItemSelector
            if let n = Self.ordinals[w] { selector = .expr(.numberLiteral(Double(n))) }
            else { selector = .ordinal(Self.ordinalKeyword(w) ?? .last) }
            advance() // ordinal
            advance() // menuitem
            if consumeWord("of") || consumeWord("in") {
                _ = consumeWord("menu")
                if let menuName = try? parsePrimary() {
                    return .menuItem(selector, menu: menuName)
                }
            }
            return .menu(.stringLiteral(""))
        }
        // A leading ordinal: `last cd btn`, `first card`, `middle field`,
        // `any button`. `first`…`tenth` are exact positions; `last`/`middle`/
        // `any` resolve against the live count when evaluated.
        if let w = peekIdentifier(), Self.ordinals[w] != nil || Self.ordinalKeyword(w) != nil,
           let next = peekIdentifier(1),
           isPartKind(next) || Self.cardWords.contains(next) || Self.backgroundWords.contains(next) {
            let numeric = Self.ordinals[w]
            let keyword = Self.ordinalKeyword(w)
            advance() // the ordinal word
            // Optional domain qualifier before a part kind (`last cd btn`).
            var ordDomain = HyperTalkObject.PartDomain.any
            if let q = peekIdentifier(), Self.cardWords.contains(q), isPartKind(peekIdentifier(1)) {
                advance(); ordDomain = .card
            } else if let q = peekIdentifier(), Self.backgroundWords.contains(q), isPartKind(peekIdentifier(1)) {
                advance(); ordDomain = .background
            }
            if let k = peekIdentifier(), let kind = Self.partKindSynonyms[k] {
                advance()
                if let n = numeric {
                    return .part(kind: kind, domain: ordDomain, name: .numberLiteral(Double(n)), card: parsePartScopeIfPresent())
                }
                return .partByOrdinal(kind: kind, domain: ordDomain, ordinal: keyword!)
            }
            if let c = peekIdentifier(), Self.cardWords.contains(c) {
                advance()
                if let n = numeric { return try scopeCardObject(.card(.numberLiteral(Double(n)))) }
                return try scopeCardObject(.cardByOrdinal(keyword!))
            }
            // `first bg` / `last bg` — background-by-ordinal isn't modeled;
            // resolve to the current background (best effort).
            if let b = peekIdentifier(), Self.backgroundWords.contains(b) {
                advance()
                return .thisBackground
            }
        }

        // Domain qualifier: `card field 1` / `bkgnd button "OK"`.
        var domain = HyperTalkObject.PartDomain.any
        if let w = peekIdentifier(), Self.cardWords.contains(w), isPartKind(peekIdentifier(1)) {
            advance()
            domain = .card
        } else if let w = peekIdentifier(), Self.backgroundWords.contains(w), isPartKind(peekIdentifier(1)) {
            advance()
            domain = .background
        }

        if let word = peekIdentifier(), let kind = Self.partKindSynonyms[word] {
            advance()
            if consumeWord("id") {
                let id = try parsePrimary()
                return .partByID(kind: kind, domain: domain, id: id, card: parsePartScopeIfPresent())
            }
            let name = try parsePrimary()
            return .part(kind: kind, domain: domain, name: name, card: parsePartScopeIfPresent())
        }
        // A background reference (`bkgnd`, `background`) → this background.
        // `bkgnd id 2717` / `bkgnd "Home Cards"` / `bkgnd 2` name a specific
        // background; Contrapt has one background context per card, so the
        // id/name/number is consumed and ignored.
        if let w = peekIdentifier(), Self.backgroundWords.contains(w) {
            advance()
            if consumeWord("id") { _ = try parsePrimary() }
            else if case .string = current.kind { advance() }
            else if case .number = current.kind { advance() }
            // `bg theBgName` — a bareword variable naming the background
            // (`there is a background theBgName`, HyperHacker). Consumed and
            // ignored (one bg context); stop at a condition/statement keyword.
            else if let n = peekIdentifier(),
                    !["then", "is", "of", "in", "to", "and", "or", "into", "from", "end", "the", "without"].contains(n) {
                advance()
            }
            return .thisBackground
        }
        if let w = peekIdentifier(), Self.cardWords.contains(w) {
            advance()
            if consumeWord("id") {
                return try scopeCardObject(.cardByID(try parsePrimary()))
            }
            // A bare `card`/`cd` with nothing naming a specific card → this card.
            if current.kind == .newline || current.kind == .endOfScript {
                return .thisCard
            }
            return try scopeCardObject(.card(try parsePrimary()))
        }
        // `stack "X"` / `stack <expr>` — a named stack (`this stack` is handled
        // above). A bare `stack` with nothing after is the current stack.
        if consumeWord("stack") {
            if current.kind == .newline || current.kind == .endOfScript {
                return .thisStack
            }
            return .stackNamed(try parsePrimary())
        }
        // `msg` / `message [box|window]` — HyperCard's message box.
        if let w = peekIdentifier(), w == "msg" || w == "message" {
            advance()
            _ = consumeWord("box") || consumeWord("window")
            return .messageBox
        }
        // Custom menus: `menu "X"` (the menu object), `menuItem <sel> of menu
        // "X"` (an item), `menuBar` (absent — the bar itself isn't an object).
        if let w = peekIdentifier(), w == "menu" || w == "menuitem" || w == "menubar" {
            advance()
            if w == "menubar" { return .menu(.stringLiteral("")) }
            _ = consumeWord("id")
            let name: Expr = (current.kind == .newline || current.kind == .endOfScript)
                ? .stringLiteral("") : try parsePrimary()
            if w == "menuitem", consumeWord("of") || consumeWord("in") {
                _ = consumeWord("menu")
                if let menuName = try? parsePrimary() {
                    return .menuItem(.expr(name), menu: menuName)
                }
            }
            return .menu(name)
        }
        // `last item of fieldList` / `first word of theList` — an ordinal-led
        // chunk whose VALUE names the object (a field descriptor held in a
        // list). The property applies to that indirect object: `the scroll of
        // last item of fieldList` (Power Tools, Car Care, 10th Anniversary).
        // Parse the chunk expression and defer resolution to run time.
        if let w = peekIdentifier(), let selector = Self.ordinalSelector(w),
           let k = peekIdentifier(1), let kind = Self.chunkKinds[k] {
            advance() // ordinal
            advance() // chunk kind
            guard consumeWord("of") || consumeWord("in") else {
                throw ScriptError(line: line, message: "Expected 'of' after '\(w) \(k)'.")
            }
            return .indirect(.chunk(kind, selector, try parsePrimary()))
        }
        // A parenthesized expression builds the object's descriptor inline —
        // `visible of (object && i)`, Power Tools' Super Grouper idiom.
        // Re-parsed as an object at run time, like a variable indirect.
        if case .symbol("(") = current.kind {
            advance()
            let expression = try parseExpression()
            guard consumeSymbol(")") else {
                throw ScriptError(line: line, message: "This '(' is missing its closing ')'.")
            }
            return .indirect(expression)
        }
        // A bare identifier here is an indirect reference: a container whose
        // value names the object (`set loc of theButton to …`, where
        // `theButton` holds "cd btn id 34"). Re-parsed at run time.
        if let word = peekIdentifier() {
            advance()
            return .indirect(.variable(word))
        }
        throw ScriptError(line: line, message: "Expected an object here, like button \"OK\", field \"Name\", card 2, or this card.")
    }

    /// The types recognized by `is a[n] <type>`.
    static let typeNames: Set<String> = [
        "number", "integer", "point", "rect", "rectangle", "logical", "boolean", "date",
    ]

    /// Functions readable as `the <fn> of X`, not just `fn(X)`.
    static let foundFields: [String: FoundField] = [
        "foundtext": .text, "foundchunk": .chunk, "foundline": .line, "foundfield": .field,
    ]

    /// `the clickLine` / `the clickText` — where the last locked-field click
    /// landed (HyperCard 2.2's list-navigation idiom).
    static let clickFields: [String: ClickField] = [
        "clickline": .line, "clicktext": .text, "clickloc": .location,
    ]

    /// `the selectedLine` etc. — the script selection set by `select`.
    /// `the selection` is HyperCard's synonym for the selected text.
    static let selectionFields: [String: SelectionComponent] = [
        "selectedline": .line, "selectedtext": .text,
        "selectedchunk": .chunk, "selectedfield": .field,
        "selection": .text,
    ]

    static let oneArgFunctions: Set<String> = [
        "sqrt", "sin", "cos", "tan", "atan", "exp", "exp1", "exp2",
        "ln", "ln1", "log2", "abs", "trunc", "round", "average", "sum",
        // `the random of N` / `random of N` — the Manhole's idle animation
        // (`if the random of 2 is 1 then …`). `random(N)` already works.
        "random",
    ]

    /// Functions whose single argument may be written `<fn> of X` without a
    /// leading `the` — `length of X`, `charToNum of X`, `sqrt of X`. The
    /// argument is an expression (value), not an object.
    static let functionsWithOf: Set<String> =
        oneArgFunctions.union(["length", "value", "chartonum", "numtochar", "param"])

    /// Words that connect or terminate a value (operators, keywords) — so a
    /// bareword like `menu` followed by one of these was itself the value, not a
    /// keyword taking a name (`if menu is "X"`, not the menu named "is").
    static let expressionConnectors: Set<String> = [
        "is", "and", "or", "then", "into", "of", "to", "from", "with", "within",
        "contains", "mod", "div", "else", "in",
    ]

    /// Adjectives HyperTalk allows before `name` — `the short name of …`,
    /// `long name of …`. Contrapt's `name` is already the bare name, so all
    /// three collapse to the `name` property.
    static let nameAdjectives: Set<String> = [
        "short", "long", "abbreviated", "abbrev", "abbr",
    ]

    /// Part nouns (and their HyperTalk abbreviations) → the canonical kind
    /// the host understands.
    static let partKindSynonyms: [String: String] = [
        "button": "button", "btn": "button",
        "field": "field", "fld": "field",
        "label": "label", "image": "image", "picture": "image",
        // `part` addresses any part by z-order, regardless of kind — `cd part 3`,
        // `the rect of cd part i`, `last cd part`. The host treats the "part"
        // pseudo-kind as a wildcard over buttons and fields.
        "part": "part",
    ]
    static let backgroundWords: Set<String> = ["background", "bkgnd", "bkgd", "bg"]
    static let cardWords: Set<String> = ["card", "cd"]
    /// Qualifiers HyperCard allows before `window`: `card window`, `tool
    /// window`, `pattern window`, `scroll window`, `fatbits window`. (`message
    /// window` is handled as the message box.)
    static let windowQualifiers: Set<String> = ["card", "cd", "tool", "pattern", "patterns",
                                                 "scroll", "fatbits", "variable"]
    /// Object-less global properties readable as `the <name>`. `stacks` (the
    /// open-stack list), `mouseclick` (a pending click), `mouse` (the button
    /// state, up/down), and `sound` (the playing sound's name, "done" when
    /// idle) are functions in HyperCard; they read the same way here.
    static let readableGlobalProperties: Set<String> = ["itemdelimiter", "userlevel", "stacks", "mouseclick", "mouse", "sound", "tool", "mouseloc", "mouseh", "mousev", "screenrect", "numberformat", "optionkey", "shiftkey", "commandkey", "cmdkey", "controlkey", "menus", "windows", "linesize", "pensize", "pattern", "penpattern", "filled", "centered", "brush", "multiple", "userlevel", "textarrows", "powerkeys", "blindtyping", "textheight", "textsize", "textfont", "textstyle", "textalign"]

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

    /// The positional keywords that resolve against a live count.
    static func ordinalKeyword(_ word: String) -> Ordinal? {
        switch word {
        case "last": return .last
        case "middle", "mid": return .middle
        case "any": return .any
        default: return nil
        }
    }

    /// The HyperCard application version Contrapt reports. A late 2.x, so
    /// stacks that require a minimum (`if the version of HyperCard < 1.2`)
    /// proceed to their modern path.
    static let hyperCardVersion = "2.4.1"

    /// Parses `the [long|short] version` — optionally `of HyperCard` — if one
    /// begins here (after `the`), returning the app version string. Consumes
    /// nothing and returns nil otherwise, including for `the version of <stack>`
    /// (a different, stack-specific property handled by the generic path).
    private mutating func parseHyperCardVersion() -> Expr? {
        let adjectives: Set<String> = ["long", "short"]
        let first = peekIdentifier()
        let hasAdjective = adjectives.contains(first ?? "")
        let noun = hasAdjective ? peekIdentifier(1) : first
        guard noun == "version" else { return nil }
        let afterNoun = hasAdjective ? 2 : 1
        if peekIdentifier(afterNoun) == "of" {
            // Only `of HyperCard` is the app version; `of <stack>` is different.
            guard peekIdentifier(afterNoun + 1) == "hypercard" else { return nil }
            if hasAdjective { advance() }
            advance() // version
            advance() // of
            advance() // hypercard
            return .stringLiteral(Self.hyperCardVersion)
        }
        if hasAdjective { advance() }
        advance() // version
        return .stringLiteral(Self.hyperCardVersion)
    }

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

    /// After `the number of`, reads a countable noun — `cards`,
    /// `backgrounds`, `[card|bkgnd] buttons/fields` — or nil if what follows
    /// isn't one (so the caller can fall back to a property like
    /// `the number of this card`). Consumes tokens only on success.
    private mutating func parseCountable() -> Countable? {
        let saved = index
        // `marked cards` / `marked cds` — cards whose `marked` property is true.
        if peekIdentifier() == "marked", let next = peekIdentifier(1), next == "cards" || next == "cds" {
            advance(); advance(); return .markedCards
        }
        // An optional layer qualifier: `card`/`bkgnd`/`background`.
        var domain: HyperTalkObject.PartDomain = .any
        var qualified = false
        switch peekIdentifier() {
        case "card", "cd":
            // Ambiguous with the `cards` plural; only treat as a qualifier if
            // a part-kind plural follows (`card buttons`, `card parts`).
            if let next = peekIdentifier(1), next == "buttons" || next == "btns"
                || next == "fields" || next == "flds" || next == "parts" || next == "part" {
                domain = .card; qualified = true; advance()
            }
        case "background", "bkgnd", "bg":
            domain = .background; qualified = true; advance()
        default:
            break
        }
        let noun = peekIdentifier()
        if !qualified {
            if noun == "cards" || noun == "cds" { advance(); return .cards(inBackground: nil) }
            if noun == "backgrounds" || noun == "bkgnds" || noun == "bgs" {
                advance(); return .backgrounds
            }
        }
        if noun == "buttons" || noun == "btns" {
            advance(); return .parts(kind: "button", domain: domain)
        }
        if noun == "fields" || noun == "flds" {
            advance(); return .parts(kind: "field", domain: domain)
        }
        // `[card|background] parts` — buttons and fields together (HyperCard's
        // `the number of card parts`). The pseudo-kind "part" counts both.
        if noun == "parts" || noun == "part" {
            advance(); return .parts(kind: "part", domain: domain)
        }
        index = saved
        return nil
    }

    /// After `the number of`, reads a count of things Contrapt doesn't model —
    /// `menuItems of menu "X"`, `menus` — or nil if what follows isn't one. Each
    /// counts as a literal 0 (no menus exist), so loops like `repeat with x = 1
    /// to the number of menuItems of menu "File"` simply never run. (Marked
    /// cards ARE modeled now — see `parseCountable`.) Consumes only on success.
    private mutating func parseUnmodeledCount() -> Expr? {
        let saved = index
        let noun = peekIdentifier()
        if noun == "menus" { advance(); return .menuCount }
        // `the number of windows` — the open-window count (card window +
        // scripted palettes), via the lines of `the windows`.
        if noun == "windows" { advance(); return .chunkCount(.line, .globalProperty("windows")) }
        guard noun == "menuitems" || noun == "menuitem" else { return nil }
        advance()
        // The owning menu: `of menu "File"`.
        if consumeWord("of") || consumeWord("in") {
            guard consumeWord("menu") else { index = saved; return nil }
            if let name = try? parsePrimary() { return .menuItemCount(name) }
        }
        return .numberLiteral(0)
    }

    /// Parses text as a container (a field or chunk-of-field) — the runtime
    /// half of `select <descriptor>`, where the descriptor came from `the
    /// clickLine` or a variable. Nil when it isn't a container.
    static func parseSoleContainer(_ source: String) -> Container? {
        guard let tokens = try? Tokenizer.tokenize(source) else { return nil }
        var parser = Parser(tokens: tokens)
        guard let container = try? parser.parseContainer(line: 0),
              parser.current.kind == .endOfScript || parser.current.kind == .newline else { return nil }
        return container
    }

    /// Parses text like "cd btns" as a countable noun — the runtime half of
    /// `the number of (<expr>)`, whose noun is computed. Nil if not countable.
    static func parseSoleCountable(_ source: String) -> Countable? {
        guard let tokens = try? Tokenizer.tokenize(source) else { return nil }
        var parser = Parser(tokens: tokens)
        return parser.parseCountable()
    }

    /// Wraps a card count with its background scope, returning a count Expr.
    /// A *dynamic* background (`of bg <variable>`) becomes `.cardCountInBackground`
    /// (resolved at run time); everything else uses the static `applyCountScope`.
    private mutating func parseCountExpr(_ countable: Countable, line: Int) throws -> Expr {
        if case .cards = countable {
            let saved = index
            if consumeWord("of") || consumeWord("in") {
                let isThis = consumeWord("this")
                let hasOrdinal = { if let w = self.peekIdentifier() { return w == "first" || w == "last" || w == "middle" || w == "any" || Self.ordinals[w] != nil }; return false }()
                if !isThis, !hasOrdinal, consumeBackgroundWord(), !consumeWord("id"),
                   case .identifier = current.kind {
                    // `of bg <variable>` — a runtime-named background.
                    let background = try parsePrimary()
                    return .cardCountInBackground(background)
                }
                index = saved // not a dynamic background — fall back to static
            }
        }
        return .count(applyCountScopeIfPresent(to: countable))
    }

    /// After a `number of <plural>` count, parses an optional
    /// `[of|in] [this|<ordinal>] card/background [id] [name|number]` scope.
    /// A *background* scope on a card count is captured — `number of cds in
    /// this bg` counts only that background's cards (the multi-background
    /// Home loop). Anything else (card scopes, scopes on non-card counts) is
    /// consumed and ignored as before. Restores the cursor if what follows
    /// isn't actually a card/background scope.
    private mutating func applyCountScopeIfPresent(to countable: Countable) -> Countable {
        let saved = index
        guard consumeWord("of") || consumeWord("in") else { return countable }
        let isThis = consumeWord("this")
        var ordinal: String?
        if let w = peekIdentifier(),
           w == "first" || w == "last" || w == "middle" || w == "any" || Self.ordinals[w] != nil {
            ordinal = w
            advance()
        }
        if consumeBackgroundWord() {
            let isID = consumeWord("id")
            var reference: HyperTalkObject.Reference?
            if case .number(let value) = current.kind {
                advance()
                reference = isID ? .id(Value.string(from: value)) : .number(Int(value))
            } else if case .string(let text) = current.kind {
                advance()
                reference = .named(text)
            }
            guard case .cards = countable else { return countable }
            let scope: Countable.BackgroundScope
            if isThis {
                scope = .current
            } else if let reference {
                scope = .reference(reference)
            } else if let ordinal, let n = Self.ordinals[ordinal] {
                scope = .reference(.number(n))
            } else if ordinal == nil {
                // Bare `in bg` reads as the current background.
                scope = .current
            } else {
                // last/middle/any background — not modeled; current is the
                // least-wrong reading (it was the whole stack before).
                scope = .current
            }
            return .cards(inBackground: scope)
        }
        if consumeCardWord() {
            // A card scope on a count is meaningless — consume and ignore.
            _ = consumeWord("id")
            if case .number = current.kind { advance() }
            else if case .string = current.kind { advance() }
            return countable
        }
        if consumeWord("stack") {
            // `in this stack` / `of stack "X"` — the whole-stack scope, which is
            // already the default; consume an optional stack name/id and ignore.
            _ = consumeWord("id")
            if case .number = current.kind { advance() }
            else if case .string = current.kind { advance() }
            return countable
        }
        index = saved
        return countable
    }

    /// A part reference may be scoped to a specific card/background —
    /// `cd btn id 8 of cd "Stack Menus"`, `cd fld 2 of this card`, `bg btn X
    /// of first bg`. A *card* scope is captured (the part lives on that card
    /// and property reads/writes resolve there); a *background* scope is
    /// parsed and ignored, since Contrapt's background parts are shared
    /// across cards. Restores the cursor if the `of …` isn't actually a
    /// card/background scope. Scopes chain (`bg btn id 68 of cd 1 of bg
    /// "Graphs"`); the innermost card scope wins.
    private mutating func parsePartScopeIfPresent() -> CardRef? {
        var cardScope: CardRef?
        while true {
            let saved = index
            // `of card N` or, as HyperCard also allows, `in card N`
            // (`show card button "X" in card 81`). The no-match reset below keeps
            // a bare `in` that isn't a card scope from being consumed.
            guard consumeWord("of") || consumeWord("in") else { return cardScope }
            let isThis = consumeWord("this")
            var ordinal: String?
            if let w = peekIdentifier(),
               w == "first" || w == "last" || w == "middle" || w == "any" || Self.ordinals[w] != nil {
                ordinal = w
                advance()
            }
            if consumeWord("marked") {
                // `… of marked card N` — scope the part/field to the Nth marked
                // card (`bg field "X" of marked card CardCount`).
                _ = consumeCardWord()
                let n = (try? parsePrimary()) ?? .numberLiteral(1)
                if cardScope == nil { cardScope = .markedCard(n) }
            } else if let w = peekIdentifier(), ["next", "previous", "prev"].contains(w),
                      let n = peekIdentifier(1), Self.cardWords.contains(n) {
                // `… of next/prev card` — the part on the adjacent card
                // (`there is a field "1" of prev card`, Fossils).
                advance() // next/previous/prev
                advance() // card word
                if cardScope == nil { cardScope = (w == "next") ? .next : .previous }
            } else if consumeCardWord() {
                let isID = consumeWord("id")
                // An optional identifier/number/string naming the card (`of cd
                // curCard`, `of card 5`) — but not a following statement keyword.
                // An ordinal (`first cd`, `last cd`) or `this cd` already fully
                // specifies the card, so DON'T consume the next token as a name
                // (it belongs to the rest of the expression, e.g. `of first cd
                // is true` — the `is` is a comparison, not a card name).
                var name: Expr?
                if ordinal == nil, !isThis,
                   current.kind != .newline, current.kind != .endOfScript, peekIdentifier() != "to" {
                    name = try? parsePrimary()
                }
                if cardScope == nil {
                    if isThis {
                        cardScope = .current
                    } else if let ordinal {
                        switch ordinal {
                        case "first": cardScope = .first
                        case "last": cardScope = .last
                        case "middle", "any": cardScope = .current // best effort
                        default: cardScope = .expression(.numberLiteral(Double(Self.ordinals[ordinal] ?? 1)))
                        }
                    } else if let name {
                        cardScope = isID ? .idExpression(name) : .expression(name)
                    } else {
                        cardScope = .current
                    }
                }
            } else if consumeBackgroundWord() {
                // Background scope: `… of cd 1 of bg "Graphs"` scopes the card
                // to that background (so the part resolves against bg "Graphs",
                // not the current background). `… of bg "X"` with no card means
                // a card of that background (best effort: its current one).
                _ = consumeWord("id")
                var backgroundName: Expr?
                if current.kind != .newline, current.kind != .endOfScript, peekIdentifier() != "to" {
                    backgroundName = try? parsePrimary()
                }
                cardScope = .inBackground(cardScope ?? .current, background: backgroundName)
            } else {
                index = saved
                return cardScope
            }
        }
    }

    /// Maps an ordinal word (or last/middle) to a chunk selector.
    static func ordinalSelector(_ word: String) -> ChunkSelector? {
        if let n = ordinals[word] { return .index(.numberLiteral(Double(n))) }
        if word == "last" { return .last }
        if word == "middle" { return .middle }
        if word == "any" { return .any } // `any item of X` — a random chunk
        return nil
    }

    /// A primary with any trailing array-index postfixes — `a["k"]`,
    /// `data["a"]["b"]`. `[` binds tighter than every operator (it's postfix on
    /// the atom). HyperCard never used `[`, so this is unambiguous.
    private mutating func parsePrimary() throws -> Expr {
        var expr = try parsePrimaryAtom()
        while consumeSymbol("[") {
            let key = try parseExpression()
            guard consumeSymbol("]") else {
                throw ScriptError(line: current.line, message: "Expected ']' after an array key.")
            }
            expr = .element(key: key, base: expr)
        }
        return expr
    }

    private mutating func parsePrimaryAtom() throws -> Expr {
        let line = current.line
        expressionDepth += 1
        defer { expressionDepth -= 1 }
        guard expressionDepth <= Self.maxExpressionDepth else {
            throw ScriptError(line: line, message: "This expression is nested too deeply.")
        }
        switch current.kind {
        case .number(let value):
            advance()
            return .numberLiteral(value)
        case .string(let text):
            advance()
            return .stringLiteral(text)
        case .symbol("("):
            advance()
            let savedSuppress = suppressBarePropertyOf
            suppressBarePropertyOf = false
            let inner = try parseExpression()
            suppressBarePropertyOf = savedSuppress
            guard consumeSymbol(")") else {
                throw ScriptError(line: line, message: "This '(' is missing its closing ')'.")
            }
            return inner
        case .identifier("field"), .identifier("fld"),
             .identifier("card"), .identifier("cd"),
             .identifier("background"), .identifier("bkgnd"), .identifier("bkgd"), .identifier("bg"):
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
            // `the foundText` / `foundChunk` / `foundLine` / `foundField`.
            if let found = Self.foundFields[peekIdentifier() ?? ""], peekIdentifier(1) != "of" {
                advance()
                return .found(found)
            }
            // `the clickLine` / `the clickText`.
            if let click = Self.clickFields[peekIdentifier() ?? ""], peekIdentifier(1) != "of" {
                advance()
                return .click(click)
            }
            // `the selectedLine` / `selectedText` / `selectedChunk` /
            // `selectedField` / `the selection`.
            if let component = Self.selectionFields[peekIdentifier() ?? ""], peekIdentifier(1) != "of" {
                advance()
                return .selected(component)
            }
            // `the [long|short] version [of HyperCard]` — the HyperCard
            // application version, which stacks gate startup on.
            if let version = parseHyperCardVersion() {
                return version
            }
            // `the [long|short|abbreviated] date/time`, `the seconds/ticks`.
            if let field = parseClockField() {
                return .clock(field)
            }
            // Object-less global properties Contrapt can read (`the
            // itemDelimiter`, `the userLevel`).
            if let word = peekIdentifier(), Self.readableGlobalProperties.contains(word),
               peekIdentifier(1) != "of" {
                advance()
                return .globalProperty(word)
            }
            // `the target` on its own → the target object's name.
            if peekIdentifier() == "target", peekIdentifier(1) != "of" {
                advance()
                return .property("name", .target)
            }
            // `the value of X` → evaluate X (a string) as an expression.
            if peekIdentifier() == "value", peekIdentifier(1) == "of" {
                advance() // value
                advance() // of
                return .call("value", [try parsePrimary()])
            }
            // `the length of X` → character count.
            if peekIdentifier() == "length", peekIdentifier(1) == "of" {
                advance() // length
                advance() // of
                return .call("length", [try parsePrimary()])
            }
            // `the sqrt of X`, `the charToNum of X`, `the param of N`, etc. —
            // one-argument functions written with `the … of`.
            if let function = peekIdentifier(), Self.functionsWithOf.contains(function),
               peekIdentifier(1) == "of" {
                advance() // function
                advance() // of
                return .call(function, [try parsePrimary()])
            }
            // `the paramCount` / `the params` — zero-argument handler-arg readers.
            if let w = peekIdentifier(), w == "paramcount" || w == "params" {
                advance()
                return .call(w, [])
            }
            // `the keys of <array>` / `the number of elements of <array>` —
            // associative-array readers (Contrapt structured data).
            if peekIdentifier() == "keys", peekIdentifier(1) == "of" {
                advance() // keys
                advance() // of
                return .arrayKeys(try parsePrimary())
            }
            if peekIdentifier() == "number", peekIdentifier(1) == "of",
               peekIdentifier(2) == "elements", peekIdentifier(3) == "of" {
                advance(); advance(); advance(); advance() // number of elements of
                return .elementCount(try parsePrimary())
            }
            // `the number of words of X` → chunk count (but not
            // `the number of this card`, which is a card property).
            if peekIdentifier() == "number", peekIdentifier(1) == "of",
               let kindWord = peekIdentifier(2), let kind = Self.chunkKinds[kindWord] {
                advance() // number
                advance() // of
                advance() // kind
                guard consumeWord("of") || consumeWord("in") else {
                    throw ScriptError(line: line, message: "Expected 'of' after 'the number of \(kindWord)'.")
                }
                return .chunkCount(kind, try parsePrimary())
            }
            // `the number of cards / backgrounds / [card|bkgnd] buttons/fields`.
            if peekIdentifier() == "number", peekIdentifier(1) == "of" {
                let saved = index
                advance() // number
                advance() // of
                if let countable = parseCountable() {
                    return try parseCountExpr(countable, line: line)
                }
                if let unmodeled = parseUnmodeledCount() { return unmodeled }
                // `the number of (<expr>)` — the noun is computed at run time
                // (`the number of (item i of list & "s")` → "cd btns").
                if case .symbol("(") = current.kind {
                    return .countDynamic(try parsePrimary())
                }
                index = saved // not a count noun — let a property handle it
            }
            // `the first word of X`, `the last line of X`, etc.
            if let ordinalWord = peekIdentifier(),
               let selector = Self.ordinalSelector(ordinalWord),
               let kindWord = peekIdentifier(1), let kind = Self.chunkKinds[kindWord] {
                advance() // ordinal
                advance() // kind
                guard consumeWord("of") || consumeWord("in") else {
                    throw ScriptError(line: line, message: "Expected 'of' after '\(ordinalWord) \(kindWord)'.")
                }
                return .chunk(kind, selector, try parsePrimary())
            }
            // `the short name of X` → the bare `name`; `the long name of X` →
            // the HyperCard-style descriptor (`stack "Graph Maker"`). Same for
            // `id`: `the long id of this cd` → the descriptor (`card id 34`).
            if let adjective = peekIdentifier(), Self.nameAdjectives.contains(adjective),
               let noun = peekIdentifier(1), noun == "name" || noun == "id",
               peekIdentifier(2) == "of" {
                advance() // adjective
                advance() // name/id
                advance() // of
                let long = adjective == "long"
                let property = noun == "name" ? (long ? "longname" : "name") : (long ? "longid" : "id")
                return .property(property, try parseObjectExpr())
            }
            // `the <property> of <object>`; otherwise "the" is a noise
            // word before a value ("the date" → the unquoted literal).
            if peekIdentifier() != nil, peekIdentifier(1) == "of" {
                let property = peekIdentifier()!
                advance() // property
                advance() // of
                // `the textStyle of line 2 of field "X"` — a run property of a
                // chunk of a field (the base after `of` is a chunk kind).
                if Self.chunkKinds[peekIdentifier() ?? ""] != nil {
                    return .chunkProperty(property.lowercased(), try parseContainer(line: line))
                }
                return .property(property.lowercased(), try parseObjectExpr())
            }
            return try parsePrimary()
        case .identifier(let word) where Self.chunkKinds[word] != nil && chunkKeywordStartsChunk():
            // `word 2 of X`, `char 1 to 5 of X`. (A chunk keyword NOT followed
            // by an index — `item is …`, `put line` — falls to the identifier
            // case below and reads as a variable.)
            let kind = Self.chunkKinds[word]!
            advance()
            let savedSuppress = suppressBarePropertyOf
            suppressBarePropertyOf = true
            // The index is an arithmetic expression (`item (x mod 12)+1 of …`)
            // — parse at the additive level so it stops before `of`/`to`/`&`.
            let start = try parseAdditive()
            let selector: ChunkSelector = consumeWord("to")
                ? .range(start, try parseAdditive())
                : .index(start)
            suppressBarePropertyOf = savedSuppress
            guard consumeWord("of") || consumeWord("in") else {
                throw ScriptError(line: line, message: "Expected 'of' after '\(word)', like: \(word) 2 of field \"Notes\".")
            }
            return .chunk(kind, selector, try parsePrimary())
        case .identifier(let word):
            advance()
            // `there is a[n] <object>` / `there is no <object>` /
            // `there is not a[n] <object>` — existence.
            if word == "there", consumeWord("is") {
                let negated = consumeWord("no") || consumeWord("not")
                _ = consumeWord("a") || consumeWord("an")
                return .exists(try parseObjectExpr(), negated: negated)
            }
            // `me` / `target` on their own → the object's name (HyperTalk
            // reserves both words for dispatch identity).
            if word == "me" { return .meValue }
            if word == "target" { return .property("name", .target) }
            // `[the] msg [box|window]` / `message [box|window]` read as a value —
            // the message box's current contents (`if the message box is not
            // empty`, `first char of the message box`).
            if word == "msg" || word == "message" {
                if let next = peekIdentifier(), next == "box" || next == "window" { advance() }
                return .messageBoxValue
            }
            // `menu "X"` read as a value — its items, one per line, in
            // HyperCard (`line 4 to 9 of menu "InUse"`, `line 8 of menu it`).
            // Contrapt has no menus, so it reads empty. A literal, parenthesized,
            // or variable name follows the keyword; a bare `menu` (nothing after)
            // stays a plain variable.
            if word == "menu" {
                switch current.kind {
                case .string, .number, .symbol("("):
                    return .property("text", .menu(try parsePrimary()))
                case .identifier(let name) where !Self.expressionConnectors.contains(name):
                    // `line 8 of menu it` — a variable names the menu. But a
                    // following operator/keyword (`menu is …`, `menu & …`) means
                    // `menu` was itself the variable, not a menu keyword.
                    advance()
                    return .property("text", .menu(.variable(name)))
                default:
                    break
                }
            }
            // `menuItem N of menu "X"` read as a value — the item's text. Menus
            // aren't modeled, so it reads empty (`get name of … menuItem …`,
            // `last menuItem of menu 3 is "-"`). A leading ordinal is handled
            // just below, where `word` is the ordinal.
            if word == "menuitem" {
                if case .number = current.kind { advance() }
                if consumeWord("of") || consumeWord("in") { _ = consumeWord("menu"); _ = try? parsePrimary() }
                return .property("text", .menu(.stringLiteral("")))
            }
            if Self.ordinalSelector(word) != nil, peekIdentifier() == "menuitem" {
                advance() // menuitem
                if case .number = current.kind { advance() }
                if consumeWord("of") || consumeWord("in") { _ = consumeWord("menu"); _ = try? parsePrimary() }
                return .property("text", .menu(.stringLiteral("")))
            }
            // Bare `number of cards/backgrounds/buttons/fields [scope]` — a
            // count (HyperTalk's `the` is optional). `number of this card`
            // (an ordinal property) isn't countable, so it falls through.
            if word == "number", peekIdentifier() == "of" {
                let saved = index
                advance() // of
                if let countable = parseCountable() {
                    return try parseCountExpr(countable, line: line)
                }
                if let unmodeled = parseUnmodeledCount() { return unmodeled }
                // Bare `number of chars/words/lines/items in X` — a chunk
                // count without the leading `the` (mirrors the `the number
                // of words of X` handling above).
                if let kindWord = peekIdentifier(), let kind = Self.chunkKinds[kindWord] {
                    advance() // kind
                    guard consumeWord("of") || consumeWord("in") else {
                        throw ScriptError(line: line, message: "Expected 'of' after 'number of \(kindWord)'.")
                    }
                    return .chunkCount(kind, try parsePrimary())
                }
                // `number of (<expr>)` — a computed noun, `the` optional.
                if case .symbol("(") = current.kind {
                    return .countDynamic(try parsePrimary())
                }
                index = saved // e.g. `number of this cd` → the ordinal property
            }
            // Bare ordinal chunk: `last char of X`, `first word of X`,
            // `middle line of X` — HyperTalk's `the` is optional.
            if !suppressBarePropertyOf, let selector = Self.ordinalSelector(word),
               let kindWord = peekIdentifier(), let kind = Self.chunkKinds[kindWord] {
                advance() // chunk kind
                guard consumeWord("of") || consumeWord("in") else {
                    throw ScriptError(line: line, message: "Expected 'of' after '\(word) \(kindWord)'.")
                }
                return .chunk(kind, selector, try parsePrimary())
            }
            // Bare `<property> of <object>` — HyperTalk lets you drop the
            // leading `the`, e.g. `loc of field "x"`, `rect of card field 2`.
            // A plain variable is never legitimately followed by `of`, so
            // treating `<ident> of …` as a property access is safe.
            // `short name of X` → `name`; `long name of X` → the descriptor.
            // Not gated by suppressBarePropertyOf: `short/long name of X` is
            // unambiguous, so `go cd short name of target` must parse (the
            // suppression exists only for the generic `<var> of` form below,
            // which would otherwise eat `go card whichSix of stack "X"`).
            if Self.nameAdjectives.contains(word),
               let noun = peekIdentifier(), noun == "name" || noun == "id",
               peekIdentifier(1) == "of" {
                advance() // name/id
                advance() // of
                let long = word == "long"
                let property = noun == "name" ? (long ? "longname" : "name") : (long ? "longid" : "id")
                return .property(property, try parseObjectExpr())
            }
            // Bare `<function> of X` (no leading `the`) — `length of theText`,
            // `charToNum of last char of fld "X"`, `sqrt of n`. The argument is
            // an expression (its value), unlike the `<property> of <object>`
            // form below. Checked first so function words aren't read as
            // properties of an object. Suppressed inside a chunk index, where a
            // variable can share a function's name (`line Ln of X` — `Ln`
            // lowercases to the `ln` function — must stay a chunk, not ln(X)).
            if !suppressBarePropertyOf, peekIdentifier() == "of",
               Self.functionsWithOf.contains(word.lowercased()) {
                advance() // of
                return .call(word, [try parsePrimary()])
            }
            if !suppressBarePropertyOf, peekIdentifier() == "of" {
                advance() // of
                // `textStyle of line 2 of fld "X"` — a run property of a chunk.
                if Self.chunkKinds[peekIdentifier() ?? ""] != nil {
                    return .chunkProperty(word.lowercased(), try parseContainer(line: line))
                }
                return .property(word.lowercased(), try parseObjectExpr())
            }
            // `name(args)` — a function call. Otherwise a plain variable.
            if case .symbol("(") = current.kind {
                advance()
                var arguments: [Expr] = []
                if case .symbol(")") = current.kind {} else {
                    repeat {
                        // A trailing comma is an empty final argument, which
                        // HyperCard tolerates (`selectType("x",1,2,)` — Tubers).
                        if case .symbol(")") = current.kind {
                            arguments.append(.stringLiteral(""))
                            break
                        }
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
