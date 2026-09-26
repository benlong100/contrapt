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
                // Loose text outside any handler — decorative banners, notes,
                // the "MESSAGE HANDLERS IN THIS SCRIPT" comment blocks common in
                // Apple's stacks. HyperCard ignores it; skip the line and go on.
                while current.kind != .newline, current.kind != .endOfScript { advance() }
                if current.kind == .newline { advance() }
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
            let prompt = try parseExpression()
            var buttons: [Expr] = []
            if consumeWord("with") {
                // Buttons are separated by `or`; parse below it so `or` isn't
                // swallowed as the boolean operator.
                buttons.append(try parseConcatenation())
                while consumeWord("or") { buttons.append(try parseConcatenation()) }
            }
            try expectNewline()
            return Stmt(kind: .answer(prompt, buttons: buttons), line: line)
        case "ask":
            advance()
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
            // `send <message> to <object>` — dispatch to a specific object.
            let message = try parseExpression()
            guard consumeWord("to") else {
                throw ScriptError(line: line, message: "Expected 'to <object>' after 'send <message>'.")
            }
            let object = try parseObjectExpr()
            try expectNewline()
            return Stmt(kind: .sendMessage(message, to: object), line: line)
        case "delete":
            // `delete menu "X"`, `delete button …`, etc. Contrapt doesn't model
            // object deletion via this verb (card deletion is `doMenu "Delete
            // Card"`), and no sample uses chunk deletion — so accept and ignore
            // so stacks that manage their own menus/objects don't error.
            advance()
            while current.kind != .newline, current.kind != .endOfScript { advance() }
            try expectNewline()
            return Stmt(kind: .noOp, line: line)
        case "choose", "drag", "type", "reset":
            // Paint/tool automation Contrapt doesn't model: `choose <tool>
            // tool`, `drag from a to b`, `type "…"`, `reset paint`. Accepted
            // and ignored so old paint scripts don't error.
            advance()
            while current.kind != .newline, current.kind != .endOfScript { advance() }
            try expectNewline()
            return Stmt(kind: .noOp, line: line)
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
        case "sort":
            advance()
            return try parseSort(line: line)
        case "show", "hide":
            advance()
            return try parseShowHide(visible: word == "show", line: line)
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
                throw ScriptError(line: line, message: "Expected a property name after 'set'.")
            }
            advance()
            if consumeWord("of") {
                let object = try parseObjectExpr()
                guard consumeWord("to") else {
                    throw ScriptError(line: line, message: "Expected 'to' and a value at the end of 'set'.")
                }
                let value = try parseSetValue()
                try expectNewline()
                return Stmt(kind: .set(property: property.lowercased(), object: object, value: value), line: line)
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
            advance()
            var arguments: [Expr] = []
            if current.kind != .newline, current.kind != .endOfScript {
                repeat {
                    arguments.append(try parseExpression())
                } while consumeSymbol(",")
            }
            // Unknown commands with bespoke syntax (`choose select tool`,
            // `drag from a to b`, `doMenu "…"`) may leave tokens we can't parse
            // as arguments. Rather than fail the whole script, skip the rest of
            // the line — the command still dispatches as a message, surfacing
            // at run time only if nothing handles it (HyperCard semantics).
            while current.kind != .newline, current.kind != .endOfScript { advance() }
            try expectNewline()
            return Stmt(kind: .send(word, arguments), line: line)
        }
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
            let savedSuppress = suppressBarePropertyOf
            suppressBarePropertyOf = true
            // The index is an arithmetic expression (`item (x mod 12)+1 of …`)
            // — parse at the additive level so it stops before `of`/`to`/`&`.
            let start = try parseAdditive()
            let selector: ChunkSelector = consumeWord("to")
                ? .range(start, try parseAdditive())
                : .index(start)
            suppressBarePropertyOf = savedSuppress
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
    /// An optional `to <image>` clause is tolerated but ignored for now.
    private mutating func parseVisualEffect(line: Int) throws -> ScreenEffect {
        guard let first = peekIdentifier() else {
            throw ScriptError(line: line, message: "Expected an effect after 'visual effect', like dissolve or wipe left.")
        }
        advance()
        let kind: ScreenEffect.Kind
        switch first {
        case "dissolve": kind = .dissolve
        case "wipe": kind = .wipe
        case "scroll": kind = .scroll
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
        default:
            throw ScriptError(line: line, message: "Unknown visual effect '\(first)'.")
        }

        var direction: ScreenEffect.Direction?
        if let word = peekIdentifier(), let parsed = ScreenEffect.Direction(rawValue: word) {
            advance()
            direction = parsed
        }

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
            guard let reference = try parseFieldRefIfPresent() else {
                throw ScriptError(line: line, message: "Expected a field after 'in', like: find \"x\" in field \"Notes\".")
            }
            field = reference
        }
        try expectNewline()
        return Stmt(kind: .find(mode, text: text, inField: field), line: line)
    }

    /// A `doMenu` item: a quoted string or single variable is an expression
    /// (`doMenu "New Card"`, `doMenu menuItem`); bare multi-word text is the
    /// literal menu name (`doMenu Select All`, `doMenu clear picture`).
    private mutating func parseMenuItem() throws -> Expr {
        if case .string = current.kind {
            let item = try parseExpression()
            try expectNewline()
            return item
        }
        var words: [String] = []
        while current.kind != .newline, current.kind != .endOfScript {
            if let word = peekIdentifier() { words.append(word) }
            else if case .string(let text) = current.kind { words.append(text) }
            else if case .number(let value) = current.kind { words.append(Value.string(from: value)) }
            advance()
        }
        try expectNewline()
        // A lone bare word is a variable holding the item; multiple words are
        // the literal menu name.
        if words.count == 1 { return .variable(words[0]) }
        return .stringLiteral(words.joined(separator: " "))
    }

    /// `sort [this stack] [marked] [cards] [of …] [ascending|descending]
    /// [text|numeric|international|dateTime] by <expr>` — reorders the stack's
    /// cards. Contrapt sorts the whole stack; qualifiers it doesn't model
    /// (marked, of a background) are accepted and ignored.
    private mutating func parseSort(line: Int) throws -> Stmt {
        _ = consumeWord("this"); _ = consumeWord("stack")
        _ = consumeWord("marked")
        _ = consumeCardWord()
        // An `of <object>` scope we don't model — skip up to `by`.
        if peekIdentifier() == "of" {
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
        // Ignorable targets.
        let ignorable = ["menubar", "menu", "titlebar", "message", "msg", "tool",
                         "pattern", "patterns", "picture", "pict", "background",
                         "card", "bkgnd", "bg", "all", "cards", "window", "windows",
                         "groups", "scroll"]
        if let first = peekIdentifier(), ignorable.contains(first),
           !isPartReference() {
            while current.kind != .newline, current.kind != .endOfScript { advance() }
            try expectNewline()
            return Stmt(kind: .noOp, line: line)
        }
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

    /// Whether what's ahead is a part reference like `card button "X"` /
    /// `field 1` (so `show card button…` isn't mistaken for the ignorable
    /// `card picture`).
    private func isPartReference() -> Bool {
        let partKinds = ["button", "field", "label", "image"]
        if let w = peekIdentifier(), partKinds.contains(w) { return true }
        if let w = peekIdentifier(), ["card", "background", "bg", "bkgnd"].contains(w),
           let next = peekIdentifier(1), partKinds.contains(next) { return true }
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
        if consumeWord("next") {
            _ = consumeCardWord()
            target = .next
        } else if consumeWord("previous") || consumeWord("prev") {
            _ = consumeCardWord()
            target = .previous
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
        } else if consumeCardWord() {
            if consumeWord("id") {
                target = .idExpression(try parseExpression())
            } else {
                target = .expression(try parseExpression())
            }
        } else if consumeWord("stack") {
            // `go [to] stack "X"` — another stack (opens at its first card).
            target = .inStack(name: try parseExpression(), card: nil)
        } else if current.kind != .newline && current.kind != .endOfScript {
            // A bare `go [to] "Name"` — a card by name/number.
            target = .expression(try parseExpression())
        } else {
            throw ScriptError(line: line, message: "Expected a destination after 'go', like 'next card' or 'card 3'.")
        }
        // Trailing qualifiers compose innermost-first, as HyperCard writes them:
        // `go cd X of bkgnd "Paths" of stack "Home"` = (card X in background
        // "Paths") in stack "Home".
        if let background = try parseOfBackground() {
            target = .inBackground(target, background: background)
        }
        if peekIdentifier() == "of", peekIdentifier(1) == "stack" {
            advance(); advance() // of stack
            target = .inStack(name: try parseExpression(), card: target)
        }
        if peekIdentifier() == "of" {
            // Some other trailing `of …` qualifier we don't model — ignore it.
            while current.kind != .newline, current.kind != .endOfScript { advance() }
        }
        try expectNewline()
        return Stmt(kind: .go(target), line: line)
    }

    private mutating func parseIf(handlerName: String, line: Int) throws -> Stmt {
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
            return .unary(.minus, try parseUnary())
        }
        if peekIdentifier() == "not" {
            advance()
            return .unary(.not, try parseUnary())
        }
        return try parsePower()
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
            return nil
        }
        let isID = consumeWord("id")
        let expr = try parsePrimary()
        return FieldRef(domain: domain, isID: isID, expr: expr, card: try parseFieldCardRef())
    }

    /// An optional `of <card>` after a field reference — `field "X" of prev
    /// card`, `field 1 of card "About"`. Returns nil (consuming nothing) when
    /// no card owner follows.
    private mutating func parseFieldCardRef() throws -> CardRef? {
        guard peekIdentifier() == "of" else { return nil }
        let saved = index
        advance() // of
        _ = consumeWord("the")
        let ref: CardRef
        if consumeWord("next") { _ = consumeCardWord(); ref = .next }
        else if consumeWord("previous") || consumeWord("prev") { _ = consumeCardWord(); ref = .previous }
        else if consumeWord("first") { _ = consumeCardWord(); ref = .first }
        else if consumeWord("last") { _ = consumeCardWord(); ref = .last }
        else if consumeWord("this") { _ = consumeCardWord(); ref = .current }
        else if consumeCardWord() {
            ref = consumeWord("id") ? .idExpression(try parsePrimary()) : .expression(try parsePrimary())
        } else {
            index = saved // not a card owner (e.g. `field "x" of the target`)
            return nil
        }
        // `last card of bkgnd "X"` — scope the card to that background.
        if let background = try parseOfBackground() {
            return .inBackground(ref, background: background)
        }
        return ref
    }

    /// Consumes an `of <background> <name>` qualifier, returning the name
    /// expression. Returns nil (consuming nothing) when it isn't present, or
    /// when it's a bare `of <background>` with no name (dropped).
    private mutating func parseOfBackground() throws -> Expr? {
        guard peekIdentifier() == "of", let word = peekIdentifier(1),
              Self.backgroundWords.contains(word) else { return nil }
        advance() // of
        advance() // background word
        guard current.kind != .newline, current.kind != .endOfScript, peekIdentifier() != "into" else {
            return nil // bare `of bkgnd` — no name to scope by
        }
        return try parsePrimary() // the background name/number
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
                    return .part(kind: kind, domain: ordDomain, name: .numberLiteral(Double(n)))
                }
                return .partByOrdinal(kind: kind, domain: ordDomain, ordinal: keyword!)
            }
            if let c = peekIdentifier(), Self.cardWords.contains(c) {
                advance()
                if let n = numeric { return .card(.numberLiteral(Double(n))) }
                return .cardByOrdinal(keyword!)
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
            let part: ObjectExpr
            if consumeWord("id") {
                part = .partByID(kind: kind, domain: domain, id: try parsePrimary())
            } else {
                part = .part(kind: kind, domain: domain, name: try parsePrimary())
            }
            skipPartScopeIfPresent()
            return part
        }
        // A bare background reference (`bkgnd`, `background`) → this background.
        if let w = peekIdentifier(), Self.backgroundWords.contains(w) {
            advance()
            return .thisBackground
        }
        if let w = peekIdentifier(), Self.cardWords.contains(w) {
            advance()
            if consumeWord("id") {
                return .cardByID(try parsePrimary())
            }
            // A bare `card`/`cd` with nothing naming a specific card → this card.
            if current.kind == .newline || current.kind == .endOfScript {
                return .thisCard
            }
            return .card(try parsePrimary())
        }
        // `msg` / `message [box|window]` — HyperCard's message box.
        if let w = peekIdentifier(), w == "msg" || w == "message" {
            advance()
            _ = consumeWord("box") || consumeWord("window")
            return .messageBox
        }
        // Menus aren't modeled in Contrapt; `menu "X"`, `menuItem N of menu
        // "X"`, and `menuBar` still parse so old stacks that test for or delete
        // their own menus don't break. They resolve to an absent object.
        if let w = peekIdentifier(), w == "menu" || w == "menuitem" || w == "menubar" {
            advance()
            if w == "menubar" { return .menu(.stringLiteral("")) }
            _ = consumeWord("id")
            let name: Expr = (current.kind == .newline || current.kind == .endOfScript)
                ? .stringLiteral("") : try parsePrimary()
            // `menuItem N of menu "X"` — consume and ignore the owning menu.
            if consumeWord("of") { _ = consumeWord("menu"); _ = try? parsePrimary() }
            return .menu(name)
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
        "number", "integer", "point", "rect", "rectangle", "logical", "boolean",
    ]

    /// Functions readable as `the <fn> of X`, not just `fn(X)`.
    static let foundFields: [String: FoundField] = [
        "foundtext": .text, "foundchunk": .chunk, "foundline": .line, "foundfield": .field,
    ]

    static let oneArgFunctions: Set<String> = [
        "sqrt", "sin", "cos", "tan", "atan", "exp", "exp1", "exp2",
        "ln", "ln1", "log2", "abs", "trunc", "round", "average", "sum",
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
    ]
    static let backgroundWords: Set<String> = ["background", "bkgnd", "bkgd", "bg"]
    static let cardWords: Set<String> = ["card", "cd"]
    /// Object-less global properties readable as `the <name>`.
    static let readableGlobalProperties: Set<String> = ["itemdelimiter", "userlevel"]

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
        // An optional layer qualifier: `card`/`bkgnd`/`background`.
        var domain: HyperTalkObject.PartDomain = .any
        var qualified = false
        switch peekIdentifier() {
        case "card", "cd":
            // Ambiguous with the `cards` plural; only treat as a qualifier if
            // a part-kind plural follows (`card buttons`).
            if let next = peekIdentifier(1), next == "buttons" || next == "btns"
                || next == "fields" || next == "flds" {
                domain = .card; qualified = true; advance()
            }
        case "background", "bkgnd", "bg":
            domain = .background; qualified = true; advance()
        default:
            break
        }
        let noun = peekIdentifier()
        if !qualified {
            if noun == "cards" || noun == "cds" { advance(); return .cards }
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
        index = saved
        return nil
    }

    /// After a `number of <plural>` count, swallows an optional
    /// `[of|in] [this|<ordinal>] card/background [name|number]` scope — e.g.
    /// `number of cds in this bg`, `number of cds of first bg`. Contrapt counts
    /// within the current stack, so the scope is parsed and ignored; it just
    /// needs consuming so the surrounding statement parses. Restores the cursor
    /// if what follows isn't actually a card/background scope.
    private mutating func skipCountScopeIfPresent() {
        let saved = index
        guard consumeWord("of") || consumeWord("in") else { return }
        _ = consumeWord("this")
        if let w = peekIdentifier(),
           w == "first" || w == "last" || w == "middle" || w == "any" || Self.ordinals[w] != nil {
            advance()
        }
        guard consumeCardWord() || consumeBackgroundWord() else { index = saved; return }
        _ = consumeWord("id")
        if case .number = current.kind { advance() }
        else if case .string = current.kind { advance() }
    }

    /// A part reference may be scoped to a specific card/background —
    /// `bg btn 3 of cd 5`, `cd fld 2 of this card`, `bg btn X of first bg`.
    /// Contrapt's background parts are shared across cards, so the owning
    /// card/background is parsed and ignored; it only needs consuming so the
    /// surrounding `set … to …` (or property read) sees what follows. Restores
    /// the cursor if the `of …` isn't actually a card/background scope.
    private mutating func skipPartScopeIfPresent() {
        let saved = index
        guard consumeWord("of") else { return }
        _ = consumeWord("this")
        if let w = peekIdentifier(),
           w == "first" || w == "last" || w == "middle" || w == "any" || Self.ordinals[w] != nil {
            advance()
        }
        guard consumeCardWord() || consumeBackgroundWord() else { index = saved; return }
        _ = consumeWord("id")
        // An optional identifier/number/string naming the card (`of cd curCard`,
        // `of card 5`, `of bg "X"`) — but not a following statement keyword.
        if current.kind != .newline, current.kind != .endOfScript, peekIdentifier() != "to" {
            _ = try? parsePrimary()
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
            let savedSuppress = suppressBarePropertyOf
            suppressBarePropertyOf = false
            let inner = try parseExpression()
            suppressBarePropertyOf = savedSuppress
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
            // `the foundText` / `foundChunk` / `foundLine` / `foundField`.
            if let found = Self.foundFields[peekIdentifier() ?? ""], peekIdentifier(1) != "of" {
                advance()
                return .found(found)
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
            // `the sqrt of X`, `the sin of X`, etc. — one-argument functions.
            if let function = peekIdentifier(), Self.oneArgFunctions.contains(function),
               peekIdentifier(1) == "of" {
                advance() // function
                advance() // of
                return .call(function, [try parsePrimary()])
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
                    skipCountScopeIfPresent()
                    return .count(countable)
                }
                index = saved // not a count noun — let a property handle it
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
            // `the short name of X`, `the long name of X` → the `name`
            // property (Contrapt already returns the bare name).
            if let adjective = peekIdentifier(), Self.nameAdjectives.contains(adjective),
               peekIdentifier(1) == "name", peekIdentifier(2) == "of" {
                advance() // adjective
                advance() // name
                advance() // of
                return .property("name", try parseObjectExpr())
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
            let savedSuppress = suppressBarePropertyOf
            suppressBarePropertyOf = true
            // The index is an arithmetic expression (`item (x mod 12)+1 of …`)
            // — parse at the additive level so it stops before `of`/`to`/`&`.
            let start = try parseAdditive()
            let selector: ChunkSelector = consumeWord("to")
                ? .range(start, try parseAdditive())
                : .index(start)
            suppressBarePropertyOf = savedSuppress
            guard consumeWord("of") else {
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
            if word == "me" { return .property("name", .me) }
            if word == "target" { return .property("name", .target) }
            // Bare `number of cards/backgrounds/buttons/fields [scope]` — a
            // count (HyperTalk's `the` is optional). `number of this card`
            // (an ordinal property) isn't countable, so it falls through.
            if word == "number", peekIdentifier() == "of" {
                let saved = index
                advance() // of
                if let countable = parseCountable() {
                    skipCountScopeIfPresent()
                    return .count(countable)
                }
                index = saved // e.g. `number of this cd` → the ordinal property
            }
            // Bare ordinal chunk: `last char of X`, `first word of X`,
            // `middle line of X` — HyperTalk's `the` is optional.
            if !suppressBarePropertyOf, let selector = Self.ordinalSelector(word),
               let kindWord = peekIdentifier(), let kind = Self.chunkKinds[kindWord] {
                advance() // chunk kind
                guard consumeWord("of") else {
                    throw ScriptError(line: line, message: "Expected 'of' after '\(word) \(kindWord)'.")
                }
                return .chunk(kind, selector, try parsePrimary())
            }
            // Bare `<property> of <object>` — HyperTalk lets you drop the
            // leading `the`, e.g. `loc of field "x"`, `rect of card field 2`.
            // A plain variable is never legitimately followed by `of`, so
            // treating `<ident> of …` as a property access is safe.
            // `short name of X`, `long name of X` → the `name` property.
            if !suppressBarePropertyOf, Self.nameAdjectives.contains(word),
               peekIdentifier() == "name", peekIdentifier(1) == "of" {
                advance() // name
                advance() // of
                return .property("name", try parseObjectExpr())
            }
            if !suppressBarePropertyOf, peekIdentifier() == "of" {
                advance() // of
                return .property(word.lowercased(), try parseObjectExpr())
            }
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
