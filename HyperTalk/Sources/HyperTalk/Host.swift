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

/// A screen transition queued by `visual effect`, played by the next `go`.
/// The interpreter parses it; the host (the UI) renders it.
public struct ScreenEffect: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        case dissolve, wipe, scroll, zoom, iris
        case barnDoor, checkerboard, venetianBlinds, plain
    }
    /// Where the effect moves or how it opens: `wipe left`, `iris open`, etc.
    public enum Direction: String, Sendable, Codable {
        case left, right, up, down, open, close, `in`, out
    }
    public enum Speed: String, Sendable, Codable {
        case verySlow, slow, normal, fast, veryFast
    }

    public let kind: Kind
    public let direction: Direction?
    public let speed: Speed

    public init(kind: Kind, direction: Direction? = nil, speed: Speed = .normal) {
        self.kind = kind
        self.direction = direction
        self.speed = speed
    }
}

/// How `find` matches text. The default is word-prefix: each search word
/// must begin a word somewhere in a searchable field. The variants narrow
/// or widen that.
public enum FindMode: String, Sendable, Equatable {
    /// `find "ab cd"` — every search word begins a word (any order).
    case wordPrefix
    /// `find word "ab"` — the text as one or more whole words.
    case wholeWord
    /// `find chars "ab"` — the text as a substring, anywhere.
    case chars
    /// `find whole "ab cd"` — the phrase, its words whole and in order.
    case wholePhrase
    /// `find string "ab cd"` — the phrase as a substring.
    case string
}

/// After a `find`, where the match landed — read by `the foundText`,
/// `the foundChunk`, `the foundLine`, and `the foundField`.
public enum FoundField: Sendable, Equatable {
    case text, chunk, line, field
}

/// Where the last click on a locked field landed — read by `the clickLine`
/// (a descriptor like `line 3 of card field id 12`, so `the value of the
/// clickLine` reads that line and `word 2 of the clickLine` is the line
/// number) and `the clickText` (the word under the click). HyperCard 2.2's
/// list-field navigation idiom. Empty before any such click.
public enum ClickField: Sendable, Equatable {
    case line, text
}

/// What the `selected*` readers ask about the script selection (set by the
/// `select` command): `the selectedLine` (a descriptor like `line 2 of card
/// field id 12`, or `line 2 to 3 of …` for a span), `the selectedText` (the
/// selected characters), `the selectedChunk` (`char 4 to 9 of card field id
/// 12`), and `the selectedField` (`card field id 12`). All empty when nothing
/// is selected; the selection clears on navigation, as in HyperCard.
public enum SelectionComponent: Sendable, Equatable {
    case line, text, chunk, field
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
    /// `go home` — open the Home stack (cross-stack navigation).
    case home
    /// `go back` — return to the previously viewed card (browser history).
    case back
    /// A card scoped to a background: `first/last/Nth card of background X`.
    /// `which` is `.first`, `.last`, or `.number(n)` within that background.
    indirect case inBackground(GoDestination, background: String)
    /// Another stack by name, with an optional card destination within it
    /// (nil = its first card): `go stack "X"`, `go card N of stack "X"`.
    indirect case stack(name: String, card: GoDestination?)
}

/// What `the number of …` counts.
public enum Countable: Sendable, Equatable {
    /// `the number of cards`, optionally scoped to one background:
    /// `the number of cds in this bg`, `… of bg "Paths"`, `… of bg 2`.
    /// Nil scope counts the whole stack. This is how multi-background
    /// stacks (like Home) loop over just their own section's cards.
    case cards(inBackground: BackgroundScope?)
    case backgrounds
    /// `the number of [card|background] buttons/fields`. Kind is
    /// "button"/"field"; `.any` counts both the card and background layers.
    case parts(kind: String, domain: HyperTalkObject.PartDomain)

    /// Which background a scoped card count means.
    public enum BackgroundScope: Sendable, Equatable {
        /// `this bg` — the current card's background.
        case current
        /// `bg "Name"` / `bg 2` / `bg id 7`.
        case reference(HyperTalkObject.Reference)
    }
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

    /// A part on a card or its background: kind is the word the script used
    /// ("button", "field", "label", "image"). `onCard` names a different card
    /// the part lives on (`hilite of cd btn id 8 of cd "Stack Menus"`); nil
    /// means the current card.
    case part(kind: String, domain: PartDomain, reference: Reference, onCard: GoDestination?)
    case card(Reference)
    case thisCard
    case thisBackground
    case thisStack
}

/// The interpreter's only window onto the world. The app implements this;
/// scripts can do nothing the host doesn't offer (D7: the interpreter is
/// the sandbox).
public protocol HyperTalkHost: AnyObject {
    /// `go` to another card, optionally playing the effects queued by
    /// `visual effect` since the last `go` (empty for a plain cut).
    func goToCard(_ destination: GoDestination, effects: [ScreenEffect]) throws
    /// Field *contents*, addressed like any part: by name, ordinal, or id,
    /// optionally restricted to the card or background layer. `onCard` names a
    /// different card the field lives on (`field "X" of prev card`); nil means
    /// the current card.
    func fieldText(_ reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, onCard: GoDestination?) throws -> String
    func setFieldText(_ reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, onCard: GoDestination?, to text: String) throws
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
    /// `wait` — pause the script for `seconds`. The host owns real time (as
    /// with the clock), so tests can make it instant.
    func wait(seconds: Double) async
    /// `there is a[n] <object>` — whether the object exists right now.
    func exists(_ object: HyperTalkObject) -> Bool
    /// `find` — search the stack's searchable fields for `text` in the given
    /// mode, starting just past the previous match and wrapping around. On a
    /// hit the host navigates to that card, boxes the match, and updates the
    /// found* values; it returns whether anything was found (the interpreter
    /// sets `the result` to empty on success, "not found" on failure). When
    /// `inField` is given, only that field (on each card) is searched — and
    /// the host throws if no such field exists, rather than reporting a miss.
    func find(_ text: String, mode: FindMode, inField: HyperTalkObject.Reference?, fieldDomain: HyperTalkObject.PartDomain) throws -> Bool
    /// `the foundText` / `foundChunk` / `foundLine` / `foundField` — details
    /// of the last successful `find` (empty before any match).
    func foundValue(_ field: FoundField) -> String
    /// `the clickLine` / `the clickText` — where the last click on a locked
    /// field landed (see ClickField). Optional; defaults to empty.
    func clickValue(_ field: ClickField) -> String
    /// `select <chunk> of <field>` — set the script selection to a character
    /// range (character offsets, end exclusive) in a field. The host shows it
    /// and serves the selected* values. Throws when the field doesn't exist.
    func setSelection(field: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, start: Int, end: Int) throws
    /// `select empty` — clear the script selection.
    func clearSelection()
    /// `the selectedLine` / `selectedText` / `selectedChunk` / `selectedField`.
    func selectionValue(_ component: SelectionComponent) -> String
    /// `the number of cards / backgrounds / [card|bkgnd] buttons / fields`.
    func count(_ countable: Countable) throws -> Int
    /// During `sort`, temporarily resolve field/property lookups against the
    /// given card index (nil restores the real current card), so the sort key
    /// can be evaluated on each card without navigating.
    func setSortContext(_ cardIndex: Int?)
    /// `sort` — reorder the stack's cards to the given permutation of current
    /// indices (e.g. `[2,0,1]` puts card 3 first).
    func reorderCards(_ order: [Int]) throws
    /// `doMenu <item>` that no handler trapped — perform the built-in menu
    /// action (e.g. New Card, Delete Card). Unknown items are ignored.
    func performMenu(_ item: String) throws
    /// `click at h,v` — a synthetic click at a card location (in card
    /// coordinates); the host routes a mouseUp to whatever part is there.
    func click(x: Int, y: Int)
    /// `push [this] card` — remember the current card on a session stack.
    func pushCard()
    /// `pop card` — remove and return the most recently pushed card's id (nil
    /// if the stack is empty). The interpreter navigates there, or writes the
    /// reference into a container for `pop card into …`.
    func popCard() -> String?
    /// Whether `name` is one of the stack's external commands or functions —
    /// the XCMD/XFCN resource names recorded when a legacy stack is imported.
    /// Contrapt can't run compiled externals, so the interpreter turns calls
    /// to *known* ones into no-ops (functions return empty) instead of
    /// "Can't understand" errors — while genuinely unknown names still error,
    /// so typos in the user's own scripts surface.
    func isExternalName(_ name: String) -> Bool
}

public extension HyperTalkHost {
    /// Hosts without external-name records (tests, the web engine) treat
    /// every unknown name as a real error.
    func isExternalName(_ name: String) -> Bool { false }

    /// Hosts without click tracking read `the clickLine`/`clickText` as empty.
    func clickValue(_ field: ClickField) -> String { "" }

    /// Hosts without selection support ignore `select` and read empty.
    func setSelection(field: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, start: Int, end: Int) throws {}
    func clearSelection() {}
    func selectionValue(_ component: SelectionComponent) -> String { "" }
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
