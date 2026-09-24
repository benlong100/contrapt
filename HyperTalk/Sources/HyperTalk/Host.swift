//
//  Host.swift
//  HyperTalk
//

import Foundation

/// A clock reading requested by `the date` / `the time` / etc. The host
/// owns the actual clock and locale formatting, keeping the interpreter
/// pure and testable.
public enum ClockField: Sendable, Equatable {
    case shortDate, longDate, abbreviatedDate
    case shortTime, longTime
    case seconds, ticks
}

/// A date/time format for the `convert` command. `convert` reads a value
/// (in the `from` format, or auto-detected) and rewrites it in the `to`
/// format. `dateItems` is the seven comma-separated numbers year, month,
/// day, hour, minute, second, and day-of-week; `seconds` is a count from a
/// fixed epoch. Date and time components combine with `and`.
public enum ConvertFormat: Sendable, Equatable {
    case seconds
    case dateItems
    case shortDate, longDate, abbreviatedDate
    case shortTime, longTime
}

/// Where a `go` command should land.
public enum GoDestination: Equatable, Sendable {
    case next
    case previous
    case first
    case last
    case number(Int)
    case named(String)
    /// `go to card id 12` — by permanent ID.
    case id(String)
}

/// An object a script can address with `get`/`set` and `the … of …`.
public enum HyperTalkObject: Sendable, Equatable {
    /// How the script referred to the object.
    public enum Reference: Sendable, Equatable {
        /// By name: `button "OK"`.
        case named(String)
        /// By ordinal: `field 1` — position among that kind.
        case number(Int)
        /// By permanent ID: `button id 6` — stable across renames.
        case id(String)
    }

    /// Which layer a part reference searches: `card field 1`,
    /// `background field 1`, or unqualified (card first, then background).
    public enum PartDomain: Sendable, Equatable {
        case any
        case card
        case background
    }

    /// A part on the current card or its background: kind is the word the
    /// script used ("button", "field", "label", "image").
    case part(kind: String, domain: PartDomain, reference: Reference)
    case card(Reference)
    case thisCard
    case thisBackground
    case thisStack
}

/// The interpreter's only window onto the world. The app implements this;
/// scripts can do nothing the host doesn't offer (D7: the interpreter is
/// the sandbox).
public protocol HyperTalkHost: AnyObject {
    func goToCard(_ destination: GoDestination) throws
    /// Field *contents*, addressed like any part: by name, ordinal, or id,
    /// optionally restricted to the card or background layer.
    func fieldText(_ reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain) throws -> String
    func setFieldText(_ reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, to text: String) throws
    /// `put <expr>` with no destination — HyperCard's message box.
    func showMessage(_ text: String)
    /// `beep` — one system beep per call.
    func beep()
    /// `the <property> of <object>` — property names arrive lowercased;
    /// the host owns the property vocabulary and throws for unknowns.
    func propertyValue(_ property: String, of object: HyperTalkObject) throws -> String
    /// `set the <property> of <object> to <value>`.
    func setProperty(_ property: String, of object: HyperTalkObject, to value: String) throws
    /// Global variables (`global x`), which persist across handlers and
    /// across separate script runs — so the host owns their storage.
    func globalValue(_ name: String) -> String?
    func setGlobalValue(_ name: String, to value: String)
    /// `the date` / `the time` / `the seconds` / `the ticks` — the host
    /// reads the clock and formats for the current locale.
    func clock(_ field: ClockField) -> String
    /// `convert` — reinterpret `value` (parsed as `from`, or auto-detected
    /// when `from` is empty) and re-render it in the `to` format. The host
    /// owns the calendar and locale; it throws if the value can't be read.
    func convert(_ value: String, from: [ConvertFormat], to: [ConvertFormat]) throws -> String
    /// `answer <prompt> with <buttons>` — a modal choice. Returns the label
    /// of the button the user clicked. Suspends the script until then, which
    /// is why the interpreter is async.
    func answer(_ prompt: String, buttons: [String]) async -> String
    /// `ask <prompt> with <default>` — a modal text prompt. Returns the text
    /// entered, or nil if the user cancels.
    func ask(_ prompt: String, initialAnswer: String) async -> String?
}

/// Errors a host throws from its callbacks; the interpreter wraps them
/// in a `ScriptError` carrying the offending line number.
public struct HostError: Error, Sendable {
    public let message: String
    public init(_ message: String) {
        self.message = message
    }
}

/// A script failure the app can show the user, pointing at the line.
public struct ScriptError: Error, LocalizedError, Sendable, Equatable {
    public let line: Int
    public let message: String
    /// Which script raised it (e.g. `card "Card 1" script`) when the
    /// message traveled a multi-layer path; nil for standalone scripts.
    public internal(set) var context: String?

    public init(line: Int, message: String, context: String? = nil) {
        self.line = line
        self.message = message
        self.context = context
    }

    public var errorDescription: String? {
        if let context {
            "Line \(line) of the \(context): \(message)"
        } else {
            "Line \(line): \(message)"
        }
    }
}
