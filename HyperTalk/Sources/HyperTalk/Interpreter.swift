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
        // HyperCard unlocks the screen when the message chain returns to idle;
        // mirror that so a handler that locks and forgets to unlock (or defers a
        // `go` under lock) is resolved at the end of this top-level dispatch.
        defer { host.setScreenLocked(false) }
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
        // Same end-of-dispatch unlock as send() — a doMenu dispatched from the
        // app's menu strip travels this path, and a handler that locks the
        // screen and `go`es to another stack parks that go until unlock
        // (Sean's Help). Without this, the parked navigation died with the
        // dispatch's host.
        defer { host.setScreenLocked(false) }
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
        // Full precision between operations — HyperCard only formats a number
        // when it becomes TEXT (numberFormat, at `put`). Rounding to 6 decimals
        // here compounded: atan(1)*4 gave 3.141592 and sqrt(2)*sqrt(2) gave
        // 2.000001 (oracle-verified both wrong). displayString applies the
        // 0.###### format at the put boundary.
        var text = String(format: "%.15g", number)
        if text.contains("e") { text = String(format: "%.15f", number) }
        while text.contains("."), text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// HyperCard's number→text conversion (the default numberFormat
    /// "0.######"): a non-integer numeric value renders rounded to 6 decimals
    /// when put somewhere. Non-numeric text passes through untouched.
    static func displayString(_ text: String) -> String {
        // `pi` is a string CONSTANT in HyperCard — numberFormat never reformats
        // it (put pi shows all 20 digits; oracle-verified, HC 2.3).
        guard text != "3.14159265358979323846" else { return text }
        guard text.contains("."), text.first != ".", let number = Double(text) else { return text }
        if number.rounded() == number, abs(number) < 1e15 { return String(Int64(number)) }
        // Round half away from zero at the 6th decimal (0.0000005 shows as
        // 0.000001, not 0 — %.6f alone rounds it down). Oracle-verified.
        let scaled = (number * 1_000_000).rounded(.toNearestOrAwayFromZero) / 1_000_000
        var formatted = String(format: "%.6f", scaled)
        while formatted.hasSuffix("0") { formatted.removeLast() }
        if formatted.hasSuffix(".") { formatted.removeLast() }
        if formatted == "-0" { return "0" } // a negative that rounded to zero
        // HyperCard drops the zero of a negative fraction: -0.5 shows as
        // "-.5" (positives keep it: "0.5"). Oracle-verified, HC 2.3.
        if formatted.hasPrefix("-0.") { formatted = "-" + formatted.dropFirst(2) }
        return formatted
    }

    static func number(from text: String, line: Int) throws -> Double {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        // Empty counts as zero in numeric context — so uninitialized
        // globals and counters (`put counter + 1 into counter`) just work.
        if trimmed.isEmpty { return 0 }
        // HyperCard allows space between the sign and digits: "- 3" + 1 = -2
        // (oracle-verified, HC 2.3).
        if trimmed.hasPrefix("-") {
            trimmed = "-" + trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
        }
        guard let number = Double(trimmed) else {
            throw ScriptError(line: line, message: "Expected a number here, but got \"\(text)\".")
        }
        return number
    }

    static func bool(from text: String, line: Int) throws -> Bool {
        switch text.lowercased() {
        case "true": return true
        case "false": return false
        // An uninitialized global/flag is empty; classic stacks routinely test
        // one directly (`global dragonFly … if dragonFly then`) expecting the
        // unset state to be false. Treat empty as false rather than erroring, so
        // such a stack takes its default branch instead of aborting. Other
        // non-boolean values are still a genuine error.
        case "": return false
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
    /// The message path: leading target-specific layers (the clicked button or
    /// field, if any) followed by the current card's card/background/stack
    /// scripts. The trailing system layers are refreshed after each in-stack
    /// `go` (see refreshSystemLayers) so dispatch follows navigation.
    private var path: [ScriptLayer]
    /// Index of the first system (card/background/stack) layer in `path`, or nil
    /// when the host doesn't model a live current card (the path stays fixed).
    private let systemLayerStart: Int?
    /// Index where the in-use auxiliary-stack layers begin (appended after the
    /// base path). `start/stop using` rebuilds the tail from there.
    private let usingLayerStart: Int
    private var stepsRemaining: Int
    private var parsedLayers: [Int: ParsedScript] = [:]

    /// One frame per handler invocation: HyperTalk variables are local,
    /// pre-seeded with the built-in constants. Names listed in `global`
    /// read/write the host's global store instead.
    private struct Frame {
        var variables: [String: String]
        let layerIndex: Int
        /// Where this handler's message was first dispatched — `the target`.
        /// A clicked button's mouseUp targets the button (layer 0); a message
        /// sent `to <object>` targets that object's layer; a function call
        /// inherits its caller's target.
        var targetLayerIndex: Int = 0
        var globalNames: Set<String> = []
        /// The positional arguments this handler/function was called with, for
        /// `the param of N` / `the paramCount` / `the params`.
        var arguments: [String] = []
    }

    private var frames: [Frame] = []

    /// The value of the last `return`, read by `the result`.
    private var lastResult = ""

    // MARK: - Custom menus

    private func menuIndex(named name: String, in menus: [HyperTalkMenu]) -> Int? {
        menus.firstIndex { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func menuItemIndex(_ selector: MenuItemSelector, in menu: HyperTalkMenu, line: Int) async throws -> Int? {
        switch selector {
        case .expr(let expression):
            let value = try await evaluate(expression, line: line)
            if let n = Int(value) { return (1...menu.items.count).contains(n) ? n - 1 : nil }
            return menu.items.firstIndex { $0.name.caseInsensitiveCompare(value) == .orderedSame }
        case .ordinal(let ordinal):
            guard !menu.items.isEmpty else { return nil }
            switch ordinal {
            case .last: return menu.items.count - 1
            case .middle: return menu.items.count / 2
            default: return 0
            }
        }
    }

    /// Splits a `put … into menu` item list: one item per line, or commas
    /// when it's a single line (both classic forms).
    private func menuItems(from list: String, messages: String?) -> [HyperTalkMenuItem] {
        let names = list.contains("\n") ? list.components(separatedBy: "\n")
                                         : list.components(separatedBy: ",")
        let messageList = messages.map {
            $0.contains("\n") ? $0.components(separatedBy: "\n") : $0.components(separatedBy: ",")
        } ?? []
        return names.enumerated().compactMap { index, raw in
            let name = raw.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            let message = index < messageList.count ? messageList[index].trimmingCharacters(in: .whitespaces) : ""
            return HyperTalkMenuItem(name: name, menuMessage: message)
        }
    }

    /// Runs a file-I/O host call; HyperCard reports file failures via
    /// `the result` (scripts probe it) rather than aborting the handler.
    private func fileCall(_ body: () throws -> Void) {
        do { try body(); lastResult = "" }
        catch let error as HostError { lastResult = error.message }
        catch { lastResult = "\(error)" }
    }
    /// Set by a `return` statement while a handler/function body runs.
    private var pendingReturn: String?

    /// The delimiter `item` chunks split on. HyperTalk's `itemDelimiter`
    /// property — a comma by default, changeable at run time.
    private var itemDelimiter = ","
    /// The message box's current text, so `put x into message`, `put after
    /// message`, and reading `message` as a container are consistent. The host
    /// owns display; this mirrors the content for the interpreter's own reads.
    private var messageBoxText = ""

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
        "textarrows", "editbkgnd", "filter", "cantabort", "cantpeek", "usermodify",
        // Paint-tool globals the host doesn't model fall through to here
        // (setGlobalProperty tries host.setPaintSetting first).
        "filled", "centered", "linesize", "pensize", "penpattern", "pattern",
        "multiple", "multispace", "polysides", "grid", "brush",
        "textfont", "textsize", "textstyle", "textheight", "textalign",
    ]
    /// Stack properties Contrapt accepts but doesn't model — `set <these> of
    /// this stack to …` is a no-op rather than an error, so old stacks that
    /// toggle interruption/peeking or lock themselves keep running. The
    /// interruption pair (`cantAbort`/`cantPeek`) also appear as bare globals.
    private static let ignorableStackProperties: Set<String> = [
        "cantabort", "cantpeek", "cantmodify", "cantdelete", "freesize",
        "userlevel",
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
        // HyperCard's pi is a 20-digit literal constant, not a computed double
        // (oracle-verified against HyperCard 2.3).
        "pi": "3.14159265358979323846",
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

    /// The classic HyperCard Home stack sits at the bottom of every message
    /// path, providing utility handlers that other stacks lean on. The one
    /// stacks hit first is `getHomeInfo` — Home used it to seed the `userName`
    /// global from its "User Info" card. Contrapt has no Home data, so these
    /// are safe no-ops: enough that a stack depending on Home keeps running
    /// (e.g. the Manhole's openStack) instead of aborting with "Can't
    /// understand". Genuinely unknown words aren't listed here, so they still
    /// error. Extend this as more Home dependencies surface.
    static let homeLibrary = """
    on getHomeInfo
    end getHomeInfo
    """

    init(host: HyperTalkHost, path basePath: [ScriptLayer], stepsRemaining: Int) {
        self.host = host
        self.stepsRemaining = stepsRemaining
        // Locate the trailing card/background/stack layers so they can be
        // refreshed on navigation. They sit at the end of the base path; the
        // host reports how many there are for the current card. Only treat them
        // as dynamic when the tail actually matches those objects, so a mismatch
        // (or an opted-out host) leaves the path fixed.
        if let system = host.systemScriptLayers(),
           basePath.count >= system.count,
           Array(basePath.suffix(system.count)).map(\.object) == system.map(\.object) {
            self.systemLayerStart = basePath.count - system.count
        } else {
            self.systemLayerStart = nil
        }
        // Auxiliary stacks in use (via `start using`) extend the path after the
        // current stack, so their handlers/functions are reachable. The host
        // owns this session state; persisted ones are appended up front.
        self.usingLayerStart = basePath.count
        var full = basePath
        for (name, source) in host.inUseStackScripts() {
            full.append(ScriptLayer(name: "stack \"\(name)\" (in use)", source: source, object: .thisStack))
        }
        // The Home stack is always last in HyperCard's hierarchy (after any
        // `start using` stacks), so its utility handlers are the final fallback.
        full.append(ScriptLayer(name: "Home", source: Self.homeLibrary, object: .thisStack))
        self.path = full
    }

    /// Rebuilds the in-use auxiliary-stack layers (the tail after
    /// `usingLayerStart`) from the host, after `start using`/`stop using`.
    /// The Home library stays pinned to the very end.
    private func refreshUsingLayers() {
        for index in usingLayerStart..<path.count { parsedLayers[index] = nil }
        path.removeSubrange(usingLayerStart..<path.count)
        for (name, source) in host.inUseStackScripts() {
            path.append(ScriptLayer(name: "stack \"\(name)\" (in use)", source: source, object: .thisStack))
        }
        path.append(ScriptLayer(name: "Home", source: Self.homeLibrary, object: .thisStack))
    }

    /// Re-reads the current card's card/background/stack scripts into the tail
    /// of the path, so a handler that navigated now dispatches against the card
    /// it moved to. The leading part layer and every running frame's layer
    /// index are untouched (the system layers keep their positions and their
    /// `.thisCard`/`.thisBackground`/`.thisStack` identities); only the source
    /// each layer carries changes, so their parsed forms are dropped.
    private func refreshSystemLayers() {
        guard let start = systemLayerStart,
              let system = host.systemScriptLayers(),
              start + system.count <= path.count else { return }
        for (offset, layer) in system.enumerated() {
            let index = start + offset
            if path[index].source != layer.source { parsedLayers[index] = nil }
            path[index] = layer
        }
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
                // A parse error in an in-use auxiliary stack can't contribute
                // handlers, but must not break the host stack's dispatch — skip
                // that layer rather than failing the message.
                if index >= usingLayerStart { continue }
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
            // `the target` is where this message was dispatched, not where the
            // handler was found (a card handler catching a button's mouseUp
            // still targets the button).
            frames.append(Frame(variables: variables, layerIndex: index, targetLayerIndex: fromLayer, arguments: arguments))
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
                // A parse error in an in-use auxiliary stack is skipped, not
                // fatal — a library we can't fully parse contributes no
                // functions but doesn't break the caller.
                if index >= usingLayerStart { continue }
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
            // A function runs within its caller's message — `the target` stays.
            frames.append(Frame(variables: variables, layerIndex: index,
                                targetLayerIndex: frames.last?.targetLayerIndex ?? 0,
                                arguments: arguments))
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
        if isExternal(name) {
            // An XFCN. A host shim (pop-up menus, file dialogs) supplies the
            // value natively; otherwise external compiled code Contrapt can't
            // run reads as empty, so `get showList(…)` degrades to a cancel.
            if let value = try await host.callExternal(name, arguments: arguments) { return value }
            return ""
        }
        throw ScriptError(line: line, message: "Can't find a function named '\(name)'.")
    }

    /// Whether a name is external compiled code (an XCMD/XFCN): recorded from
    /// the stack's resource fork at import, or one of the externals HyperCard
    /// itself shipped (which never lived in the stack's own fork).
    private func isExternal(_ name: String) -> Bool {
        Self.hyperCardExternals.contains(name.lowercased()) || host.isExternalName(name)
    }

    /// Externals bundled inside the HyperCard application itself.
    static let hyperCardExternals: Set<String> = ["palette", "picture", "flash"]

    /// HyperCard's auto-sent system messages. These are recognized keywords, so
    /// sending one that no handler catches is a silent no-op (not "Can't
    /// understand") — a stack's `openStack` that calls `openCard`, or a script
    /// that sends `idle`/`mouseUp`, works whether or not a handler exists.
    static let systemMessages: Set<String> = [
        "openstack", "closestack", "openbackground", "closebackground",
        "opencard", "closecard", "suspendstack", "resumestack", "suspend",
        "resume", "startup", "quit", "idle",
        "newcard", "newbackground", "newstack", "newbutton", "newfield",
        "deletecard", "deletebackground", "deletestack", "deletebutton", "deletefield",
        "mouseup", "mousedown", "mousestilldown", "mouseenter", "mouseleave",
        "mousewithin", "mousedoubleclick",
        "keydown", "returnkey", "enterkey", "tabkey", "arrowkey", "functionkey",
        "controlkey", "commandkeydown",
        "openfield", "closefield", "exitfield", "returninfield", "enterinfield",
        "tabinfield", "help", "appleevent", "hidewindow", "showwindow",
        "movewindow", "sizewindow", "openpalette", "closepalette",
    ]

    /// Whether an unhandled command should be silently ignored rather than
    /// erroring — true for system messages and recorded externals.
    private func isSilentlyIgnorable(_ name: String) -> Bool {
        Self.systemMessages.contains(name.lowercased()) || isExternal(name)
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
        // In-use auxiliary stacks parse leniently (handler-by-handler), so a big
        // shared library stays usable even if some of its handlers use
        // constructs Contrapt doesn't support — HyperCard's per-handler compile.
        let parsed = index >= usingLayerStart
            ? Parser.parseLenient(path[index].source)
            : try Parser.parse(path[index].source)
        parsedLayers[index] = parsed
        return parsed
    }

    /// Names the offending layer in errors when the path has several. The
    /// always-present Home library layer doesn't count toward "several" (every
    /// path carries exactly one), so a standalone single-script run still
    /// reports a context-free error — hence `> 2`, not `> 1`.
    private func annotated(_ error: ScriptError, layerIndex: Int) -> ScriptError {
        guard path.count > 2, error.context == nil else { return error }
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
            if case .messageBox = objectExpression {
                // Setting the message box's visibility (etc.) is a no-op —
                // Contrapt doesn't model it. Evaluate the value for side
                // effects and errors, then ignore it.
                _ = try await evaluate(valueExpression, line: statement.line)
                return .normal
            }
            if case .window(let nameExpression) = objectExpression {
                // Window properties go to the host — `set the rect of card
                // window` crops the card viewport (the Hacker Crackdown's
                // resizable pages); hosts without windows no-op.
                let windowName = try await evaluate(nameExpression, line: statement.line).lowercased()
                let value = try await evaluate(valueExpression, line: statement.line)
                try host.setWindowProperty(property, window: windowName, to: value)
                return .normal
            }
            if case .menu(let nameExpression) = objectExpression {
                let name = try await evaluate(nameExpression, line: statement.line)
                let value = try await evaluate(valueExpression, line: statement.line)
                var menus = host.menuBarSnapshot()
                if let index = menuIndex(named: name, in: menus) {
                    switch property {
                    case "enabled": menus[index].enabled = (try? Value.bool(from: value, line: statement.line)) ?? true
                    case "name": menus[index].name = value
                    default: break // unmodeled menu properties stay ignored
                    }
                    host.updateMenuBar(menus)
                }
                return .normal
            }
            if case .menuItem(let selector, let menuExpression) = objectExpression {
                let name = try await evaluate(menuExpression, line: statement.line)
                let value = try await evaluate(valueExpression, line: statement.line)
                var menus = host.menuBarSnapshot()
                if let menuIdx = menuIndex(named: name, in: menus),
                   let itemIdx = try await menuItemIndex(selector, in: menus[menuIdx], line: statement.line) {
                    switch property {
                    case "enabled": menus[menuIdx].items[itemIdx].enabled = (try? Value.bool(from: value, line: statement.line)) ?? true
                    case "checkmark": menus[menuIdx].items[itemIdx].checkMark = (try? Value.bool(from: value, line: statement.line)) ?? false
                    case "menumessage", "menumsg": menus[menuIdx].items[itemIdx].menuMessage = value
                    case "name": menus[menuIdx].items[itemIdx].name = value
                    default: break
                    }
                    host.updateMenuBar(menus)
                }
                return .normal
            }
            // Stack properties Contrapt doesn't model (`set cantAbort of this
            // stack to true` in the Home stack's disallowInterruption) — a
            // no-op rather than an error, like the bare-global form. Evaluate
            // the value for side effects first.
            if Self.ignorableStackProperties.contains(property),
               case .thisStack = objectExpression {
                _ = try await evaluate(valueExpression, line: statement.line)
                return .normal
            }
            if Self.ignorableStackProperties.contains(property),
               case .stackNamed = objectExpression {
                _ = try await evaluate(valueExpression, line: statement.line)
                return .normal
            }
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

        case .setScreenLocked(let locked):
            host.setScreenLocked(locked)
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

        case .select(let target):
            try await executeSelect(target, line: statement.line)
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
                try await hostCall(line: statement.line) { try await self.host.goToCard(.id(popped), effects: effects) }
            }
            return .normal

        case .deleteChunk(let container):
            // delete <chunk> of <container> — remove chunk AND delimiter.
            guard case .chunk(let kind, let selector, let base) = container else { return .normal }
            let source = try await containerValue(base, line: statement.line)
            let updated = try await ChunkResolver.deleting(kind: kind, selector: selector, in: source, itemDelimiter: itemDelimiter) {
                Int(try Value.number(from: try await evaluate($0, line: statement.line), line: statement.line))
            }
            try await setContainer(base, to: updated, line: statement.line)
            return .normal

        case .setChunkProperty(let property, let chunk, let valueExpression):
            // `set the textStyle of line 2 of field "X" to bold` — resolve the
            // chunk to its field + character range (as the read side does) and
            // let the host split/merge style runs. A container that doesn't
            // bottom out in a field stays accepted-and-ignored.
            let value = try await evaluate(valueExpression, line: statement.line)
            guard let resolved = try await fieldAndRange(of: chunk, line: statement.line) else {
                return .normal
            }
            try hostCall(line: statement.line) {
                try host.setTextRunProperty(property, ofField: resolved.reference,
                                            domain: resolved.domain, range: resolved.range, to: value)
            }
            return .normal

        case .menuCommand(let command):
            var menus = host.menuBarSnapshot()
            switch command {
            case .createMenu(let nameExpression):
                let name = try await evaluate(nameExpression, line: statement.line)
                if menuIndex(named: name, in: menus) == nil {
                    menus.append(HyperTalkMenu(name: name))
                }
            case .deleteMenu(let nameExpression):
                let name = try await evaluate(nameExpression, line: statement.line)
                if let index = menuIndex(named: name, in: menus) { menus.remove(at: index) }
            case .deleteMenuItem(let selector, let menuExpression):
                let name = try await evaluate(menuExpression, line: statement.line)
                if let menuIdx = menuIndex(named: name, in: menus),
                   let itemIdx = try await menuItemIndex(selector, in: menus[menuIdx], line: statement.line) {
                    menus[menuIdx].items.remove(at: itemIdx)
                }
            case .putIntoMenu(let menuExpression, let itemsExpression, let mode, let messagesExpression):
                let name = try await evaluate(menuExpression, line: statement.line)
                let list = try await evaluate(itemsExpression, line: statement.line)
                let messages: String? = if let messagesExpression {
                    try await evaluate(messagesExpression, line: statement.line)
                } else { nil }
                let incoming = menuItems(from: list, messages: messages)
                let menuIdx: Int
                if let existing = menuIndex(named: name, in: menus) { menuIdx = existing }
                else { menus.append(HyperTalkMenu(name: name)); menuIdx = menus.count - 1 }
                switch mode {
                case .into: menus[menuIdx].items = incoming
                case .after: menus[menuIdx].items.append(contentsOf: incoming)
                case .before: menus[menuIdx].items.insert(contentsOf: incoming, at: 0)
                }
            case .setEnabled(let menuExpression, let selector, let enabled):
                let name = try await evaluate(menuExpression, line: statement.line)
                if let menuIdx = menuIndex(named: name, in: menus) {
                    if let selector {
                        if let itemIdx = try await menuItemIndex(selector, in: menus[menuIdx], line: statement.line) {
                            menus[menuIdx].items[itemIdx].enabled = enabled
                        }
                    } else {
                        menus[menuIdx].enabled = enabled
                    }
                }
            case .resetMenuBar:
                menus = []
            }
            host.updateMenuBar(menus)
            return .normal

        case .openFile(let pathExpression):
            let path = try await evaluate(pathExpression, line: statement.line)
            fileCall { try host.fileOpen(path) }
            return .normal

        case .closeFile(let pathExpression):
            let path = try await evaluate(pathExpression, line: statement.line)
            fileCall { try host.fileClose(path) }
            return .normal

        case .readFile(let fileExpression, let untilExpression, let countExpression):
            let path = try await evaluate(fileExpression, line: statement.line)
            var delimiter: String? = nil
            var count: Int? = nil
            if let untilExpression {
                let d = try await evaluate(untilExpression, line: statement.line)
                // `read until eof` means the rest of the file, not a literal.
                if d.lowercased() == "eof" || d.lowercased() == "end" { delimiter = nil }
                else { delimiter = String(d.prefix(1)) }
            }
            if let countExpression {
                count = Int(try Value.number(from: try await evaluate(countExpression, line: statement.line), line: statement.line))
            }
            do {
                let (text, atEOF) = try host.fileRead(path, until: delimiter, count: count)
                setVariable("it", to: text)
                lastResult = atEOF ? "eof" : ""
            } catch let error as HostError {
                setVariable("it", to: "")
                lastResult = error.message
            }
            return .normal

        case .writeFile(let valueExpression, let fileExpression, let atEOF, let atExpression):
            let text = try await evaluate(valueExpression, line: statement.line)
            let path = try await evaluate(fileExpression, line: statement.line)
            let position: FileWritePosition
            if atEOF { position = .eof }
            else if let atExpression {
                position = .offset(Int(try Value.number(from: try await evaluate(atExpression, line: statement.line), line: statement.line)))
            } else { position = .mark }
            fileCall { try host.fileWrite(path, text: text, at: position) }
            return .normal

        case .noOp:
            return .normal

        case .passMessage:
            return .passMessage

        case .sortCards(let ascending, let numeric, let keyExpression):
            let count = try hostCall(line: statement.line) { try host.count(.cards(inBackground: nil)) }
            var keyed: [(key: String, index: Int)] = []
            keyed.reserveCapacity(count)
            for index in 0..<count {
                host.setSortContext(index)
                let key = try await evaluate(keyExpression, line: statement.line)
                keyed.append((key, index))
            }
            host.setSortContext(nil)
            keyed.sort { a, b in
                let cmp = Self.sortOrdering(a.key, b.key, numeric: numeric)
                return ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            }
            try hostCall(line: statement.line) { try host.reorderCards(keyed.map(\.index)) }
            return .normal

        case .sortContainer(let items, let container, let ascending, let numeric, let keyExpression):
            let text = try await containerValue(container, line: statement.line)
            let delimiter = items ? itemDelimiter : "\n"
            // A field's trailing return ends its last line rather than adding
            // an empty one — hold it aside so it doesn't sort to the front.
            let hadTrailingReturn = !items && text.hasSuffix("\n")
            let body = hadTrailingReturn ? String(text.dropLast()) : text
            if body.isEmpty { return .normal }
            var keyed: [(key: String, element: String)] = []
            for element in body.components(separatedBy: delimiter) {
                var key = element
                if let keyExpression {
                    // `by last word of each` — the key sees the element as `each`.
                    let savedEach = variableValue("each")
                    setVariable("each", to: element)
                    key = try await evaluate(keyExpression, line: statement.line)
                    setVariable("each", to: savedEach ?? "")
                }
                keyed.append((key, element))
            }
            keyed.sort { a, b in
                let cmp = Self.sortOrdering(a.key, b.key, numeric: numeric)
                return ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            }
            let sorted = keyed.map(\.element).joined(separator: delimiter)
            try await setContainer(container, to: hadTrailingReturn ? sorted + "\n" : sorted, line: statement.line)
            return .normal

        case .setMarked(let mark, let target):
            switch target {
            case .card(let cardRef):
                let destination = try await resolveCardRef(cardRef, line: statement.line)
                try hostCall(line: statement.line) { try host.setMarked(mark, card: destination) }
            case .allCards:
                let count = try hostCall(line: statement.line) { try host.count(.cards(inBackground: nil)) }
                for index in 0..<count {
                    try hostCall(line: statement.line) { try host.setMarked(mark, card: .number(index + 1)) }
                }
            case .cardsWhere(let condition):
                // Evaluate the condition on each card (via the sort context, so
                // field/property reads resolve against that card), marking the
                // ones it holds for — `mark cards where field "X" = …`.
                let count = try hostCall(line: statement.line) { try host.count(.cards(inBackground: nil)) }
                for index in 0..<count {
                    host.setSortContext(index)
                    let matches = try Value.bool(from: try await evaluate(condition, line: statement.line), line: statement.line)
                    if matches {
                        try hostCall(line: statement.line) { try host.setMarked(mark, card: .number(index + 1)) }
                    }
                }
                host.setSortContext(nil)
            }
            return .normal

        case .startUsing(let nameExpression):
            let name = try await evaluate(nameExpression, line: statement.line)
            host.beginUsingStack(name)
            refreshUsingLayers()
            return .normal

        case .stopUsing(let nameExpression):
            let name = try await evaluate(nameExpression, line: statement.line)
            host.endUsingStack(name)
            refreshUsingLayers()
            return .normal

        case .clickAt(let hExpression, let vExpression):
            let x: Int, y: Int
            if let vExpression {
                x = Int(try Value.number(from: try await evaluate(hExpression, line: statement.line), line: statement.line))
                y = Int(try Value.number(from: try await evaluate(vExpression, line: statement.line), line: statement.line))
            } else {
                // A single `"h,v"` value (e.g. `click at loc of button "X"`).
                let point = try await evaluate(hExpression, line: statement.line)
                    .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                x = Int(Double(point.first ?? "") ?? 0)
                y = Int(Double(point.count > 1 ? point[1] : "") ?? 0)
            }
            host.click(x: x, y: y)
            return .normal

        case .drag(let fromH, let fromV, let toH, let toV):
            func point(_ h: Expr, _ v: Expr?, line: Int) async throws -> (Int, Int) {
                if let v {
                    return (Int(try Value.number(from: try await evaluate(h, line: line), line: line)),
                            Int(try Value.number(from: try await evaluate(v, line: line), line: line)))
                }
                let parts = try await evaluate(h, line: line)
                    .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                return (Int(Double(parts.first ?? "") ?? 0), Int(Double(parts.count > 1 ? parts[1] : "") ?? 0))
            }
            let from = try await point(fromH, fromV, line: statement.line)
            let to = try await point(toH, toV, line: statement.line)
            host.drag(fromX: from.0, fromY: from.1, toX: to.0, toY: to.1)
            return .normal

        case .resetPaint:
            host.resetPaint()
            return .normal

        case .typeText(let valueExpression, let withCommandKey):
            let text = try await evaluate(valueExpression, line: statement.line)
            host.typeText(text, withCommandKey: withCommandKey)
            return .normal

        case .openPrinting(let withDialog):
            host.openPrinting(withDialog: withDialog)
            return .normal

        case .closePrinting:
            host.closePrinting()
            return .normal

        case .printCards(let selection):
            host.printCards(selection)
            return .normal

        case .printField(let objectExpression):
            let object = try await resolveObject(objectExpression, line: statement.line)
            guard case .part(_, let domain, let reference, let onCard) = object else {
                throw ScriptError(line: statement.line, message: "Print expects a field.")
            }
            let text = try host.fieldText(reference, domain: domain, onCard: onCard)
            host.printText(text, title: "Field")
            return .normal

        case .play(let voiceExpression, let tempoExpression, let notesExpression):
            let voice = try await evaluate(voiceExpression, line: statement.line)
            var tempo = 120.0 // HyperCard's default beat
            if let tempoExpression {
                tempo = try Value.number(from: try await evaluate(tempoExpression, line: statement.line), line: statement.line)
            }
            var notes: [PlayNote] = []
            if let notesExpression {
                notes = PlayNotes.parse(try await evaluate(notesExpression, line: statement.line))
            }
            host.play(voice: voice, tempo: max(1, tempo), notes: notes)
            return .normal

        case .playStop:
            host.stopPlay()
            return .normal

        case .chooseTool(let name):
            host.chooseTool(name)
            return .normal

        case .doMenu(let itemExpression):
            let item = try await evaluate(itemExpression, line: statement.line)
            // Send a `doMenu` message so a handler can trap the command; if
            // none does (or it passes), perform the built-in menu action.
            let trapped = try await send("doMenu", arguments: [item], fromLayer: currentLayerIndex, line: statement.line)
            if !trapped {
                // A custom menu item with a menuMessage sends that message
                // instead of the built-in action (the `put … into menu … with
                // menuMessages …` idiom).
                for menu in host.menuBarSnapshot() {
                    if let found = menu.items.first(where: { $0.name.caseInsensitiveCompare(item) == .orderedSame }),
                       !found.menuMessage.isEmpty {
                        let (command, rawArguments) = Self.splitMessage(found.menuMessage)
                        if !command.isEmpty {
                            _ = try await send(command, arguments: rawArguments, fromLayer: currentLayerIndex, line: statement.line)
                        }
                        return .normal
                    }
                }
                try hostCall(line: statement.line) { try host.performMenu(item) }
            }
            return .normal

        case .sendMessage(let messageExpression, let objectExpression):
            let text = try await evaluate(messageExpression, line: statement.line)
                .trimmingCharacters(in: .whitespaces)
            let target = try await resolveObject(objectExpression, line: statement.line)
            let (command, rawArguments) = Self.splitMessage(text)
            guard !command.isEmpty else { return .normal }
            // Arguments inside the message string are expressions, evaluated
            // in the sender's context — `send "greet 2+3" to …` passes 5, and
            // a variable the sender holds passes its value. A bare word with
            // no value is an unquoted literal: it passes verbatim (not through
            // the parser, which would lowercase it — "Bill" stays "Bill").
            var arguments: [String] = []
            for raw in rawArguments {
                guard let expression = try? Parser.parseSoleExpression(raw) else {
                    arguments.append(raw)
                    continue
                }
                if case .variable(let name) = expression, variableValue(name) == nil {
                    arguments.append(raw)
                } else if let value = try? await evaluate(expression, line: statement.line) {
                    arguments.append(value)
                } else {
                    arguments.append(raw)
                }
            }
            let handled: Bool
            if let fromLayer = path.firstIndex(where: { $0.object == target }) {
                // The target is on the running path (this card/background/
                // stack): dispatch at its layer, falling through beneath it.
                handled = try await send(command, arguments: arguments, fromLayer: fromLayer, line: statement.line)
            } else if let layers = host.scriptLayers(for: target) {
                // An off-path object (a button, a field, another card): the
                // host supplies its full path — the object's script first,
                // then the layers beneath it. A child runtime dispatches over
                // it, sharing this one's runaway-step budget.
                let child = Runtime(host: host, path: layers, stepsRemaining: stepsRemaining)
                defer { stepsRemaining = child.stepsRemaining }
                handled = try await child.send(command, arguments: arguments, fromLayer: 0, line: statement.line)
            } else {
                // Host can't resolve the object — dispatch from here, the
                // best-effort pre-targeted behavior.
                handled = try await send(command, arguments: arguments, fromLayer: currentLayerIndex, line: statement.line)
            }
            if !handled, !isSilentlyIgnorable(command) {
                throw ScriptError(line: statement.line, message: "Can't understand '\(command)'.")
            }
            return .normal

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

        case .answerFile(let promptExpression, let typeExpression):
            // Present a file-open dialog. A chosen file lands in `it` with an
            // empty `result`; cancelling leaves `it` empty and `result` is
            // "Cancel" — HyperCard's contract, which `selectHCFile`-style
            // handlers test with `if it is empty or the result is "Cancel"`.
            let prompt = try await evaluate(promptExpression, line: statement.line)
            var type: String?
            if let typeExpression {
                type = try await evaluate(typeExpression, line: statement.line)
            }
            if let path = await host.answerFile(prompt, type: type) {
                setVariable("it", to: path)
                lastResult = ""
            } else {
                setVariable("it", to: "")
                lastResult = "Cancel"
            }
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
            case _ where host.setPaintSetting(property, to: value):
                // A modeled paint global (lineSize, pattern, filled, …) —
                // the host stored it for the next scripted stroke.
                break
            case _ where host.setEnvironmentSetting(property, to: value):
                // A modeled environment global (userLevel, textArrows, …).
                break
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
                if isSilentlyIgnorable(name) {
                    // An XCMD the import recorded (`palette`), or a HyperCard
                    // system message (`openCard`, `idle`) with no handler. A
                    // host shim may run it natively (its return is the
                    // result); otherwise recognized-but-ignored. 
                    if isExternal(name),
                       let result = try await host.callExternal(name, arguments: arguments) {
                        lastResult = result
                        return .normal
                    }
                    lastResult = ""
                    return .normal
                }
                throw ScriptError(line: statement.line, message: "Can't understand '\(name)'.")
            }
            return .normal
        }
    }

    private func executePut(_ expression: Expr, _ mode: PutMode, _ container: Container?, line: Int) async throws {
        // Numbers become text here — apply HyperCard's numberFormat (default
        // 0.######). Intermediate expression values keep full precision.
        let value = Value.displayString(try await evaluate(expression, line: line))
        guard let container else {
            messageBoxText = value
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
        case .messageBox:
            return messageBoxText
        case .selection:
            return host.selectionValue(.text)
        case .me:
            guard let field = meAsField(line: line) else {
                throw ScriptError(line: line, message: "'me' is not a field here.")
            }
            return try hostCall(line: line) { try host.fieldText(field.reference, domain: field.domain, onCard: nil) }
        case .target:
            guard let field = targetAsField(line: line) else {
                throw ScriptError(line: line, message: "The target is not a field here.")
            }
            return try hostCall(line: line) { try host.fieldText(field.reference, domain: field.domain, onCard: nil) }
        case .chunk(let kind, let selector, let base):
            let source = try await containerValue(base, line: line)
            return try await ChunkResolver.resolve(kind: kind, selector: selector, in: source, itemDelimiter: itemDelimiter) {
                Int(try Value.number(from: try await evaluate($0, line: line), line: line))
            }
        }
    }

    /// The current selection as a chunk-of-field container, parsed from the
    /// host's selection descriptor (`char X to Y of card field Z`). Nil when
    /// nothing is selected or the host doesn't track one.
    private func selectionContainer() -> Container? {
        let descriptor = host.selectionValue(.chunk)
        guard !descriptor.isEmpty else { return nil }
        return Parser.parseSoleContainer(descriptor)
    }

    /// How two sort keys rank — HyperCard's text sort is case-insensitive,
    /// and its numeric sort compares values (non-numbers rank as 0). Shared
    /// by the cards sort and the container sort.
    private static func sortOrdering(_ a: String, _ b: String, numeric: Bool) -> ComparisonResult {
        if numeric {
            let x = Double(a.trimmingCharacters(in: .whitespaces)) ?? 0
            let y = Double(b.trimmingCharacters(in: .whitespaces)) ?? 0
            return x < y ? .orderedAscending : (x > y ? .orderedDescending : .orderedSame)
        }
        return a.localizedCaseInsensitiveCompare(b)
    }

    /// The text a chunk expression addresses. A chunk of `the target` resolves
    /// against the target field's *contents* (HyperCard: `line 2 of the
    /// target`), while `the target` alone stays the object's name.
    private func chunkSource(_ expression: Expr, line: Int) async throws -> String {
        if case .property("name", .target) = expression, let field = targetAsField(line: line) {
            return try hostCall(line: line) { try host.fieldText(field.reference, domain: field.domain, onCard: nil) }
        }
        return try await evaluate(expression, line: line)
    }

    /// Writes a container's text — replacing a chunk in place when needed.
    private func setContainer(_ container: Container, to value: String, line: Int) async throws {
        switch container {
        case .variable(let name):
            setVariable(name, to: value)
        case .field(let fieldRef):
            let (reference, domain, onCard) = try await resolveFieldRef(fieldRef, line: line)
            try hostCall(line: line) { try host.setFieldText(reference, domain: domain, onCard: onCard, to: value) }
        case .messageBox:
            messageBoxText = value
            host.showMessage(value)
        case .selection:
            // Replace the selected text by writing to its field+range. No
            // selection → nothing to write (as in HyperCard).
            if let resolved = selectionContainer() {
                try await setContainer(resolved, to: value, line: line)
            }
        case .me:
            guard let field = meAsField(line: line) else {
                throw ScriptError(line: line, message: "'me' is not a field here.")
            }
            try hostCall(line: line) { try host.setFieldText(field.reference, domain: field.domain, onCard: nil, to: value) }
        case .target:
            guard let field = targetAsField(line: line) else {
                throw ScriptError(line: line, message: "The target is not a field here.")
            }
            try hostCall(line: line) { try host.setFieldText(field.reference, domain: field.domain, onCard: nil, to: value) }
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

    /// `select …` — resolve the target to a field + character range and hand
    /// it to the host. Containers that don't bottom out in a field (old
    /// stacks `select theObject` for paint tools) are a graceful no-op.
    private func executeSelect(_ target: SelectTarget, line: Int) async throws {
        switch target {
        case .empty:
            host.clearSelection()
        case .textOf(let fieldRef), .beforeText(let fieldRef), .afterText(let fieldRef):
            let (reference, domain, _) = try await resolveFieldRef(fieldRef, line: line)
            let length = try hostCall(line: line) { try host.fieldText(reference, domain: domain, onCard: nil) }.count
            let range: Range<Int> = switch target {
            case .beforeText: 0..<0
            case .afterText: length..<length
            default: 0..<length
            }
            try hostCall(line: line) {
                try host.setSelection(field: reference, domain: domain, start: range.lowerBound, end: range.upperBound)
            }
        case .chunk(let container):
            guard let resolved = try await fieldAndRange(of: container, line: line) else { return }
            try hostCall(line: line) {
                try host.setSelection(field: resolved.reference, domain: resolved.domain,
                                      start: resolved.range.lowerBound, end: resolved.range.upperBound)
            }
        case .textOfContainer(let container, let edge):
            // `select [before|after] text of <me|target|fieldVar|…>` — resolve
            // the container to its field, then select the whole text or collapse
            // to an end. Non-field containers (msg, a non-field var) no-op.
            guard let resolved = try await fieldAndRange(of: container, line: line) else { return }
            let range: Range<Int> = switch edge {
            case .before: resolved.range.lowerBound..<resolved.range.lowerBound
            case .after: resolved.range.upperBound..<resolved.range.upperBound
            case .whole: resolved.range
            }
            try hostCall(line: line) {
                try host.setSelection(field: resolved.reference, domain: resolved.domain,
                                      start: range.lowerBound, end: range.upperBound)
            }
        case .descriptor(let expression):
            // The value is a chunk descriptor (`line 2 of card field id 20`,
            // from the clickLine); re-parse and select it. Anything else —
            // including an empty value before any click — is a no-op.
            let value = try await evaluate(expression, line: line)
            guard let container = Parser.parseSoleContainer(value),
                  let resolved = try await fieldAndRange(of: container, line: line) else { return }
            try hostCall(line: line) {
                try host.setSelection(field: resolved.reference, domain: resolved.domain,
                                      start: resolved.range.lowerBound, end: resolved.range.upperBound)
            }
        }
    }

    /// Walks a (possibly nested) chunk container down to its base field and
    /// computes the chunk's absolute character range in the field's text.
    /// Nil when the base isn't a field (nothing text-selectable).
    private func fieldAndRange(of container: Container, line: Int)
        async throws -> (reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, range: Range<Int>)? {
        switch container {
        case .field(let fieldRef):
            let (reference, domain, _) = try await resolveFieldRef(fieldRef, line: line)
            let length = try hostCall(line: line) { try host.fieldText(reference, domain: domain, onCard: nil) }.count
            return (reference, domain, 0..<length)
        case .chunk(let kind, let selector, let base):
            guard let outer = try await fieldAndRange(of: base, line: line) else { return nil }
            let text = try hostCall(line: line) { try host.fieldText(outer.reference, domain: outer.domain, onCard: nil) }
            let baseText = String(Array(text)[outer.range.lowerBound..<min(outer.range.upperBound, text.count)])
            guard let inner = try await ChunkResolver.range(
                kind: kind, selector: selector, in: baseText, itemDelimiter: itemDelimiter,
                evaluateIndex: { Int(try Value.number(from: try await self.evaluate($0, line: line), line: line)) }
            ) else { return nil }
            let offset = outer.range.lowerBound
            return (outer.reference, outer.domain, (offset + inner.lowerBound)..<(offset + inner.upperBound))
        case .me:
            // `select line 2 of me` in a field's script.
            guard let field = meAsField(line: line) else { return nil }
            let length = try hostCall(line: line) { try host.fieldText(field.reference, domain: field.domain, onCard: nil) }.count
            return (field.reference, field.domain, 0..<length)
        case .target:
            // `select line 2 of the target` — the classic list-field idiom.
            guard let field = targetAsField(line: line) else { return nil }
            let length = try hostCall(line: line) { try host.fieldText(field.reference, domain: field.domain, onCard: nil) }.count
            return (field.reference, field.domain, 0..<length)
        case .variable(let name):
            // A variable may hold a descriptor ("line 2 of card field id 20",
            // stashed from the clickLine). One re-parse level, no recursion
            // into further variables.
            guard let value = variableValue(name),
                  let container = Parser.parseSoleContainer(value),
                  !isVariableContainer(container) else { return nil }
            return try await fieldAndRange(of: container, line: line)
        case .selection:
            guard let resolved = selectionContainer() else { return nil }
            return try await fieldAndRange(of: resolved, line: line)
        case .messageBox:
            return nil
        }
    }

    /// The running script's `me`, when it belongs to a field — the reference
    /// the host can read/write its contents by. Nil for any other object.
    private func meAsField(line: Int) -> (reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain)? {
        guard let object = try? layerObject(at: currentLayerIndex, keyword: "me", line: line),
              case .part(let kind, let domain, let reference, _) = object, kind == "field" else { return nil }
        return (reference, domain)
    }

    /// The current message's target, when it's a field — `the target` used as
    /// a container (or as a chunk's base) addresses that field's contents,
    /// HyperCard's list-field idiom. Nil for any other object.
    private func targetAsField(line: Int) -> (reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain)? {
        guard let object = try? layerObject(at: frames.last?.targetLayerIndex ?? 0, keyword: "the target", line: line),
              case .part(let kind, let domain, let reference, _) = object, kind == "field" else { return nil }
        return (reference, domain)
    }

    private func isVariableContainer(_ container: Container) -> Bool {
        switch container {
        case .variable: return true
        case .chunk(_, _, let base): return isVariableContainer(base)
        case .field, .messageBox, .me, .target, .selection: return false
        }
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
            var name: String?
            if let backgroundExpression { name = try await evaluate(backgroundExpression, line: line) }
            return .inBackground(inner, background: name)
        case .markedCard(let expression):
            let n = Int(try Value.number(from: try await evaluate(expression, line: line), line: line))
            return .markedCard(n)
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
        case .any:
            // A random card in the stack (`go to any card`).
            let count = try hostCall(line: line) { try host.count(.cards(inBackground: nil)) }
            return .number(count > 0 ? Int.random(in: 1...count) : 1)
        case .expression(let expression):
            let value = try await evaluate(expression, line: line)
            if let number = Int(value.trimmingCharacters(in: .whitespaces)) {
                return .number(number)
            }
            return .named(value)
        case .idExpression(let expression):
            return .id(try await evaluate(expression, line: line))
        case .current:
            // The current card, resolved to its number so any host can navigate
            // there (a `go this card` stay/refresh).
            let value = try hostCall(line: line) { try host.propertyValue("number", of: .thisCard) }
            return .number(Int(value.trimmingCharacters(in: .whitespaces)) ?? 1)
        case .home: return .home
        case .back: return .back
        case .inBackground(let base, let backgroundExpression):
            var name: String?
            if let backgroundExpression { name = try await evaluate(backgroundExpression, line: line) }
            return .inBackground(try await destination(for: base, line: line), background: name)
        case .inStack(let nameExpression, let card):
            let name = try await evaluate(nameExpression, line: line)
            var cardDestination: GoDestination?
            if let card { cardDestination = try await destination(for: card, line: line) }
            return .stack(name: name, card: cardDestination)
        case .markedCard(let expression):
            let n = Int(try Value.number(from: try await evaluate(expression, line: line), line: line))
            return .markedCard(n)
        case .relativeMarked(let forward):
            return .relativeMarked(forward: forward)
        case .markedCardOrdinal(let ordinal):
            let total = try hostCall(line: line) { try host.count(.markedCards) }
            return .markedCard(Self.resolveOrdinal(ordinal, count: total))
        }
    }

    /// Splits a `send` message string into a command name and its
    /// comma-separated arguments — `"bracketWeek 12345"` → ("bracketWeek",
    /// ["12345"]); `"extendWeekly"` → ("extendWeekly", []).
    static func splitMessage(_ text: String) -> (command: String, arguments: [String]) {
        guard let space = text.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
            return (text, [])
        }
        let command = String(text[..<space])
        let rest = text[text.index(after: space)...].trimmingCharacters(in: .whitespaces)
        if rest.isEmpty { return (command, []) }
        return (command, rest.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) })
    }

    private func executeGo(_ target: GoTarget, line: Int) async throws {
        let destination = try await destination(for: target, line: line)
        // The go consumes any queued visual effects, whether or not it succeeds.
        let effects = pendingVisualEffects
        pendingVisualEffects = []
        try await hostCall(line: line) { try await self.host.goToCard(destination, effects: effects) }
        // Same-stack navigation moves the current card, so the message path's
        // card/background/stack layers must follow. Leaving to another stack or
        // Home starts a fresh dispatch in that document, so there's nothing to
        // refresh here.
        switch destination {
        case .home, .stack:
            break
        default:
            refreshSystemLayers()
        }
    }

    private func executeRepeat(_ kind: RepeatKind, _ body: [Stmt], line: Int) async throws -> Flow {
        func runBody() async throws -> Flow? {
            try spendStep(line: line)
            let flow = try await execute(body)
            switch flow {
            case .exitRepeat: return .normal
            case .exitHandler: return .exitHandler
            case .passMessage: return .passMessage
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

        case .chunkProperty(let property, let container):
            // `the textStyle of line 2 of field "X"` — resolve the chunk to its
            // field and character range, then read the run property over it.
            guard let resolved = try await fieldAndRange(of: container, line: line) else {
                throw ScriptError(line: line, message: "Can't read \(property) of that — it isn't a field.")
            }
            return try hostCall(line: line) {
                try host.textRunProperty(property, ofField: resolved.reference,
                                         domain: resolved.domain, range: resolved.range)
            }
        case .property(let property, let objectExpression):
            if case .messageBox = objectExpression {
                // Contrapt doesn't model the message box's properties; its
                // visibility reads false (hidden until a `put` shows it).
                return property == "visible" ? "false" : ""
            }
            if case .window(let nameExpression) = objectExpression {
                // Ask the host first (`the rect of card window` on a viewport-
                // cropping host); absent windows read visible=false, else empty.
                let windowName = try await evaluate(nameExpression, line: line).lowercased()
                if let value = host.windowProperty(property, window: windowName) { return value }
                return property == "visible" ? "false" : ""
            }
            if case .menu(let nameExpression) = objectExpression {
                let name = try await evaluate(nameExpression, line: line)
                let menus = host.menuBarSnapshot()
                guard let index = menuIndex(named: name, in: menus) else {
                    return property == "visible" ? "false" : ""
                }
                let menu = menus[index]
                switch property {
                case "text", "": return menu.items.map(\.name).joined(separator: "\n")
                case "name", "short name": return menu.name
                case "enabled": return menu.enabled ? "true" : "false"
                case "visible": return "true"
                default: return ""
                }
            }
            if case .menuItem(let selector, let menuExpression) = objectExpression {
                let name = try await evaluate(menuExpression, line: line)
                let menus = host.menuBarSnapshot()
                guard let menuIdx = menuIndex(named: name, in: menus),
                      let itemIdx = try await menuItemIndex(selector, in: menus[menuIdx], line: line) else {
                    return property == "visible" ? "false" : ""
                }
                let item = menus[menuIdx].items[itemIdx]
                switch property {
                case "name", "short name", "text", "": return item.name
                case "enabled": return item.enabled ? "true" : "false"
                case "checkmark": return item.checkMark ? "true" : "false"
                case "menumessage", "menumsg": return item.menuMessage
                case "visible": return "true"
                default: return ""
                }
            }
            if case .stackNamed(let nameExpression) = objectExpression {
                // Contrapt doesn't model other stacks as property-bearing
                // objects; name properties echo the referenced name so string
                // comparisons degrade safely.
                return try await evaluate(nameExpression, line: line)
            }
            let object = try await resolveObject(objectExpression, line: line)
            return try hostCall(line: line) { try host.propertyValue(property, of: object) }

        case .count(let countable):
            return try hostCall(line: line) { String(try host.count(countable)) }

        case .cardCountInBackground(let backgroundExpression):
            // `the number of cds of bg <variable>` — resolve the background name
            // at run time (a number → by position, else by name), then count.
            let value = try await evaluate(backgroundExpression, line: line).trimmingCharacters(in: .whitespaces)
            let reference: HyperTalkObject.Reference = Int(value).map { .number($0) } ?? .named(value)
            return try hostCall(line: line) { String(try host.count(.cards(inBackground: .reference(reference)))) }

        case .chunk(let kind, let selector, let sourceExpression):
            let source = try await chunkSource(sourceExpression, line: line)
            return try await ChunkResolver.resolve(kind: kind, selector: selector, in: source, itemDelimiter: itemDelimiter) { expression in
                Int(try Value.number(from: try await evaluate(expression, line: line), line: line))
            }

        case .chunkCount(let kind, let sourceExpression):
            // The source becomes text here, so numberFormat applies — the
            // number of chars in (10/3) is 8 (oracle-verified, HC 2.3).
            let source = Value.displayString(try await chunkSource(sourceExpression, line: line))
            return String(ChunkResolver.count(kind: kind, in: source, itemDelimiter: itemDelimiter))

        case .countDynamic(let expression):
            // The noun is computed — `the number of (item i of list & "s")`
            // where the value is "cd btns". Re-parse it as a countable.
            let noun = try await evaluate(expression, line: line)
            guard let countable = Parser.parseSoleCountable(noun) else {
                throw ScriptError(line: line, message: "Can't count \"\(noun)\".")
            }
            return try hostCall(line: line) { String(try host.count(countable)) }

        case .call(let name, let argumentExpressions):
            var arguments: [String] = []
            for expression in argumentExpressions {
                arguments.append(try await evaluate(expression, line: line))
            }
            if let builtin = try await evaluateBuiltin(name, arguments, line: line) {
                return builtin
            }
            return try await callFunction(name, arguments: arguments, line: line)

        case .menuCount:
            return String(host.menuBarSnapshot().count)

        case .menuItemCount(let nameExpression):
            let name = try await evaluate(nameExpression, line: line)
            let menus = host.menuBarSnapshot()
            guard let index = menuIndex(named: name, in: menus) else { return "0" }
            return String(menus[index].items.count)

        case .result:
            return lastResult

        case .globalProperty(let property):
            switch property {
            case "itemdelimiter":
                return itemDelimiter
            case "stacks":
                // HyperCard: the open stacks' paths, one per line, frontmost
                // first. Contrapt shows one stack per window: its name. Pairs
                // with `the long name of <stack>` (`stack "<name>"`) so the
                // classic am-I-the-right-stack guard compares equal.
                return try hostCall(line: line) { try host.propertyValue("name", of: .thisStack) }
            case "mouseclick":
                // Whether a click has landed since the last read. Tick-paced
                // like `the mouse` so the wait-for-a-click poll `repeat until
                // the mouseClick` runs at HyperCard's cadence instead of
                // spinning through the step budget. Consumed on read, so it
                // reads true exactly once per click.
                await host.wait(seconds: 1.0 / 60.0)
                return host.consumeMouseClick() ? "true" : "false"
            case "mouse":
                // Reading the button state pauses a tick first, so the classic
                // press-and-hold poll `repeat until the mouse is up` runs at
                // HyperCard's cadence instead of spinning through the runaway-
                // script step budget.
                await host.wait(seconds: 1.0 / 60.0)
                return host.mouseIsDown() ? "down" : "up"
            case "sound":
                // The playing voice's name ("done" when idle). Tick-paced like
                // `the mouse`, for `repeat until the sound is done` loops.
                await host.wait(seconds: 1.0 / 60.0)
                return host.playingSoundName()
            case "optionkey", "shiftkey", "commandkey", "cmdkey", "controlkey":
                // Tick-paced like `the mouse`, so a key-polling loop (Sean's
                // nocheat `repeat … if the optionKey is up`) runs at HyperCard
                // speed instead of burning the step budget in a second.
                await host.wait(seconds: 1.0 / 60.0)
                return host.modifierKey(property)
            case "menus":
                return host.menuBarSnapshot().map(\.name).joined(separator: "\n")
            case "numberformat":
                // The default format (oracle-verified, HC 2.3). Setting it is
                // an ignorable global; the read must still answer the default.
                return "0.######"
            case "screenrect":
                // HyperCard's display rectangle. Contrapt shows one card, which
                // is effectively the screen, so report "0,0,<width>,<height>" of
                // the stack — stacks center/position against it.
                return try hostCall(line: line) {
                    let width = try host.propertyValue("width", of: .thisStack)
                    let height = try host.propertyValue("height", of: .thisStack)
                    return "0,0,\(width),\(height)"
                }
            case "mouseloc", "mouseh", "mousev":
                // The pointer's card location, live during a press — polled by
                // drag-tracking loops, so it's tick-paced like `the mouse`.
                // Hosts without pointer tracking read 0,0.
                await host.wait(seconds: 1.0 / 60.0)
                let location = host.mouseLocation() ?? (0, 0)
                switch property {
                case "mouseh": return String(location.x)
                case "mousev": return String(location.y)
                default: return "\(location.x),\(location.y)"
                }
            case "linesize", "pensize", "pattern", "penpattern", "filled", "centered", "brush", "multiple":
                if let value = host.paintSetting(property) { return value }
                throw ScriptError(line: line, message: "Can't read the '\(property)'.")
            case "userlevel", "textarrows", "powerkeys", "blindtyping":
                if let value = host.environmentSetting(property) { return value }
                throw ScriptError(line: line, message: "Can't read the '\(property)'.")
            case "tool":
                // "browse tool" etc. — the save/restore idiom (`put the tool
                // into t … choose t`... uses `choose <t>` which re-parses; the
                // common read-only guard `if the tool is "browse tool"` works).
                return host.currentToolName()
            default:
                throw ScriptError(line: line, message: "Can't read the '\(property)'.")
            }

        case .clock(let field):
            return host.clock(field)

        case .found(let field):
            return host.foundValue(field)

        case .click(let field):
            return host.clickValue(field)

        case .selected(let component):
            return host.selectionValue(component)

        case .meValue:
            // In a field's script, `me` is the field's contents (HyperCard
            // 2.x); for any other object it reads as the name, as before.
            if let field = meAsField(line: line) {
                return try hostCall(line: line) { try host.fieldText(field.reference, domain: field.domain, onCard: nil) }
            }
            let object = try layerObject(at: currentLayerIndex, keyword: "me", line: line)
            return try hostCall(line: line) { try host.propertyValue("name", of: object) }

        case .messageBoxValue:
            return messageBoxText

        case .isType(let expression, let type, let negated):
            let value = try await evaluate(expression, line: line)
            let matches: Bool
            if type == "date" {
                // `is a date` needs the host's calendar — it's a date if `convert`
                // can read it (auto-detecting the format).
                matches = (try? hostCall(line: line) { try host.convert(value, from: [], to: [.dateItems]) }) != nil
            } else {
                matches = Self.matchesType(value, type)
            }
            return (negated ? !matches : matches) ? "true" : "false"

        case .exists(let objectExpression, let negated):
            if case .menu(let nameExpression) = objectExpression {
                let name = try await evaluate(nameExpression, line: line)
                let exists = menuIndex(named: name, in: host.menuBarSnapshot()) != nil
                return (negated ? !exists : exists) ? "true" : "false"
            }
            if case .menuItem(let selector, let menuExpression) = objectExpression {
                let name = try await evaluate(menuExpression, line: line)
                let menus = host.menuBarSnapshot()
                var exists = false
                if let menuIdx = menuIndex(named: name, in: menus),
                   let _ = try await menuItemIndex(selector, in: menus[menuIdx], line: line) { exists = true }
                return (negated ? !exists : exists) ? "true" : "false"
            }
            if case .window = objectExpression {
                // Contrapt has no window objects, so `there is a window …` is
                // always false.
                return negated ? "true" : "false"
            }
            if case .stackNamed = objectExpression {
                // Contrapt doesn't resolve arbitrary stacks by existence (helper
                // stacks like "Audio Help" aren't present), so it's false.
                return negated ? "true" : "false"
            }
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
            // Integer mod truncates toward zero (-7 mod 2 = -1), but float mod
            // floors (-7.5 mod 2 = 0.5) — both oracle-verified against HC 2.3.
            if a == a.rounded(), b == b.rounded() {
                return Value.string(from: a.truncatingRemainder(dividingBy: b))
            }
            let r = a.truncatingRemainder(dividingBy: b)
            return Value.string(from: r != 0 && (r < 0) != (b < 0) ? r + b : r)
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

        // Concatenation converts numbers to text, so numberFormat applies to
        // each operand (as at `put` — oracle-verified behavior family, HC 2.3).
        case .concat:
            return Value.displayString(left) + Value.displayString(right)
        case .concatWithSpace:
            return Value.displayString(left) + " " + Value.displayString(right)

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
            // Empty is contained in nothing: `"abc" contains ""` and
            // `"" is in "abc"` are both false (oracle-verified, HC 2.3).
            // Classic Mac string matching ignores case AND diacritics —
            // "é" is in "abe" is true (oracle-verified, HC 2.3).
            return bool(!right.isEmpty && left.range(of: right, options: [.caseInsensitive, .diacriticInsensitive]) != nil)

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
            // A number becomes text here, so numberFormat applies:
            // length(1/3) is 8 ("0.333333"), oracle-verified.
            return String(Value.displayString(arguments[0]).count)
        case "random":
            guard arguments.count == 1 else {
                throw ScriptError(line: line, message: "random expects one number, like random(6).")
            }
            let n = Int(try Value.number(from: arguments[0], line: line))
            return n >= 1 ? String(Int.random(in: 1...n)) : "0"
        case "param":
            // `the param of N` / `param(N)` — the Nth argument to the current
            // handler (1-based). param(0) is the message name, which we don't
            // track, so it reads empty, as does an out-of-range index.
            let n = Int(try Value.number(from: arguments.first ?? "0", line: line))
            let args = frames.last?.arguments ?? []
            return (n >= 1 && n <= args.count) ? args[n - 1] : ""
        case "paramcount":
            return String(frames.last?.arguments.count ?? 0)
        case "params":
            // The parameters as the message would have been written, comma-
            // separated. (HyperCard prefixes the message name; we don't track
            // it, so this is just the arguments.)
            return (frames.last?.arguments ?? []).joined(separator: ",")
        case "round":
            // Banker's rounding, as in HyperCard: round(2.5)=2, round(3.5)=4
            // (oracle-verified against HyperCard 2.3).
            let x = try number(arguments, count: 1, line: line, name: "round")[0]
            return Value.string(from: x.rounded(.toNearestOrEven))
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
            guard let range = arguments[1].range(of: arguments[0], options: [.caseInsensitive, .diacriticInsensitive]) else {
                return "0"
            }
            return String(arguments[1].distance(from: arguments[1].startIndex, to: range.lowerBound) + 1)
        case "chartonum":
            guard let scalar = arguments.first?.unicodeScalars.first else { return "0" }
            // The model's \n is classic return, char 13 (see numToChar).
            if scalar == "\n" { return "13" }
            return String(scalar.value)
        case "numtochar":
            let n = Int(try Value.number(from: arguments.first ?? "", line: line))
            // Classic char 13 is the return constant — Contrapt's model
            // normalizes line endings to \n, so map it (numToChar(13) = return
            // is true, oracle-verified against HC 2.3).
            if n == 13 { return "\n" }
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

    /// Resolves a card *object* (`card N`, `card "X"`, `card id N`, an ordinal
    /// card, or a relative `next`/`prev` card) to the concrete `GoDestination`
    /// the host resolves — the same vocabulary `go` uses. A background scope is
    /// applied by the `.cardInScope` caller, not here.
    private func cardDestination(for object: ObjectExpr, line: Int) async throws -> GoDestination {
        switch object {
        case .card(let expression):
            let value = try await evaluate(expression, line: line)
            if let number = Int(value.trimmingCharacters(in: .whitespaces)) { return .number(number) }
            return .named(value)
        case .cardByID(let idExpression):
            return .id(try await evaluate(idExpression, line: line))
        case .cardByOrdinal(let ordinal):
            let total = try hostCall(line: line) { try host.count(.cards(inBackground: nil)) }
            return .number(Self.resolveOrdinal(ordinal, count: total))
        case .cardRelative(let cardRef):
            // `next card` / `prev card` as an object — a concrete card number
            // from the current one and the stack's card count (wrapping, as in
            // HyperCard).
            let count = try hostCall(line: line) { try host.count(.cards(inBackground: nil)) }
            guard count > 0 else { return .number(1) }
            let currentText = try hostCall(line: line) { try host.propertyValue("number", of: .thisCard) }
            let current = Int(currentText.trimmingCharacters(in: .whitespaces)) ?? 1
            switch cardRef {
            case .next: return .number(current % count + 1)
            case .previous: return .number((current - 2 + count) % count + 1)
            default: return .number(current)
            }
        case .thisCard:
            let value = try hostCall(line: line) { try host.propertyValue("number", of: .thisCard) }
            return .number(Int(value.trimmingCharacters(in: .whitespaces)) ?? 1)
        case .markedCard(let expression):
            let n = Int(try Value.number(from: try await evaluate(expression, line: line), line: line))
            return .markedCard(n)
        default:
            throw ScriptError(line: line, message: "Expected a card here.")
        }
    }

    private func resolveObject(_ object: ObjectExpr, line: Int) async throws -> HyperTalkObject {
        switch object {
        case .part(let kind, let domain, let nameExpression, let card):
            return .part(kind: kind, domain: domain,
                         reference: reference(from: try await evaluate(nameExpression, line: line)),
                         onCard: try await resolveCardRef(card, line: line))
        case .partByID(let kind, let domain, let idExpression, let card):
            return .part(kind: kind, domain: domain,
                         reference: .id(try await evaluate(idExpression, line: line)),
                         onCard: try await resolveCardRef(card, line: line))
        case .card, .cardByID, .cardByOrdinal, .cardRelative, .markedCard:
            // Every card object resolves to the same `GoDestination` the host
            // navigates with, so a card object and a `go` target reach the
            // same card.
            return .card(try await cardDestination(for: object, line: line))
        case .cardInScope(let base, let backgroundExpression):
            // `card "Color" of bkgnd "Content"` — the base card, scoped to a
            // background (nil = `of this bkgnd`, the current card's).
            let baseDestination = try await cardDestination(for: base, line: line)
            var backgroundName: String?
            if let backgroundExpression {
                backgroundName = try await evaluate(backgroundExpression, line: line)
            }
            return .card(.inBackground(baseDestination, background: backgroundName))
        case .thisCard: return .thisCard
        case .thisBackground: return .thisBackground
        case .thisStack: return .thisStack
        case .me:
            return try layerObject(at: currentLayerIndex, keyword: "me", line: line)
        case .target:
            // The object the current message was dispatched to — layer 0 for a
            // clicked part, the send target for `send <msg> to <object>`.
            return try layerObject(at: frames.last?.targetLayerIndex ?? 0, keyword: "the target", line: line)
        case .menu, .menuItem:
            // Menus are interpreter/host state, not message-path objects —
            // property reads/sets and existence short-circuit before this.
            throw ScriptError(line: line, message: "A menu can't be used as a message target.")
        case .messageBox:
            // Reached only if the message box is used somewhere other than a
            // property get/set (both short-circuit) — Contrapt doesn't model it.
            throw ScriptError(line: line, message: "Contrapt doesn't model the message box as an object.")
        case .window:
            // Reached only if a window is used somewhere other than a property
            // get/set or existence test (all short-circuit) — no window objects.
            throw ScriptError(line: line, message: "Contrapt doesn't have HyperCard windows.")
        case .partByOrdinal(let kind, let domain, let ordinal):
            let total = try hostCall(line: line) { try host.count(.parts(kind: kind, domain: domain)) }
            return .part(kind: kind, domain: domain, reference: .number(Self.resolveOrdinal(ordinal, count: total)), onCard: nil)
        case .indirect(let expression):
            // A container whose value names the object — re-parse it as a
            // descriptor and resolve that. Guard against a value that's itself
            // a bare word (which would parse back to `.indirect` forever).
            let descriptor = try await evaluate(expression, line: line)
            let parsed: ObjectExpr
            do {
                parsed = try Parser.parseSoleObject(descriptor)
            } catch {
                throw ScriptError(line: line, message: "Can't understand \"\(descriptor)\" as an object.")
            }
            if case .indirect = parsed {
                throw ScriptError(line: line, message: "Can't understand \"\(descriptor)\" as an object.")
            }
            return try await resolveObject(parsed, line: line)
        case .stackNamed:
            // Reached only outside exists/property (both short-circuit) — e.g.
            // `send … to stack "X"`, which Contrapt can't dispatch to.
            throw ScriptError(line: line, message: "Contrapt can't address another stack as an object here.")
        }
    }

    /// Turns a positional keyword into a 1-based index against a live count.
    /// `middle` is HyperCard's `(count + 1) div 2`; `any` is random.
    private static func resolveOrdinal(_ ordinal: Ordinal, count: Int) -> Int {
        switch ordinal {
        case .last: return max(1, count)
        case .middle: return max(1, (count + 1) / 2)
        case .any: return count > 0 ? Int.random(in: 1...count) : 1
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
        // HyperCard's numeric lexicon (oracle-verified, HC 2.3): no exponent
        // notation ("1e3" isn't a number), no leading + ("+3" isn't), but a
        // space between the sign and digits is fine ("- 3" is).
        func classicNumber(_ s: String) -> Double? {
            var t = s
            if t.hasPrefix("-") { t = "-" + t.dropFirst().trimmingCharacters(in: .whitespaces) }
            guard !t.lowercased().contains("e"), !t.contains("+") else { return nil }
            return Double(t)
        }
        switch type {
        case "number":
            return classicNumber(trimmed) != nil
        case "integer":
            guard let number = classicNumber(trimmed) else { return false }
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
        // Case- AND diacritic-insensitive, like classic Mac string compare:
        // "é" = "e" and "café" = "cafe" (oracle-verified, HC 2.3).
        return left.compare(right, options: [.caseInsensitive, .diacriticInsensitive])
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

    private func hostCall<T>(line: Int, _ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as HostError {
            throw ScriptError(line: line, message: error.message)
        }
    }
}
