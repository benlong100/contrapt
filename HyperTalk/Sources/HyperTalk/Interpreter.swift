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
    ) throws -> Bool {
        try send(handlerName, along: [ScriptLayer(name: "script", source: scriptSource)], host: host, maxSteps: maxSteps)
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
    ) throws -> Bool {
        guard !path.isEmpty else { return false }
        let runtime = Runtime(host: host, path: path, stepsRemaining: maxSteps)
        return try runtime.send(message, arguments: arguments, fromLayer: 0, line: 0)
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
    ) throws -> String? {
        let effectivePath = path.isEmpty ? [ScriptLayer(name: "message box", source: "")] : path
        let runtime = Runtime(host: host, path: effectivePath, stepsRemaining: maxSteps)
        do {
            let statements = try Parser.parseLooseStatements(line)
            try runtime.runLoose(statements)
            return nil
        } catch let statementError as ScriptError {
            // If it reads as a bare expression, evaluate it — preferring the
            // expression's own (more specific) error if evaluation fails.
            guard let expression = try? Parser.parseSoleExpression(line) else {
                throw statementError
            }
            return try runtime.evaluateLoose(expression)
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

    private static let maxMessageDepth = 64
    private static let constants: [String: String] = [
        "empty": "",
        "quote": "\"",
        "space": " ",
        "return": "\n",
        "comma": ",",
        "tab": "\t",
        "true": "true",
        "false": "false",
    ]

    enum Flow {
        case normal
        case exitRepeat
        case nextRepeat
        case exitHandler
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
    func send(_ message: String, arguments: [String], fromLayer: Int, line: Int) throws -> Bool {
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
            defer { frames.removeLast() }
            let savedReturn = pendingReturn
            pendingReturn = nil
            do {
                _ = try execute(handler.body)
            } catch let error as ScriptError {
                throw annotated(error, layerIndex: index)
            }
            lastResult = pendingReturn ?? ""
            pendingReturn = savedReturn
            return true
        }
        return false
    }

    /// Calls a user function found along the path from the current layer,
    /// returning its `return` value ("" if it returns nothing).
    func callFunction(_ name: String, arguments: [String], line: Int) throws -> String {
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
                _ = try execute(function.body)
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
    func runLoose(_ statements: [Stmt]) throws {
        frames.append(Frame(variables: Self.constants, layerIndex: 0))
        defer { frames.removeLast() }
        _ = try execute(statements)
    }

    /// Evaluates a bare expression (a message box line) in a fresh frame.
    func evaluateLoose(_ expression: Expr) throws -> String {
        frames.append(Frame(variables: Self.constants, layerIndex: 0))
        defer { frames.removeLast() }
        return try evaluate(expression, line: 1)
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

    func execute(_ statements: [Stmt]) throws -> Flow {
        for statement in statements {
            let flow = try execute(statement)
            if case .normal = flow { continue }
            return flow
        }
        return .normal
    }

    private func execute(_ statement: Stmt) throws -> Flow {
        try spendStep(line: statement.line)
        switch statement.kind {
        case .put(let expression, let mode, let container):
            try executePut(expression, mode, container, line: statement.line)
            return .normal

        case .go(let target):
            try executeGo(target, line: statement.line)
            return .normal

        case .ifThen(let condition, let thenBody, let elseBody):
            let isTrue = try Value.bool(from: try evaluate(condition, line: statement.line), line: statement.line)
            return try execute(isTrue ? thenBody : elseBody)

        case .repeatLoop(let kind, let body):
            return try executeRepeat(kind, body, line: statement.line)

        case .exitRepeat:
            return .exitRepeat

        case .nextRepeat:
            return .nextRepeat

        case .exitHandler:
            return .exitHandler

        case .declareGlobals(let names):
            if !frames.isEmpty { frames[frames.count - 1].globalNames.formUnion(names) }
            return .normal

        case .returnStatement(let expression):
            pendingReturn = try expression.map { try evaluate($0, line: statement.line) } ?? ""
            return .exitHandler

        case .beep(let countExpression):
            var count = 1
            if let countExpression {
                count = Int(try Value.number(from: try evaluate(countExpression, line: statement.line), line: statement.line))
            }
            for _ in 0..<max(0, min(count, 50)) {
                host.beep()
            }
            return .normal

        case .get(let expression):
            // `get` evaluates into the special variable `it`.
            setVariable("it", to: try evaluate(expression, line: statement.line))
            return .normal

        case .set(let property, let objectExpression, let valueExpression):
            let object = try resolveObject(objectExpression, line: statement.line)
            let value = try evaluate(valueExpression, line: statement.line)
            try hostCall(line: statement.line) { try host.setProperty(property, of: object, to: value) }
            return .normal

        case .convert(let target, let from, let to):
            let source: String
            switch target {
            case .container(let container):
                source = try containerValue(container, line: statement.line)
            case .expression(let expression):
                source = try evaluate(expression, line: statement.line)
            }
            let converted = try hostCall(line: statement.line) { try host.convert(source, from: from, to: to) }
            switch target {
            case .container(let container):
                try setContainer(container, to: converted, line: statement.line)
            case .expression:
                setVariable("it", to: converted)
            }
            return .normal

        case .setGlobalProperty(let property, let valueExpression):
            let value = try evaluate(valueExpression, line: statement.line)
            switch property {
            case "itemdelimiter":
                // HyperCard uses only the first character of the delimiter.
                itemDelimiter = value.isEmpty ? "" : String(value.first!)
            default:
                throw ScriptError(line: statement.line, message: "Can't set the '\(property)'.")
            }
            return .normal

        case .send(let name, let argumentExpressions):
            let arguments = try argumentExpressions.map { try evaluate($0, line: statement.line) }
            let handled = try send(name, arguments: arguments, fromLayer: currentLayerIndex, line: statement.line)
            guard handled else {
                throw ScriptError(line: statement.line, message: "Can't understand '\(name)'.")
            }
            return .normal
        }
    }

    private func executePut(_ expression: Expr, _ mode: PutMode, _ container: Container?, line: Int) throws {
        let value = try evaluate(expression, line: line)
        guard let container else {
            host.showMessage(value)
            return
        }
        let combined: String
        switch mode {
        case .into:
            combined = value
        case .after:
            combined = try containerValue(container, line: line) + value
        case .before:
            combined = value + (try containerValue(container, line: line))
        }
        try setContainer(container, to: combined, line: line)
    }

    /// Reads a container's text — a variable, a field, or a chunk of one.
    private func containerValue(_ container: Container, line: Int) throws -> String {
        switch container {
        case .variable(let name):
            return variableValue(name) ?? ""
        case .field(let fieldRef):
            let (reference, domain) = try resolveFieldRef(fieldRef, line: line)
            return try hostCall(line: line) { try host.fieldText(reference, domain: domain) }
        case .chunk(let kind, let selector, let base):
            let source = try containerValue(base, line: line)
            return try ChunkResolver.resolve(kind: kind, selector: selector, in: source, itemDelimiter: itemDelimiter) {
                Int(try Value.number(from: try evaluate($0, line: line), line: line))
            }
        }
    }

    /// Writes a container's text — replacing a chunk in place when needed.
    private func setContainer(_ container: Container, to value: String, line: Int) throws {
        switch container {
        case .variable(let name):
            setVariable(name, to: value)
        case .field(let fieldRef):
            let (reference, domain) = try resolveFieldRef(fieldRef, line: line)
            try hostCall(line: line) { try host.setFieldText(reference, domain: domain, to: value) }
        case .chunk(let kind, let selector, let base):
            let source = try containerValue(base, line: line)
            let updated = try ChunkResolver.replacing(kind: kind, selector: selector, in: source, with: value, itemDelimiter: itemDelimiter) {
                Int(try Value.number(from: try evaluate($0, line: line), line: line))
            }
            try setContainer(base, to: updated, line: line)
        }
    }

    private func resolveFieldRef(_ fieldRef: FieldRef, line: Int) throws -> (HyperTalkObject.Reference, HyperTalkObject.PartDomain) {
        let value = try evaluate(fieldRef.expr, line: line)
        let reference: HyperTalkObject.Reference = fieldRef.isID ? .id(value) : self.reference(from: value)
        return (reference, fieldRef.domain)
    }

    private func executeGo(_ target: GoTarget, line: Int) throws {
        let destination: GoDestination
        switch target {
        case .next: destination = .next
        case .previous: destination = .previous
        case .first: destination = .first
        case .last: destination = .last
        case .expression(let expression):
            let value = try evaluate(expression, line: line)
            if let number = Int(value.trimmingCharacters(in: .whitespaces)) {
                destination = .number(number)
            } else {
                destination = .named(value)
            }
        case .idExpression(let expression):
            destination = .id(try evaluate(expression, line: line))
        }
        try hostCall(line: line) { try host.goToCard(destination) }
    }

    private func executeRepeat(_ kind: RepeatKind, _ body: [Stmt], line: Int) throws -> Flow {
        func runBody() throws -> Flow? {
            try spendStep(line: line)
            let flow = try execute(body)
            switch flow {
            case .exitRepeat: return .normal
            case .exitHandler: return .exitHandler
            case .normal, .nextRepeat: return nil // keep looping
            }
        }

        switch kind {
        case .forever:
            while true {
                if let flow = try runBody() { return flow }
            }

        case .times(let countExpression):
            let count = Int(try Value.number(from: try evaluate(countExpression, line: line), line: line))
            for _ in 0..<max(0, count) {
                if let flow = try runBody() { return flow }
            }

        case .whileTrue(let condition):
            while try Value.bool(from: try evaluate(condition, line: line), line: line) {
                if let flow = try runBody() { return flow }
            }

        case .untilTrue(let condition):
            while try !Value.bool(from: try evaluate(condition, line: line), line: line) {
                if let flow = try runBody() { return flow }
            }

        case .counting(let variable, let fromExpression, let toExpression, let descending):
            let start = try Value.number(from: try evaluate(fromExpression, line: line), line: line)
            let end = try Value.number(from: try evaluate(toExpression, line: line), line: line)
            var counter = start
            while descending ? counter >= end : counter <= end {
                setVariable(variable, to: Value.string(from: counter))
                if let flow = try runBody() { return flow }
                counter += descending ? -1 : 1
            }
        }
        return .normal
    }

    // MARK: Expressions

    private func evaluate(_ expression: Expr, line: Int) throws -> String {
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
            let (reference, domain) = try resolveFieldRef(fieldRef, line: line)
            return try hostCall(line: line) { try host.fieldText(reference, domain: domain) }

        case .property(let property, let objectExpression):
            let object = try resolveObject(objectExpression, line: line)
            return try hostCall(line: line) { try host.propertyValue(property, of: object) }

        case .chunk(let kind, let selector, let sourceExpression):
            let source = try evaluate(sourceExpression, line: line)
            return try ChunkResolver.resolve(kind: kind, selector: selector, in: source, itemDelimiter: itemDelimiter) { expression in
                Int(try Value.number(from: try evaluate(expression, line: line), line: line))
            }

        case .chunkCount(let kind, let sourceExpression):
            let source = try evaluate(sourceExpression, line: line)
            return String(ChunkResolver.count(kind: kind, in: source, itemDelimiter: itemDelimiter))

        case .call(let name, let argumentExpressions):
            let arguments = try argumentExpressions.map { try evaluate($0, line: line) }
            if let builtin = try evaluateBuiltin(name, arguments, line: line) {
                return builtin
            }
            return try callFunction(name, arguments: arguments, line: line)

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

        case .unary(let op, let operand):
            let value = try evaluate(operand, line: line)
            switch op {
            case .minus:
                return Value.string(from: -(try Value.number(from: value, line: line)))
            case .not:
                return (try Value.bool(from: value, line: line)) ? "false" : "true"
            }

        case .binary(let op, let leftExpression, let rightExpression):
            let left = try evaluate(leftExpression, line: line)
            let right = try evaluate(rightExpression, line: line)
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
    private func evaluateBuiltin(_ name: String, _ arguments: [String], line: Int) throws -> String? {
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

    private func number(_ arguments: [String], count: Int, line: Int, name: String) throws -> [Double] {
        guard arguments.count == count else {
            throw ScriptError(line: line, message: "\(name) expects \(count) number\(count == 1 ? "" : "s").")
        }
        return try arguments.map { try Value.number(from: $0, line: line) }
    }

    private func resolveObject(_ object: ObjectExpr, line: Int) throws -> HyperTalkObject {
        switch object {
        case .part(let kind, let domain, let nameExpression):
            .part(kind: kind, domain: domain, reference: reference(from: try evaluate(nameExpression, line: line)))
        case .partByID(let kind, let domain, let idExpression):
            .part(kind: kind, domain: domain, reference: .id(try evaluate(idExpression, line: line)))
        case .card(let expression):
            .card(reference(from: try evaluate(expression, line: line)))
        case .cardByID(let idExpression):
            .card(.id(try evaluate(idExpression, line: line)))
        case .thisCard: .thisCard
        case .thisBackground: .thisBackground
        case .thisStack: .thisStack
        case .me:
            try layerObject(at: currentLayerIndex, keyword: "me", line: line)
        case .target:
            try layerObject(at: 0, keyword: "the target", line: line)
        }
    }

    /// The object a path layer belongs to, for `me` / `the target`.
    private func layerObject(at index: Int, keyword: String, line: Int) throws -> HyperTalkObject {
        guard path.indices.contains(index), let object = path[index].object else {
            throw ScriptError(line: line, message: "There is no '\(keyword)' here.")
        }
        return object
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
