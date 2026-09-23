//
//  Interpreter.swift
//  HyperTalk
//

import Foundation

/// Public entry point.
public enum HyperTalk {
    /// Parses `scriptSource` and runs the named handler, reaching the world
    /// through `host`. Returns false if the script has no such handler
    /// (the message goes unhandled). `maxSteps` is the runaway-script
    /// budget (D7): every statement and loop iteration costs one step.
    @discardableResult
    public static func run(
        handler handlerName: String,
        in scriptSource: String,
        host: HyperTalkHost,
        maxSteps: Int = 100_000
    ) throws -> Bool {
        let script = try Parser.parse(scriptSource)
        guard let handler = script.handlers[handlerName.lowercased()] else {
            return false
        }
        let runtime = Runtime(host: host, stepsRemaining: maxSteps)
        _ = try runtime.execute(handler.body)
        return true
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
        guard let number = Double(text.trimmingCharacters(in: .whitespaces)) else {
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
    private var stepsRemaining: Int
    /// Case-insensitive variable store, pre-seeded with HyperTalk constants.
    private var variables: [String: String] = [
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

    init(host: HyperTalkHost, stepsRemaining: Int) {
        self.host = host
        self.stepsRemaining = stepsRemaining
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
        }
    }

    private func executePut(_ expression: Expr, _ mode: PutMode, _ container: Container?, line: Int) throws {
        let value = try evaluate(expression, line: line)
        guard let container else {
            host.showMessage(value)
            return
        }
        let existing: String
        switch container {
        case .variable(let name):
            existing = variables[name] ?? ""
        case .field(let nameExpression):
            let fieldName = try evaluate(nameExpression, line: line)
            existing = try hostCall(line: line) { try host.fieldText(named: fieldName) }
        }

        let combined = switch mode {
        case .into: value
        case .after: existing + value
        case .before: value + existing
        }

        switch container {
        case .variable(let name):
            variables[name] = combined
        case .field(let nameExpression):
            let fieldName = try evaluate(nameExpression, line: line)
            try hostCall(line: line) { try host.setFieldText(named: fieldName, to: combined) }
        }
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
                variables[variable] = Value.string(from: counter)
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
            return variables[name] ?? name

        case .field(let nameExpression):
            let fieldName = try evaluate(nameExpression, line: line)
            return try hostCall(line: line) { try host.fieldText(named: fieldName) }

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
