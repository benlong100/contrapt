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

/// One item of a scripted custom menu (`create menu` / `put … into menu`).
public struct HyperTalkMenuItem: Sendable, Equatable {
    public var name: String
    public var enabled: Bool
    public var checkMark: Bool
    /// Sent instead of `doMenu <name>` when the item is chosen, if nonempty.
    public var menuMessage: String

    public init(name: String, enabled: Bool = true, checkMark: Bool = false, menuMessage: String = "") {
        self.name = name
        self.enabled = enabled
        self.checkMark = checkMark
        self.menuMessage = menuMessage
    }
}

/// A scripted custom menu. The host stores the menu bar (it outlives any one
/// handler dispatch) and renders it; the interpreter owns the semantics of
/// the menu verbs and mutates the bar through the snapshot/update pair.
public struct HyperTalkMenu: Sendable, Equatable {
    public var name: String
    public var enabled: Bool
    public var items: [HyperTalkMenuItem]

    public init(name: String, enabled: Bool = true, items: [HyperTalkMenuItem] = []) {
        self.name = name
        self.enabled = enabled
        self.items = items
    }
}

/// Where `write … to file` lands: the file's current mark (a fresh open
/// writes from the top), the end (`at eof`/`at end` appends), or an absolute
/// 1-based character position (`at 100`).
public enum FileWritePosition: Sendable, Equatable {
    case mark
    case eof
    case offset(Int)
}

/// A date/time format for the `convert` command. `convert` reads a value
/// (in the `from` format, or auto-detected) and rewrites it in the `to`
/// format. `dateItems` is the seven comma-separated numbers year, month,
/// day, hour, minute, second, and day-of-week; `seconds` is a count from a
/// fixed epoch. Date and time components combine with `and`.
/// HyperCard's clock: `the seconds` and `convert … to seconds` count from
/// January 1, 1904 (local time), not the Unix epoch — 2841955200 seconds is
/// 1/21/94, not a 2060 date (oracle-verified against HC 2.3). Two-digit years
/// pivot to the CURRENT century ("1/15/94" on a 2026 clock is 2094), exactly
/// as real HyperCard resolves them.
public enum HyperCardDate {
    public static func epoch1904(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: 1904, month: 1, day: 1)) ?? Date(timeIntervalSince1970: -2_082_844_800)
    }
    public static func seconds(of date: Date, calendar: Calendar = .current) -> Int {
        Int(date.timeIntervalSince(epoch1904(in: calendar)))
    }
    public static func date(fromSeconds seconds: Double, calendar: Calendar = .current) -> Date {
        epoch1904(in: calendar).addingTimeInterval(seconds)
    }
    /// Jan 1 of the current century — DateFormatter.twoDigitStartDate, so
    /// "94" resolves into the century we're in (HyperCard's rule).
    public static var centuryStart: Date {
        let year = (Calendar.current.component(.year, from: Date()) / 100) * 100
        return Calendar.current.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
    }
}

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
/// list-field navigation idiom. Empty before any such click. `location` is
/// `the clickLoc` — the card point of the last press, "h,v" (DateBook's month
/// grids compute the clicked row from it).
public enum ClickField: Sendable, Equatable {
    case line, text, location
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
    /// A nil background name means the *current* card's background (`go last
    /// card of bkgnd` with no name, or `of this bkgnd`).
    indirect case inBackground(GoDestination, background: String?)
    /// `marked card N` — the Nth card (1-based, stack order) whose `marked`
    /// property is true. `go marked card 2`, `bg field "X" of marked card n`.
    case markedCard(Int)
    /// `go next/previous marked card` — the next/previous marked card from the
    /// current one, wrapping around.
    case relativeMarked(forward: Bool)
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
    /// `the number of marked cards` — cards whose `marked` property is true.
    case markedCards

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
    /// A card as an object, addressed the same way `go` addresses one — by
    /// number/name/id, by ordinal, or scoped to a background (`card "X" of
    /// bkgnd "Y"`). The host resolves it with the same logic as navigation.
    case card(GoDestination)
    case thisCard
    case thisBackground
    case thisStack
}

/// The interpreter's only window onto the world. The app implements this;
/// scripts can do nothing the host doesn't offer (D7: the interpreter is
/// the sandbox).
public protocol HyperTalkHost: AnyObject {
    /// `go` to another card, optionally playing the effects queued by
    /// `visual effect` since the last `go` (empty for a plain cut). Async so
    /// a host can hold the script while the effect plays — HyperCard scripts
    /// resume only after the new card is on screen.
    func goToCard(_ destination: GoDestination, effects: [ScreenEffect]) async throws
    /// `lock screen` / `unlock screen`. Hosts that show each stack in its own
    /// window use this to defer a cross-window `go home`/`go stack` until the
    /// screen unlocks, so the classic invisible peek-and-pop at Home doesn't
    /// reorder windows. Optional; the default ignores it.
    func setScreenLocked(_ locked: Bool)
    /// Window properties — `the rect of card window` / `set the rect of card
    /// window to …`. Classic stacks crop a large card by shrinking the card
    /// window (The Hacker Crackdown's resizable pages). `window` is the
    /// window's qualifier/name, lowercased ("card", "tool", a palette name…).
    /// The getter returns nil to fall back to the absent-object default
    /// (`visible` false, everything else empty); the setter defaults to no-op.
    func windowProperty(_ property: String, window: String) -> String?
    func setWindowProperty(_ property: String, window: String, to value: String) throws
    /// `the optionKey` / `shiftKey` / `commandKey` / `controlKey` — "down"
    /// or "up". The nocheat/easter-egg idiom (`if the optionKey is down`).
    func modifierKey(_ name: String) -> String
    /// The scripted menu bar (`create menu`, `put … into menu`, …). The host
    /// STORES it (menus outlive a dispatch) and renders it; the interpreter
    /// reads the snapshot, applies a verb, and writes the result back.
    func menuBarSnapshot() -> [HyperTalkMenu]
    func updateMenuBar(_ menus: [HyperTalkMenu])
    /// A native shim for an XCMD/XFCN the stack recorded at import. Return
    /// the external's value (functions) / its `the result` text (commands,
    /// empty = success) — or nil when the host has no shim, which keeps the
    /// accepted-and-ignored behavior. Async so a shim can present UI (pop-up
    /// menus, file dialogs).
    func callExternal(_ name: String, arguments: [String]) async throws -> String?
    /// File I/O for `open/read/write/close file`. Paths are classic-style
    /// (colon-separated or bare names); the host owns the mapping to real
    /// storage. `fileRead` consumes from the file's mark and reports whether
    /// it hit end-of-file; `until` reads through the delimiter (inclusive),
    /// `count` reads that many characters, neither reads the rest. Throwing
    /// HostError surfaces as `the result`, not a script error (as HyperCard).
    func fileOpen(_ path: String) throws
    func fileClose(_ path: String) throws
    func fileRead(_ path: String, until delimiter: String?, count: Int?) throws -> (text: String, atEOF: Bool)
    func fileWrite(_ path: String, text: String, at position: FileWritePosition) throws
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
    /// `answer file <prompt> [of type <type>]` — a file-open dialog. `type` is
    /// the classic four-char Mac file type the stack asked for (e.g. "STAK"),
    /// advisory only. Returns the chosen file's path, or nil if the user
    /// cancels.
    func answerFile(_ prompt: String, type: String?) async -> String?
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
    /// A text-run property (`textFont`, `textSize`, `textStyle`) over a
    /// character range of a field — `the textStyle of char 3 to 9 of field "X"`,
    /// `the textSize of line 2 of fld "Notes"`. Returns the uniform value over
    /// the range, or "mixed" when the runs disagree (as in HyperCard).
    func textRunProperty(_ property: String, ofField reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, range: Range<Int>) throws -> String
    /// The write side: `set the textStyle/textFont/textSize of <chunk> of
    /// <field> to …` applies `value` over the character range, splitting and
    /// merging style runs as needed. Default ignores it (hosts without styled
    /// text keep the accept-and-ignore behavior).
    func setTextRunProperty(_ property: String, ofField reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, range: Range<Int>, to value: String) throws
    /// `the number of cards / backgrounds / [card|bkgnd] buttons / fields`.
    func count(_ countable: Countable) throws -> Int
    /// During `sort`, temporarily resolve field/property lookups against the
    /// given card index (nil restores the real current card), so the sort key
    /// can be evaluated on each card without navigating.
    func setSortContext(_ cardIndex: Int?)
    /// `sort` — reorder the stack's cards to the given permutation of current
    /// indices (e.g. `[2,0,1]` puts card 3 first).
    func reorderCards(_ order: [Int]) throws
    /// `mark`/`unmark` — set a card's `marked` property. `card` nil means the
    /// current card. `mark all cards` and `mark cards where …` call this once
    /// per card (by number). Throws if the card doesn't exist.
    func setMarked(_ marked: Bool, card: GoDestination?) throws
    /// `start using stack <name>` / `stop using stack <name>` — add/remove an
    /// auxiliary stack from the message hierarchy (session state the host owns,
    /// like globals). The host resolves the named stack's script.
    func beginUsingStack(_ name: String)
    func endUsingStack(_ name: String)
    /// The scripts of the stacks currently in use, most-recently-added first —
    /// searched for handlers/functions after the current stack, before giving up.
    func inUseStackScripts() -> [(name: String, source: String)]
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
    /// `the mouse` — whether the primary button (or a touch) is down right
    /// now, for the classic press-and-hold poll `repeat until the mouse is
    /// up`. Optional; hosts without live mouse tracking read up, so such a
    /// loop exits on its first check.
    func mouseIsDown() -> Bool
    /// `the mouseClick` — whether a click has happened since this was last
    /// read. True is reported once per click and consumed on read, so the
    /// classic wait-for-a-click poll `repeat until the mouseClick` exits on
    /// the next click (and `the clickLoc`/`the clickLine` then describe it).
    /// Optional; hosts without click tracking read false, so such a loop would
    /// spin — those hosts shouldn't run click-wait scripts. The click that
    /// launched the current handler does not count.
    func consumeMouseClick() -> Bool
    /// `the mouseLoc` / `mouseH` / `mouseV` — the pointer's card location,
    /// live during a browse press (the mid-drag tracking loops poll). Nil
    /// (the default) reads as 0,0 — hosts without pointer tracking.
    func mouseLocation() -> (x: Int, y: Int)?
    /// The card/background/stack scripts of the *current* card, in message-path
    /// order (card, then background, then stack). The interpreter re-reads this
    /// after every in-stack `go` so the message path follows navigation, as in
    /// HyperCard: a handler that navigates and then sends a message (or lets one
    /// travel unhandled) reaches the card it moved to, not the one it started
    /// on. Return nil (the default) to keep the path fixed at dispatch — hosts
    /// that don't model a live current card opt out this way.
    func systemScriptLayers() -> [ScriptLayer]?
    /// The full dispatch path for `send <msg> to <object>` when the target
    /// isn't on the running message path: the object's own script layer first,
    /// then the layers beneath it (its card, background, stack). Nil (the
    /// default) means the host can't resolve it — the send then dispatches
    /// from the current layer, the pre-targeted behavior.
    func scriptLayers(for object: HyperTalkObject) -> [ScriptLayer]?
    /// `play <voice> [tempo <n>] [<notes>]` — start the named sound, as a
    /// melody when `notes` is non-empty (tempo in quarter-notes per minute).
    /// Playback is asynchronous: the script continues while sound plays, and
    /// `the sound` reports the voice until it finishes. Optional; hosts
    /// without audio ignore it.
    func play(voice: String, tempo: Double, notes: [PlayNote])
    /// `play stop` — silence the current sound. Optional.
    func stopPlay()
    /// `choose <name> tool` — "browse", "button", "field", or a paint tool
    /// name. With the button/field tool chosen, `click at` selects the part
    /// under the point (armed for `doMenu "Clear Button"`) instead of
    /// clicking it. Optional; hosts without tools ignore it.
    func chooseTool(_ name: String)
    /// `the tool` — the chosen tool's name, e.g. "browse tool". Optional.
    func currentToolName() -> String
    /// `the sound` — the playing voice's name, or "done" when idle. Optional;
    /// hosts without audio always read "done", so wait-for-melody loops
    /// (`repeat until the sound is done`) exit immediately.
    func playingSoundName() -> String
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

    /// Hosts that don't model card marking ignore `mark`/`unmark`.
    func setMarked(_ marked: Bool, card: GoDestination?) throws {}

    /// Hosts that don't model a multi-stack library ignore `start/stop using`
    /// and report no in-use stacks (so the message path stays single-stack).
    func beginUsingStack(_ name: String) {}
    func endUsingStack(_ name: String) {}
    func inUseStackScripts() -> [(name: String, source: String)] { [] }

    /// Hosts without per-run style storage fall back to the field's whole-field
    /// run property (the range is ignored).
    func setTextRunProperty(_ property: String, ofField reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, range: Range<Int>, to value: String) throws {}

    func textRunProperty(_ property: String, ofField reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, range: Range<Int>) throws -> String {
        try propertyValue(property, of: .part(kind: "field", domain: domain, reference: reference, onCard: nil))
    }

    /// Single-window hosts (and tests) don't defer navigation; ignore the lock.
    func setScreenLocked(_ locked: Bool) {}

    /// Hosts without window objects fall back to the absent-object defaults.
    func windowProperty(_ property: String, window: String) -> String? { nil }
    func setWindowProperty(_ property: String, window: String, to value: String) throws {}

    /// Hosts without a keyboard read every modifier as up.
    func modifierKey(_ name: String) -> String { "up" }

    /// Hosts without a menu bar: verbs no-op, reads see no menus.
    func menuBarSnapshot() -> [HyperTalkMenu] { [] }
    func updateMenuBar(_ menus: [HyperTalkMenu]) {}

    /// Hosts without native XCMD/XFCN shims leave externals as no-ops.
    func callExternal(_ name: String, arguments: [String]) async throws -> String? { nil }

    /// Hosts without file access report HyperCard's classic failure.
    func fileOpen(_ path: String) throws { throw HostError("Can't open that file.") }
    func fileClose(_ path: String) throws { throw HostError("File not open.") }
    func fileRead(_ path: String, until delimiter: String?, count: Int?) throws -> (text: String, atEOF: Bool) {
        throw HostError("File not open.")
    }
    func fileWrite(_ path: String, text: String, at position: FileWritePosition) throws {
        throw HostError("File not open.")
    }

    /// Hosts without live mouse tracking read `the mouse` as up and the
    /// pointer as unknown.
    func mouseIsDown() -> Bool { false }
    func consumeMouseClick() -> Bool { false }
    func mouseLocation() -> (x: Int, y: Int)? { nil }

    /// Hosts that don't model a live current card keep the message path fixed
    /// at dispatch (the pre-navigation-following behavior).
    func systemScriptLayers() -> [ScriptLayer]? { nil }

    /// Hosts that can't resolve arbitrary objects leave off-path sends
    /// dispatching from the current layer.
    func scriptLayers(for object: HyperTalkObject) -> [ScriptLayer]? { nil }

    /// Hosts without audio ignore `play` and read `the sound` as done.
    func play(voice: String, tempo: Double, notes: [PlayNote]) {}
    func stopPlay() {}
    func playingSoundName() -> String { "done" }

    /// Hosts without tools ignore `choose` and always read the browse tool.
    func chooseTool(_ name: String) {}
    func currentToolName() -> String { "browse tool" }
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
