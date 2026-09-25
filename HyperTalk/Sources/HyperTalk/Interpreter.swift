//
//  Interpreter.swift
//  HyperTalk
//

import Foundation

/// One script along the message path, named for error reporting
/// (e.g. `button "Greet" script`, `card "Card 1" script`).
public struct ScriptLayer: Sendable, Equatable {
    public let name: String
    public let source: String
    /// The object this script belongs to — a button, field, card, etc. —
    /// so `me` and `the target` can name it. Nil for scriptless contexts
    /// like the message box.
    public let object: HyperTalkObject?

    public init(name: String, source: String, object: HyperTalkObject? = nil) {
        self.name = name
        self.source = source
        self.object = object
    }
}

/// Public entry points.
public enum HyperTalk {
    /// Convenience for a single, standalone script.
    @discardableResult
    public static func run(
        handler handlerName: String,
        in scriptSource: String,
        host: HyperTalkHost,
        maxSteps: Int = 100_000
    ) async throws -> Bool {
        try await send(handlerName, along: [ScriptLayer(name: "script", source: scriptSource)], host: host, maxSteps: maxSteps)
    }

    /// Sends a message along the HyperCard message path: the first layer
    /// whose script defines a matching handler receives it. Handlers can
    /// send further messages (unknown commands travel the path from their
    /// own layer onward), with arguments bound to handler parameters.
    /// Returns false if nothing along the path handles the message.
    /// `maxSteps` is the runaway-script budget (D7): every statement and
    /// loop iteration costs one step.
    @discardableResult
    public static func send(
        _ message: String,
        arguments: [String] = [],
        along path: [ScriptLayer],
        host: HyperTalkHost,
        maxSteps: Int = 100_000
    ) async throws -> Bool {
        guard !path.isEmpty else { return false }
        let runtime = Runtime(host: host, path: path, stepsRemaining: maxSteps)
        do {
            return try await runtime.send(message, arguments: arguments, fromLayer: 0, line: 0)
        } catch is AbortToHyperCard {
            return true // `exit to HyperCard` — the message was handled, then aborted.
        }
    }

    /// Executes one line typed into the message box, in the context of the
    /// given path. Commands run (and unknown words dispatch as messages
    /// along the path); a line that doesn't work as a statement but parses
    /// as an expression — `2 + 3`, `field "Name"` — evaluates instead, and
    /// its value is returned for display.
    @discardableResult
    public static func execute(
        messageLine line: String,
        along path: [ScriptLayer],
        host: HyperTalkHost,
        maxSteps: Int = 100_000
    ) async throws -> String? {
        let effectivePath = path.isEmpty ? [ScriptLayer(name: "message box", source: "")] : path
        let runtime = Runtime(host: host, path: effectivePath, stepsRemaining: maxSteps)
        do {
            let statements = try Parser.parseLooseStatements(line)
            try await runtime.runLoose(statements)
            return nil
        } catch is AbortToHyperCard {
            return nil // `exit to HyperCard` from a message-box line.
        } catch let statementError as ScriptError {
            // If it reads as a bare expression, evaluate it — preferring the
            // expression's own (more specific) error if evaluation fails.
            guard let expression = try? Parser.parseSoleExpression(line) else {
                throw statementError
            }
            return try await runtime.evaluateLoose(expression)
        }
    }
}

// MARK: - Values

/// HyperTalk is stringly typed: every value is a string, coerced to a
/// number or boolean where context demands.
enum Value {
    static func string(from number: Double) -> String {
        if number.rounded() == number, abs(number) < 1e15 {
            return String(Int64(number))
        }
        var text = String(format: "%.6f", number)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    static func number(from text: String, line: Int) throws -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        // Empty counts as zero in numeric context — so uninitialized
        // globals and counters (`put counter + 1 into counter`) just work.
        if trimmed.isEmpty { return 0 }
        guard let number = Double(trimmed) else {
            throw ScriptError(line: line, message: "Expected a number here, but got \"\(text)\".")
        }
        return number
    }

    static func bool(from text: String, line: Int) throws -> Bool {
        switch text.lowercased() {
        case "true": return true
        case "false": return false
        default:
            throw ScriptError(line: line, message: "Expected true or false here, but got \"\(text)\".")
        }
    }
}

/// Thrown by `exit to HyperCard` to unwind every running handler and
/// function back to the dispatch entry, where it's caught and swallowed.
struct AbortToHyperCard: Error {}

// MARK: - Runtime

final class Runtime {
    private let host: HyperTalkHost
    private let path: [ScriptLayer]
    private var stepsRemaining: Int
    private var parsedLayers: [Int: ParsedScript] = [:]

    /// One frame per handler invocation: HyperTalk variables are local,
    /// pre-seeded with the built-in constants. Names listed in `global`
    /// read/write the host's global store instead.
    private struct Frame {
        var variables: [String: String]
        let layerIndex: Int
        var globalNames: Set<String> = []
    }

    private var frames: [Frame] = []

    /// The value of the last `return`, read by `the result`.
    private var lastResult = ""
    /// Set by a `return` statement while a handler/function body runs.
    private var pendingReturn: String?

    /// The delimiter `item` chunks split on. HyperTalk's `itemDelimiter`
    /// property — a comma by default, changeable at run time.
    private var itemDelimiter = ","

    /// Effects queued by `visual effect`, played (and cleared) by the next
    /// `go`, as in HyperCard.
    private var pendingVisualEffects: [ScreenEffect] = []

    private static let maxMessageDepth = 64
    /// Global environment properties Contrapt accepts but doesn't model —
    /// `set the <these> to …` is a no-op rather than an error, so old stacks
    /// that tweak the environment during handlers keep running.
    private static let ignorableGlobalProperties: Set<String> = [
        "cursor", "lockscreen", "lockmessages", "lockrecent", "lockerrordialogs",
        "userlevel", "dragspeed", "numberformat", "powerkeys", "blindtyping",
        "textarrows", "editbkgnd", "filter", "cantabort", "cantpeek",
    ]
    private static let constants: [String: String] = [
        "empty": "",
        "quote": "\"",
        "space": " ",
        "return": "\n",
        "linefeed": "\n",
        "formfeed": "\u{0C}",
        "null": "\u{0}",
        "comma": ",",
        "colon": ":",
        "tab": "\t",
        "true": "true",
        "false": "false",
        "pi": "3.14159265358979",
        "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4",
        "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10",
    ]

    enum Flow {
        case normal
        case exitRepeat
        case nextRepeat
        case exitHandler
        /// `pass <message>` — stop this handler and let the same message
        /// continue to the next object down the path.
        case passMessage
    }

    init(host: HyperTalkHost, path: [ScriptLayer], stepsRemaining: Int) {
        self.host = host
        self.path = path
        self.stepsRemaining = stepsRemaining
    }

    // MARK: Message dispatch

    /// Walks the path from `fromLayer` looking for a handler. Scripts parse
    /// lazily — a syntax error in the stack script can't break a button
    /// whose own script handles the message.
    func send(_ message: String, arguments: [String], fromLayer: Int, line: Int) async throws -> Bool {
        let key = message.lowercased()
        for index in fromLayer..<path.count {
            let script: ParsedScript
            do {
                script = try parsedScript(at: index)
            } catch let error as ScriptError {
                throw annotated(error, layerIndex: index)
            }
            guard let handler = script.handlers[key] else { continue }
            guard frames.count < Self.maxMessageDepth else {
                throw ScriptError(line: line, message: "Too many messages within messages — is a handler calling itself?")
            }
            var variables = Self.constants
            for (offset, parameter) in handler.parameters.enumerated() {
                variables[parameter] = offset < arguments.count ? arguments[offset] : ""
            }
            frames.append(Frame(variables: variables, layerIndex: index))
            defer { frames.removeLast() } // per-iteration: popped before any continue
            let savedReturn = pendingReturn
            pendingReturn = nil
            let flow: Flow
            do {
                flow = try await execute(handler.body)
            } catch let error as ScriptError {
                throw annotated(error, layerIndex: index)
            }
            lastResult = pendingReturn ?? ""
            pendingReturn = savedReturn
            // `pass` hands the same message to the next object down the path.
            if case .passMessage = flow { continue }
            return true
        }
        return false
    }

    /// Calls a user function found along the path from the current layer,
    /// returning its `return` value ("" if it returns nothing).
    func callFunction(_ name: String, arguments: [String], line: Int) async throws -> String {
        let key = name.lowercased()
        for index in currentLayerIndex..<path.count {
            let script: ParsedScript
            do {
                script = try parsedScript(at: index)
            } catch let error as ScriptError {
                throw annotated(error, layerIndex: index)
            }
            guard let function = script.functions[key] else { continue }
            guard frames.count < Self.maxMessageDepth else {
                throw ScriptError(line: line, message: "Too many functions within functions — is a function calling itself?")
            }
            var variables = Self.constants
            for (offset, parameter) in function.parameters.enumerated() {
                variables[parameter] = offset < arguments.count ? arguments[offset] : ""
            }
            frames.append(Frame(variables: variables, layerIndex: index))
            defer { frames.removeLast() }
            let savedReturn = pendingReturn
            pendingReturn = nil
            do {
                _ = try await execute(function.body)
            } catch let error as ScriptError {
                throw annotated(error, layerIndex: index)
            }
            let value = pendingReturn ?? ""
            pendingReturn = savedReturn
            return value
        }
        throw ScriptError(line: line, message: "Can't find a function named '\(name)'.")
    }

    /// Runs loose statements (a message box line) in a fresh frame rooted
    /// at the first layer, so message sends search the whole path.
    func runLoose(_ statements: [Stmt]) async throws {
        frames.append(Frame(variables: Self.constants, layerIndex: 0))
        defer { frames.removeLast() }
        _ = try await execute(statements)
    }

    /// Evaluates a bare expression (a message box line) in a fresh frame.
    func evaluateLoose(_ expression: Expr) async throws -> String {
        frames.append(Frame(variables: Self.constants, layerIndex: 0))
        defer { frames.removeLast() }
        return try await evaluate(expression, line: 1)
    }

    private func parsedScript(at index: Int) throws -> ParsedScript {
        if let cached = parsedLayers[index] { return cached }
        let parsed = try Parser.parse(path[index].source)
        parsedLayers[index] = parsed
        return parsed
    }

    /// Names the offending layer in errors when the path has several.
    private func annotated(_ error: ScriptError, layerIndex: Int) -> ScriptError {
        guard path.count > 1, error.context == nil else { return error }
        var annotated = error
        annotated.context = path[layerIndex].name
        return annotated
    }

    // MARK: Variables

    private func variableValue(_ name: String) -> String? {
        if frames.last?.globalNames.contains(name) == true {
            return host.globalValue(name) ?? ""
        }
        return frames.last?.variables[name]
    }

    private func setVariable(_ name: String, to value: String) {
        guard !frames.isEmpty else { return }
        if frames[frames.count - 1].globalNames.contains(name) {
            host.setGlobalValue(name, to: value)
        } else {
            frames[frames.count - 1].variables[name] = value
        }
    }

    private var currentLayerIndex: Int {
        frames.last?.layerIndex ?? 0
    }

    // MARK: Statements

    func execute(_ statements: [Stmt]) async throws -> Flow {
        for statement in statements {
            let flow = try await execute(statement)
            if case .normal = flow { continue }
            return flow
        }
        return .normal
    }

    private func execute(_ statement: Stmt) async throws -> Flow {
        try spendStep(line: statement.line)
        switch statement.kind {
        case .put(let expression, let mode, let container):
            try await executePut(expression, mode, container, line: statement.line)
            return .normal

        case .go(let target):
            try await executeGo(target, line: statement.line)
            return .normal

        case .ifThen(let condition, let thenBody, let elseBody):
            let isTrue = try Value.bool(from: try await evaluate(condition, line: statement.line), line: statement.line)
            return try await execute(isTrue ? thenBody : elseBody)

        case .repeatLoop(let kind, let body):
            return try await executeRepeat(kind, body, line: statement.line)

        case .exitRepeat:
            return .exitRepeat

        case .nextRepeat:
            return .nextRepeat

        case .exitHandler:
            return .exitHandler

        case .exitToHyperCard:
            // Unwinds every running handler/function; caught at the entry.
            throw AbortToHyperCard()

        case .declareGlobals(let names):
            if !frames.isEmpty { frames[frames.count - 1].globalNames.formUnion(names) }
            return .normal

        case .returnStatement(let expression):
            if let expression {
                pendingReturn = try await evaluate(expression, line: statement.line)
            } else {
                pendingReturn = ""
            }
            return .exitHandler

        case .beep(let countExpression):
            var count = 1
            if let countExpression {
                count = Int(try Value.number(from: try await evaluate(countExpression, line: statement.line), line: statement.line))
            }
            for _ in 0..<max(0, min(count, 50)) {
                host.beep()
            }
            return .normal

        case .get(let expression):
            // `get` evaluates into the special variable `it`.
            setVariable("it", to: try await evaluate(expression, line: statement.line))
            return .normal

        case .set(let property, let objectExpression, let valueExpression):
            let object = try await resolveObject(objectExpression, line: statement.line)
            let value = try await evaluate(valueExpression, line: statement.line)
            try hostCall(line: statement.line) { try host.setProperty(property, of: object, to: value) }
            return .normal

        case .convert(let target, let from, let to):
            let source: String
            switch target {
            case .container(let container):
                source = try await containerValue(container, line: statement.line)
            case .expression(let expression):
                source = try await evaluate(expression, line: statement.line)
            }
            let converted = try hostCall(line: statement.line) { try host.convert(source, from: from, to: to) }
            switch target {
            case .container(let container):
                try await setContainer(container, to: converted, line: statement.line)
            case .expression:
                setVariable("it", to: converted)
            }
            return .normal

        case .visualEffect(let effect):
            pendingVisualEffects.append(effect)
            return .normal

        case .wait(let kind):
            switch kind {
            case .duration(let expression, let unit):
                let amount = try Value.number(from: try await evaluate(expression, line: statement.line), line: statement.line)
                let seconds = unit == .seconds ? amount : amount / 60.0
                if seconds > 0 { await host.wait(seconds: seconds) }
            case .untilTrue(let condition):
                while try !Value.bool(from: try await evaluate(condition, line: statement.line), line: statement.line) {
                    try spendStep(line: statement.line)
                    await host.wait(seconds: 1.0 / 60.0)
                }
            case .whileTrue(let condition):
                while try Value.bool(from: try await evaluate(condition, line: statement.line), line: statement.line) {
                    try spendStep(line: statement.line)
                    await host.wait(seconds: 1.0 / 60.0)
                }
            }
            return .normal

        case .find(let mode, let textExpression, let fieldRef):
            let text = try await evaluate(textExpression, line: statement.line)
            var reference: HyperTalkObject.Reference?
            var domain: HyperTalkObject.PartDomain = .any
            if let fieldRef {
                let resolved = try await resolveFieldRef(fieldRef, line: statement.line)
                reference = resolved.0
                domain = resolved.1
            }
            let found = try hostCall(line: statement.line) {
                try host.find(text, mode: mode, inField: reference, fieldDomain: domain)
            }
            // HyperCard leaves the result empty on a hit, "not found" on a miss.
            lastResult = found ? "" : "not found"
            return .normal

        case .pushCard:
            host.pushCard()
            return .normal

        case .popCard(let container):
            let popped = host.popCard()
            if let container {
                // `pop card into x` reads the card reference without going.
                try await setContainer(container, to: popped.map { "card id \($0)" } ?? "", line: statement.line)
            } else if let popped {
                let effects = pendingVisualEffects
                pendingVisualEffects = []
                try hostCall(line: statement.line) { try host.goToCard(.id(popped), effects: effects) }
            }
            return .normal

        case .noOp:
            return .normal

        case .passMessage:
            return .passMessage

        case .arithmetic(let op, let amountExpr, let container):
            let current = try Value.number(from: try await containerValue(container, line: statement.line), line: statement.line)
            let amount = try Value.number(from: try await evaluate(amountExpr, line: statement.line), line: statement.line)
            let result: Double
            switch op {
            case .add: result = current + amount
            case .subtract: result = current - amount
            case .multiply: result = current * amount
            case .divide:
                guard amount != 0 else { throw ScriptError(line: statement.line, message: "Can't divide by zero.") }
                result = current / amount
            default: result = current
            }
            try await setContainer(container, to: Value.string(from: result), line: statement.line)
            return .normal

        case .doCommand(let expression):
            let source = try await evaluate(expression, line: statement.line)
            let statements: [Stmt]
            do {
                statements = try Parser.parseLooseStatements(source)
            } catch let error as ScriptError {
                throw ScriptError(line: statement.line, message: "Can't do \"\(source)\": \(error.message)")
            }
            // Runs in the current frame, so `do` sees and sets local variables.
            return try await execute(statements)

        case .answer(let promptExpression, let buttonExpressions):
            let prompt = try await evaluate(promptExpression, line: statement.line)
            var buttons: [String] = []
            for expression in buttonExpressions {
                buttons.append(try await evaluate(expression, line: statement.line))
            }
            if buttons.isEmpty { buttons = ["OK"] }
            setVariable("it", to: await host.answer(prompt, buttons: buttons))
            return .normal

        case .ask(let promptExpression, let initialExpression):
            let prompt = try await evaluate(promptExpression, line: statement.line)
            let initial: String
            if let initialExpression {
                initial = try await evaluate(initialExpression, line: statement.line)
            } else {
                initial = ""
            }
            let answer = await host.ask(prompt, initialAnswer: initial)
            // Cancel yields empty and sets the result to "Cancel", as in HyperCard.
            setVariable("it", to: answer ?? "")
            lastResult = answer == nil ? "Cancel" : ""
            return .normal

        case .setGlobalProperty(let property, let valueExpression):
            let value = try await evaluate(valueExpression, line: statement.line)
            switch property {
            case "itemdelimiter":
                // HyperCard uses only the first character of the delimiter.
                itemDelimiter = value.isEmpty ? "" : String(value.first!)
            case _ where Self.ignorableGlobalProperties.contains(property):
                // Global environment properties Contrapt has no state for
                // (cursor, lockScreen, userLevel…). Accept silently so old
                // stacks that set them during long operations don't error.
                break
            default:
                throw ScriptError(line: statement.line, message: "Can't set the '\(property)'.")
            }
            return .normal

        case .send(let name, let argumentExpressions):
            var arguments: [String] = []
            for expression in argumentExpressions {
                arguments.append(try await evaluate(expression, line: statement.line))
            }
            let handled = try await send(name, arguments: arguments, fromLayer: currentLayerIndex, line: statement.line)
            guard handled else {
                throw ScriptError(line: statement.line, message: "Can't understand '\(name)'.")
            }
            return .normal
        }
    }

    private func executePut(_ expression: Expr, _ mode: PutMode, _ container: Container?, line: Int) async throws {
        let value = try await evaluate(expression, line: line)
        guard let container else {
            host.showMessage(value)
            return
        }
        let combined: String
        switch mode {
        case .into:
            combined = value
        case .after:
            combined = try await containerValue(container, line: line) + value
        case .before:
            combined = value + (try await containerValue(container, line: line))
        }
        try await setContainer(container, to: combined, line: line)
    }

    /// Reads a container's text — a variable, a field, or a chunk of one.
    private func containerValue(_ container: Container, line: Int) async throws -> String {
        switch container {
        case .variable(let name):
            return variableValue(name) ?? ""
        case .field(let fieldRef):
            let (reference, domain, onCard) = try await resolveFieldRef(fieldRef, line: line)
            return try hostCall(line: line) { try host.fieldText(reference, domain: domain, onCard: onCard) }
        case .chunk(let kind, let selector, let base):
            let source = try await containerValue(base, line: line)
            return try await ChunkResolver.resolve(kind: kind, selector: selector, in: source, itemDelimiter: itemDelimiter) {
                Int(try Value.number(from: try await evaluate($0, line: line), line: line))
            }
        }
    }

    /// Writes a container's text — replacing a chunk in place when needed.
    private func setContainer(_ container: Container, to value: String, line: Int) async throws {
        switch container {
        case .variable(let name):
            setVariable(name, to: value)
        case .field(let fieldRef):
            let (reference, domain, onCard) = try await resolveFieldRef(fieldRef, line: line)
            try hostCall(line: line) { try host.setFieldText(reference, domain: domain, onCard: onCard, to: value) }
        case .chunk(let kind, let selector, let base):
            let source = try await containerValue(base, line: line)
            let updated = try await ChunkResolver.replacing(kind: kind, selector: selector, in: source, with: value, itemDelimiter: itemDelimiter) {
                Int(try Value.number(from: try await evaluate($0, line: line), line: line))
            }
            try await setContainer(base, to: updated, line: line)
        }
    }

    private func resolveFieldRef(_ fieldRef: FieldRef, line: Int) async throws -> (HyperTalkObject.Reference, HyperTalkObject.PartDomain, GoDestination?) {
        let value = try await evaluate(fieldRef.expr, line: line)
        let reference: HyperTalkObject.Reference = fieldRef.isID ? .id(value) : self.reference(from: value)
        return (reference, fieldRef.domain, try await resolveCardRef(fieldRef.card, line: line))
    }

    /// Resolves a field's `of <card>` owner to a navigation destination the
    /// host can locate (nil for the current card).
    private func resolveCardRef(_ card: CardRef?, line: Int) async throws -> GoDestination? {
        guard let card else { return nil }
        switch card {
        case .current: return nil
        case .next: return .next
        case .previous: return .previous
        case .first: return .first
        case .last: return .last
        case .expression(let expression):
            let value = try await evaluate(expression, line: line)
            if let number = Int(value.trimmingCharacters(in: .whitespaces)) {
                return .number(number)
            }
            return .named(value)
        case .idExpression(let expression):
            return .id(try await evaluate(expression, line: line))
        case .inBackground(let base, let backgroundExpression):
            guard let inner = try await resolveCardRef(base, line: line) else { return nil }
            return .inBackground(inner, background: try await evaluate(backgroundExpression, line: line))
        }
    }

    /// Maps a parsed `go` target to a host destination, evaluating any
    /// name/number/background expressions.
    private func destination(for target: GoTarget, line: Int) async throws -> GoDestination {
        switch target {
        case .next: return .next
        case .previous: return .previous
        case .first: return .first
        case .last: return .last
        case .expression(let expression):
            let value = try await evaluate(expression, line: line)
            if let number = Int(value.trimmingCharacters(in: .whitespaces)) {
                return .number(number)
            }
            return .named(value)
        case .idExpression(let expression):
            return .id(try await evaluate(expression, line: line))
        case .home: return .home
        case .back: return .back
        case .inBackground(let base, let backgroundExpression):
            return .inBackground(try await destination(for: base, line: line),
                                 background: try await evaluate(backgroundExpression, line: line))
        }
    }

    private func executeGo(_ target: GoTarget, line: Int) async throws {
        let destination = try await destination(for: target, line: line)
        // The go consumes any queued visual effects, whether or not it succeeds.
        let effects = pendingVisualEffects
        pendingVisualEffects = []
        try hostCall(line: line) { try host.goToCard(destination, effects: effects) }
    }

    private func executeRepeat(_ kind: RepeatKind, _ body: [Stmt], line: Int) async throws -> Flow {
        func runBody() async throws -> Flow? {
            try spendStep(line: line)
            let flow = try await execute(body)
            switch flow {
            case .exitRepeat: return .normal
            case .exitHandler: return .exitHandler
            case .passMessage: return .passMessage // propagate out of the loop
            case .normal, .nextRepeat: return nil // keep looping
            }
        }

        switch kind {
        case .forever:
            while true {
                if let flow = try await runBody() { return flow }
            }

        case .times(let countExpression):
            let count = Int(try Value.number(from: try await evaluate(countExpression, line: line), line: line))
            for _ in 0..<max(0, count) {
                if let flow = try await runBody() { return flow }
            }

        case .whileTrue(let condition):
            while try Value.bool(from: try await evaluate(condition, line: line), line: line) {
                if let flow = try await runBody() { return flow }
            }

        case .untilTrue(let condition):
            while try !Value.bool(from: try await evaluate(condition, line: line), line: line) {
                if let flow = try await runBody() { return flow }
            }

        case .counting(let variable, let fromExpression, let toExpression, let descending):
            let start = try Value.number(from: try await evaluate(fromExpression, line: line), line: line)
            let end = try Value.number(from: try await evaluate(toExpression, line: line), line: line)
            var counter = start
            while descending ? counter >= end : counter <= end {
                setVariable(variable, to: Value.string(from: counter))
                if let flow = try await runBody() { return flow }
                counter += descending ? -1 : 1
            }
        }
        return .normal
    }

    // MARK: Expressions

    private func evaluate(_ expression: Expr, line: Int) async throws -> String {
        switch expression {
        case .stringLiteral(let text):
            return text

        case .numberLiteral(let number):
            return Value.string(from: number)

        case .variable(let name):
            // An unassigned variable evaluates to its own name — HyperTalk's
            // unquoted literal behavior.
            return variableValue(name) ?? name

        case .field(let fieldRef):
            let (reference, domain, onCard) = try await resolveFieldRef(fieldRef, line: line)
            return try hostCall(line: line) { try host.fieldText(reference, domain: domain, onCard: onCard) }

        case .property(let property, let objectExpression):
            let object = try await resolveObject(objectExpression, line: line)
            return try hostCall(line: line) { try host.propertyValue(property, of: object) }

        case .count(let countable):
            return try hostCall(line: line) { String(try host.count(countable)) }

        case .chunk(let kind, let selector, let sourceExpression):
            let source = try await evaluate(sourceExpression, line: line)
            return try await ChunkResolver.resolve(kind: kind, selector: selector, in: source, itemDelimiter: itemDelimiter) { expression in
                Int(try Value.number(from: try await evaluate(expression, line: line), line: line))
            }

        case .chunkCount(let kind, let sourceExpression):
            let source = try await evaluate(sourceExpression, line: line)
            return String(ChunkResolver.count(kind: kind, in: source, itemDelimiter: itemDelimiter))

        case .call(let name, let argumentExpressions):
            var arguments: [String] = []
            for expression in argumentExpressions {
                arguments.append(try await evaluate(expression, line: line))
            }
            if let builtin = try await evaluateBuiltin(name, arguments, line: line) {
                return builtin
            }
            return try await callFunction(name, arguments: arguments, line: line)

        case .result:
            return lastResult

        case .globalProperty(let property):
            switch property {
            case "itemdelimiter":
                return itemDelimiter
            default:
                throw ScriptError(line: line, message: "Can't read the '\(property)'.")
            }

        case .clock(let field):
            return host.clock(field)

        case .found(let field):
            return host.foundValue(field)

        case .isType(let expression, let type, let negated):
            let matches = Self.matchesType(try await evaluate(expression, line: line), type)
            return (negated ? !matches : matches) ? "true" : "false"

        case .exists(let objectExpression, let negated):
            let object = try await resolveObject(objectExpression, line: line)
            let present = host.exists(object)
            return (negated ? !present : present) ? "true" : "false"

        case .unary(let op, let operand):
            let value = try await evaluate(operand, line: line)
            switch op {
            case .minus:
                return Value.string(from: -(try Value.number(from: value, line: line)))
            case .not:
                return (try Value.bool(from: value, line: line)) ? "false" : "true"
            }

        case .binary(let op, let leftExpression, let rightExpression):
            let left = try await evaluate(leftExpression, line: line)
            let right = try await evaluate(rightExpression, line: line)
            return try evaluateBinary(op, left, right, line: line)
        }
    }

    private func evaluateBinary(_ op: BinaryOp, _ left: String, _ right: String, line: Int) throws -> String {
        func numbers() throws -> (Double, Double) {
            (try Value.number(from: left, line: line), try Value.number(from: right, line: line))
        }
        func bools() throws -> (Bool, Bool) {
            (try Value.bool(from: left, line: line), try Value.bool(from: right, line: line))
        }
        func bool(_ result: Bool) -> String { result ? "true" : "false" }

        switch op {
        case .add:
            let (a, b) = try numbers(); return Value.string(from: a + b)
        case .subtract:
            let (a, b) = try numbers(); return Value.string(from: a - b)
        case .multiply:
            let (a, b) = try numbers(); return Value.string(from: a * b)
        case .divide:
            let (a, b) = try numbers()
            guard b != 0 else { throw ScriptError(line: line, message: "Can't divide by zero.") }
            return Value.string(from: a / b)
        case .intDivide:
            let (a, b) = try numbers()
            guard b != 0 else { throw ScriptError(line: line, message: "Can't divide by zero.") }
            return Value.string(from: (a / b).rounded(.towardZero))
        case .modulo:
            let (a, b) = try numbers()
            guard b != 0 else { throw ScriptError(line: line, message: "Can't divide by zero.") }
            return Value.string(from: a.truncatingRemainder(dividingBy: b))
        case .power:
            let (a, b) = try numbers(); return Value.string(from: pow(a, b))
        case .within:
            guard let point = Self.numberList(left), point.count == 2,
                  let rect = Self.numberList(right), rect.count == 4 else {
                throw ScriptError(line: line, message: "'is within' needs a point (h,v) and a rectangle (left,top,right,bottom).")
            }
            // QuickDraw's PtInRect: inclusive of left/top, exclusive of right/bottom.
            let (h, v) = (point[0], point[1])
            return bool(h >= rect[0] && h < rect[2] && v >= rect[1] && v < rect[3])

        case .concat:
            return left + right
        case .concatWithSpace:
            return left + " " + right

        case .equal:
            return bool(compare(left, right) == .orderedSame)
        case .notEqual:
            return bool(compare(left, right) != .orderedSame)
        case .less:
            return bool(compare(left, right) == .orderedAscending)
        case .greater:
            return bool(compare(left, right) == .orderedDescending)
        case .lessOrEqual:
            return bool(compare(left, right) != .orderedDescending)
        case .greaterOrEqual:
            return bool(compare(left, right) != .orderedAscending)

        case .contains:
            return bool(left.range(of: right, options: .caseInsensitive) != nil || right.isEmpty)

        case .and:
            let (a, b) = try bools(); return bool(a && b)
        case .or:
            let (a, b) = try bools(); return bool(a || b)
        }
    }

    /// Built-in functions callable with parens. Returns nil if `name` isn't
    /// a built-in (so a user function is tried instead).
    private func evaluateBuiltin(_ name: String, _ arguments: [String], line: Int) async throws -> String? {
        switch name.lowercased() {
        case "length":
            guard arguments.count == 1 else {
                throw ScriptError(line: line, message: "length expects one value, like length(field \"Name\").")
            }
            return String(arguments[0].count)
        case "random":
            guard arguments.count == 1 else {
                throw ScriptError(line: line, message: "random expects one number, like random(6).")
            }
            let n = Int(try Value.number(from: arguments[0], line: line))
            return n >= 1 ? String(Int.random(in: 1...n)) : "0"
        case "round":
            let x = try number(arguments, count: 1, line: line, name: "round")[0]
            return Value.string(from: x.rounded(.toNearestOrAwayFromZero))
        case "trunc":
            let x = try number(arguments, count: 1, line: line, name: "trunc")[0]
            return Value.string(from: x.rounded(.towardZero))
        case "abs":
            let x = try number(arguments, count: 1, line: line, name: "abs")[0]
            return Value.string(from: Swift.abs(x))
        case "min":
            let xs = try numbers(arguments, line: line, name: "min")
            return Value.string(from: xs.min() ?? 0)
        case "max":
            let xs = try numbers(arguments, line: line, name: "max")
            return Value.string(from: xs.max() ?? 0)
        case "sum":
            return Value.string(from: try statisticalValues(arguments, line: line).reduce(0, +))
        case "average", "avg":
            let xs = try statisticalValues(arguments, line: line)
            return Value.string(from: xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count))
        case "offset":
            guard arguments.count == 2 else {
                throw ScriptError(line: line, message: "offset expects two values, like offset(\"lo\", \"hello\").")
            }
            // 1-based position of the first argument in the second, 0 if
            // absent; case-insensitive, as in HyperCard.
            if arguments[0].isEmpty { return "0" }
            guard let range = arguments[1].range(of: arguments[0], options: .caseInsensitive) else {
                return "0"
            }
            return String(arguments[1].distance(from: arguments[1].startIndex, to: range.lowerBound) + 1)
        case "chartonum":
            guard let scalar = arguments.first?.unicodeScalars.first else { return "0" }
            return String(scalar.value)
        case "numtochar":
            let n = Int(try Value.number(from: arguments.first ?? "", line: line))
            guard let scalar = Unicode.Scalar(UInt32(max(0, n))) else { return "" }
            return String(Character(scalar))
        case "sqrt":
            return Value.string(from: try number(arguments, count: 1, line: line, name: "sqrt")[0].squareRoot())
        case "sin":
            return Value.string(from: sin(try number(arguments, count: 1, line: line, name: "sin")[0]))
        case "cos":
            return Value.string(from: cos(try number(arguments, count: 1, line: line, name: "cos")[0]))
        case "tan":
            return Value.string(from: tan(try number(arguments, count: 1, line: line, name: "tan")[0]))
        case "atan":
            return Value.string(from: atan(try number(arguments, count: 1, line: line, name: "atan")[0]))
        case "exp":
            return Value.string(from: exp(try number(arguments, count: 1, line: line, name: "exp")[0]))
        case "exp1":
            return Value.string(from: expm1(try number(arguments, count: 1, line: line, name: "exp1")[0]))
        case "exp2":
            return Value.string(from: exp2(try number(arguments, count: 1, line: line, name: "exp2")[0]))
        case "ln":
            return Value.string(from: log(try number(arguments, count: 1, line: line, name: "ln")[0]))
        case "ln1":
            return Value.string(from: log1p(try number(arguments, count: 1, line: line, name: "ln1")[0]))
        case "log2":
            return Value.string(from: log2(try number(arguments, count: 1, line: line, name: "log2")[0]))
        case "annuity":
            // (1 - (1 + rate)^-periods) / rate — present value of an annuity.
            let a = try number(arguments, count: 2, line: line, name: "annuity")
            let (rate, periods) = (a[0], a[1])
            return Value.string(from: rate == 0 ? periods : (1 - pow(1 + rate, -periods)) / rate)
        case "compound":
            // (1 + rate)^periods — compound growth of a principal.
            let a = try number(arguments, count: 2, line: line, name: "compound")
            return Value.string(from: pow(1 + a[0], a[1]))
        case "value":
            guard arguments.count == 1 else {
                throw ScriptError(line: line, message: "value expects one string, like value(\"2 + 3\").")
            }
            let expression: Expr
            do {
                expression = try Parser.parseSoleExpression(arguments[0])
            } catch {
                // A string that isn't an expression evaluates to itself.
                return arguments[0]
            }
            return try await evaluate(expression, line: line)
        default:
            return nil
        }
    }

    private func numbers(_ arguments: [String], line: Int, name: String) throws -> [Double] {
        guard !arguments.isEmpty else {
            throw ScriptError(line: line, message: "\(name) expects at least one number.")
        }
        return try arguments.map { try Value.number(from: $0, line: line) }
    }

    /// Flattens `sum`/`average` arguments into numbers, so both `sum(1,2,3)`
    /// and `sum(field "list")` (one comma/space/line-separated value) work.
    private func statisticalValues(_ arguments: [String], line: Int) throws -> [Double] {
        var values: [Double] = []
        for argument in arguments {
            let tokens = argument.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" || $0 == "\t" })
            for token in tokens {
                values.append(try Value.number(from: String(token), line: line))
            }
        }
        return values
    }

    private func number(_ arguments: [String], count: Int, line: Int, name: String) throws -> [Double] {
        guard arguments.count == count else {
            throw ScriptError(line: line, message: "\(name) expects \(count) number\(count == 1 ? "" : "s").")
        }
        return try arguments.map { try Value.number(from: $0, line: line) }
    }

    private func resolveObject(_ object: ObjectExpr, line: Int) async throws -> HyperTalkObject {
        switch object {
        case .part(let kind, let domain, let nameExpression):
            return .part(kind: kind, domain: domain, reference: reference(from: try await evaluate(nameExpression, line: line)))
        case .partByID(let kind, let domain, let idExpression):
            return .part(kind: kind, domain: domain, reference: .id(try await evaluate(idExpression, line: line)))
        case .card(let expression):
            return .card(reference(from: try await evaluate(expression, line: line)))
        case .cardByID(let idExpression):
            return .card(.id(try await evaluate(idExpression, line: line)))
        case .thisCard: return .thisCard
        case .thisBackground: return .thisBackground
        case .thisStack: return .thisStack
        case .me:
            return try layerObject(at: currentLayerIndex, keyword: "me", line: line)
        case .target:
            return try layerObject(at: 0, keyword: "the target", line: line)
        }
    }

    /// The object a path layer belongs to, for `me` / `the target`.
    private func layerObject(at index: Int, keyword: String, line: Int) throws -> HyperTalkObject {
        guard path.indices.contains(index), let object = path[index].object else {
            throw ScriptError(line: line, message: "There is no '\(keyword)' here.")
        }
        return object
    }

    /// Whether `value` reads as the given `is a …` type. Purely textual —
    /// `date` isn't handled here (it would need the host's calendar).
    private static func matchesType(_ value: String, _ type: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        switch type {
        case "number":
            return Double(trimmed) != nil
        case "integer":
            guard let number = Double(trimmed) else { return false }
            return number.rounded() == number
        case "logical", "boolean":
            let lowercased = trimmed.lowercased()
            return lowercased == "true" || lowercased == "false"
        case "point":
            return isNumberList(trimmed, count: 2)
        case "rect", "rectangle":
            return isNumberList(trimmed, count: 4)
        default:
            return false
        }
    }

    /// True when `value` is exactly `count` comma-separated numbers.
    private static func isNumberList(_ value: String, count: Int) -> Bool {
        numberList(value)?.count == count
    }

    /// The comma-separated numbers in `value`, or nil if any component isn't
    /// a number (so "10,20" → [10, 20], "10,x" → nil).
    private static func numberList(_ value: String) -> [Double]? {
        let parts = value.split(separator: ",", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return numbers.count == parts.count ? numbers : nil
    }

    /// A numeric value is an ordinal (`field 1`); anything else is a name.
    /// Parts whose names are digits remain reachable by `id`.
    private func reference(from value: String) -> HyperTalkObject.Reference {
        if let number = Int(value.trimmingCharacters(in: .whitespaces)) {
            return .number(number)
        }
        return .named(value)
    }

    /// Numeric comparison when both sides are numbers, case-insensitive
    /// text comparison otherwise — authentic HyperTalk semantics.
    private func compare(_ left: String, _ right: String) -> ComparisonResult {
        if let a = Double(left.trimmingCharacters(in: .whitespaces)),
           let b = Double(right.trimmingCharacters(in: .whitespaces)) {
            if a < b { return .orderedAscending }
            if a > b { return .orderedDescending }
            return .orderedSame
        }
        return left.compare(right, options: .caseInsensitive)
    }

    // MARK: Budget and host bridging

    private func spendStep(line: Int) throws {
        stepsRemaining -= 1
        if stepsRemaining < 0 {
            throw ScriptError(line: line, message: "The script ran too long and was stopped (is there an endless repeat?).")
        }
    }

    @discardableResult
    private func hostCall<T>(line: Int, _ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as HostError {
            throw ScriptError(line: line, message: error.message)
        }
    }
}
