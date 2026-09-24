//
//  Host.swift
//  HyperTalk
//

import Foundation

/// Where a `go` command should land.
public enum GoDestination: Equatable, Sendable {
    case next
    case previous
    case first
    case last
    case number(Int)
    case named(String)
}

/// The interpreter's only window onto the world. The app implements this;
/// scripts can do nothing the host doesn't offer (D7: the interpreter is
/// the sandbox).
public protocol HyperTalkHost: AnyObject {
    func goToCard(_ destination: GoDestination) throws
    func fieldText(named name: String) throws -> String
    func setFieldText(named name: String, to text: String) throws
    /// `put <expr>` with no destination — HyperCard's message box.
    func showMessage(_ text: String)
    /// `beep` — one system beep per call.
    func beep()
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
