//
//  DocumentScriptHost.swift
//  Contrapt
//

import SwiftUI
import AVFoundation
import Combine
import HyperTalk

/// Session-wide HyperTalk globals — shared across cards and stacks while
/// the app runs, as in HyperCard.
@MainActor final class GlobalStore {
    static let shared = GlobalStore()
    var values: [String: String] = [:]
}

/// The `push card` / `pop card` back-stack, session-wide (the host is rebuilt
/// per script run, so the stack lives here).
@MainActor final class CardBackStack {
    static let shared = CardBackStack()
    var ids: [String] = []
}

/// Browser history for `go back` — the trail of cards a script navigated
/// away from. Session-wide, since the host is rebuilt per script run.
@MainActor final class VisitHistory {
    static let shared = VisitHistory()
    var ids: [String] = []
}

/// Stacks added to the message hierarchy by `start using stack "X"`, session-
/// wide (the host is rebuilt per run). Each stack's script is resolved once,
/// via the Stack Library, and searched after the current stack for handlers
/// and functions. Most-recently-added first, as in HyperCard.
@MainActor final class UsingStackStore {
    static let shared = UsingStackStore()
    private(set) var stacks: [(name: String, source: String)] = []

    func begin(_ name: String) {
        stacks.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        guard let url = StackLibrary.shared.url(forName: name),
              let data = try? Data(contentsOf: url) else { return }
        // A classic stack's first block is the STAK block; otherwise it's a
        // native .contrapt. (StackDocument.load never returns nil — it yields an
        // empty stack for non-.contrapt bytes — so dispatch on the format here.)
        let head = Array(data.prefix(8))
        let isClassic = head.count >= 8 && String(bytes: head[4..<8], encoding: .ascii) == "STAK"
        if isClassic {
            if let imported = try? LegacyStackImporter.stack(
                from: data, name: name, stackFork: ResourceFork.forkData(of: url)) {
                stacks.insert((name, imported.stack.script), at: 0)
            }
        } else if let document = StackDocument.load(from: url) {
            stacks.insert((name, document.stack.script), at: 0)
        }
    }

    func end(_ name: String) {
        stacks.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Clears all in-use stacks — used between independent runs (the audit).
    func reset() { stacks.removeAll() }
}

/// Remembered network-consent decisions, per (stack, host). "Always" answers
/// persist in UserDefaults so a trusted stack doesn't re-prompt across launches;
/// "Allow Once" and session denials live only for this app session. The stack
/// being authored bypasses this entirely (see DocumentScriptHost.isNetworkAllowed).
@MainActor final class NetworkConsentStore {
    static let shared = NetworkConsentStore()
    private var sessionAllow: Set<String> = []
    private var sessionDeny: Set<String> = []

    static func key(stackPath: String, host: String) -> String {
        "\(stackPath)\n\(host.lowercased())"
    }

    private func defaultsKey(_ key: String) -> String { "network.consent.\(key)" }

    /// A remembered allow (true) / deny (false), or nil if the stack hasn't
    /// been asked about this host yet. Session answers win over persisted ones.
    func remembered(_ key: String) -> Bool? {
        if sessionAllow.contains(key) { return true }
        if sessionDeny.contains(key) { return false }
        return UserDefaults.standard.object(forKey: defaultsKey(key)) as? Bool
    }

    func record(_ key: String, allow: Bool, always: Bool) {
        if always {
            UserDefaults.standard.set(allow, forKey: defaultsKey(key))
        } else if allow {
            sessionAllow.insert(key)
        } else {
            sessionDeny.insert(key)
        }
    }
}

/// The stack's persistent `stackData` store — one encoded associative-array
/// string per stack, kept in a per-stack file under Application Support so it
/// survives between runs. Private to each stack (keyed by the stack's id); the
/// stack file itself is never touched. A small in-memory cache fronts the file.
@MainActor final class StackDataStore {
    static let shared = StackDataStore()
    private var cache: [String: String] = [:]

    private func fileURL(for id: String) -> URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Stack Data", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("\(id).json")
    }

    func data(for id: String) -> String {
        if let cached = cache[id] { return cached }
        let loaded = (fileURL(for: id).flatMap { try? String(contentsOf: $0, encoding: .utf8) }) ?? ""
        cache[id] = loaded
        return loaded
    }

    func set(_ data: String, for id: String) {
        cache[id] = data
        guard let url = fileURL(for: id) else { return }
        try? data.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Where `find` last matched, so the view can box it on the card.
struct FindHighlight: Equatable {
    var partID: UUID
    /// Character range within the field's text (for future exact boxing).
    var range: Range<Int>?
}

/// The running `find` cursor and its results, kept across script runs (so
/// repeating `find` walks to the next match, as in HyperCard).
/// Where the last click on a locked field landed — `the clickLine` (a
/// descriptor like `line 3 of card field id 12`) and `the clickText` (the
/// word clicked). The field's press gesture records the raw hit; the mouseUp
/// dispatcher composes the descriptor (it knows the part's layer). Session
/// state, like FindSession: kept until the next locked-field click.
/// Whether a browse-mode press is currently down — `the mouse`. Every press
/// gesture (button, locked field, label, card surface) flips it at touch-down
/// and release, so a script's press-and-hold poll (`repeat until the mouse is
/// up`) sees the release. Session state, like ClickRecord.
@MainActor final class MouseState {
    static let shared = MouseState()
    var isDown = false
    /// The pointer's card location, updated continuously while a browse press
    /// drags — `the mouseLoc` (there's no hover tracking; between presses it
    /// holds the last press's position).
    var location = CGPoint.zero
}

@MainActor final class ClickRecord {
    static let shared = ClickRecord()
    /// The raw hit from the press gesture, consumed by the dispatcher.
    private var pending: (line: Int, text: String, chunk: Range<Int>?)?
    var line = ""
    var text = ""
    var chunk = ""
    /// The card point of the last press — `the clickLoc` (DateBook's month
    /// grids compute the clicked row from it). Nil before any press.
    var clickLocation: CGPoint?
    /// Whether a completed click is waiting for `the mouseClick` to report it.
    /// Armed only when a click lands while a script is already running (the
    /// dispatcher absorbs it instead of launching a competing handler), so the
    /// wait-for-a-click poll `repeat until the mouseClick` (deleteHCLine's list
    /// idiom) sees the user's next click — not the one that launched it.
    var clickPending = false

    func recordPending(line: Int, text: String, chunk: Range<Int>?) { pending = (line, text, chunk) }
    func takePending() -> (line: Int, text: String, chunk: Range<Int>?)? {
        defer { pending = nil }
        return pending
    }

    /// Reads and clears the pending-click flag — `the mouseClick`.
    func consumeClick() -> Bool {
        defer { clickPending = false }
        return clickPending
    }
}

/// The script selection set by `select line 2 of field 1` — which field (by
/// model id + permanent scriptID), its layer word for descriptors, and the
/// character range. Session state (hosts are per-dispatch); cleared on
/// navigation, as in HyperCard.
@MainActor final class SelectionSession {
    static let shared = SelectionSession()
    var partID: UUID?
    var scriptID = 0
    var layer = "card"
    var range: Range<Int> = 0..<0

    func clear() { partID = nil }
}

@MainActor final class FindSession {
    static let shared = FindSession()
    var query: String?
    var mode: FindMode = .wordPrefix
    var scope: String?          // the field reference searched, if any
    var cardIndex = 0
    var partID: UUID?
    var matchStart = 0
    var found: [FoundField: String] = [:]

    func reset() {
        query = nil
        partID = nil
        matchStart = 0
        found = [:]
    }
}

/// Bridges a running script to the open document: `go` moves the current
/// card, `field` reads and writes field parts on the current card and its
/// background. Scripts can reach nothing else (D7: the interpreter is the
/// sandbox, and this host is its only door).
@MainActor
final class DocumentScriptHost: HyperTalkHost {
    private let stackBinding: Binding<Stack>
    private let currentCardIndex: Binding<Int>
    private let onMessage: (String) -> Void
    private let onAnswer: (String, [String]) async -> String
    private let onAsk: (String, String) async -> String?
    private let onAnswerFile: (String, String?) async -> String?
    private let onNavigate: (Int, [ScreenEffect]) -> Void
    private let onFind: (FindHighlight?) -> Void
    private let onSelection: (FindHighlight?) -> Void
    private let onGoHome: () -> Void
    private let onClickPart: (Part) -> Void
    private let onGoStack: (String, GoDestination?) -> Void
    /// `lock screen` state, and a cross-window `go home`/`go stack` deferred
    /// while locked (applied on unlock). Lets the classic invisible peek-and-pop
    /// at Home net out to no window switch, so the stack stays frontmost.
    private var isScreenLocked = false
    private var pendingLockedDestination: GoDestination?
    /// `doMenu "Copy/Cut/Paste Card"` — the item, lowercased. Routed to the
    /// document's own card-clipboard actions so scripts and the Edit menu
    /// share one implementation.
    private let onCardMenu: (String) -> Void
    /// Asset bytes by name — `play` reads its WAV through this (assets live on
    /// the document, not the stack).
    private let assetData: (String) -> Data?
    /// Stores asset bytes on the document — scripted painting writes the
    /// card's updated paint PNG through this.
    private let onAssetWrite: (String, Data) -> Void
    /// The document's full asset table — card rendering for print needs every
    /// paint/icon image, not single lookups.
    private let assetsSnapshot: () -> [String: Data]
    /// Presents a print dialog for finished PDF data (title second). The app
    /// wires the real dialog; tests capture the bytes.
    private let onPresentPrint: (Data, String) -> Void
    /// Flashes the screen (inverts N times) — the Flash XCMD's effect.
    private let onFlash: (Int) -> Void
    /// The document's classic-style colon path, for `the long name of this
    /// stack`. Empty for an unsaved stack (falls back to the bare name).
    private let stackPath: String
    /// Whether the stack is being authored right now (edit mode). The stack you
    /// are editing is trusted to reach the network without a consent prompt;
    /// a stack merely being browsed must ask. Read live, so toggling Edit
    /// changes the answer mid-session.
    private let isAuthoring: () -> Bool
    /// Presents the network-consent prompt for a host the running stack hasn't
    /// been granted yet. Returns whether to allow the connection and whether to
    /// remember that choice (Allow Always / Don't Allow persist; Allow Once is
    /// allow=true, always=false). Suspends the script until the user answers,
    /// like `answer`.
    private let onNetworkConsent: (String) async -> (allow: Bool, always: Bool)
    /// `send … in <time>` — hands the resolved (message, arguments, target,
    /// seconds) to the document view, which owns the pending timers (this
    /// host is per-dispatch and won't outlive the script). Nil = no clock
    /// here (tests, print rendering), and the command errors.
    private let onScheduleSend: ((String, [String], HyperTalkObject, Double) -> Void)?

    init(
        stack: Binding<Stack>,
        currentCardIndex: Binding<Int>,
        stackPath: String = "",
        onMessage: @escaping (String) -> Void,
        onAnswer: @escaping (String, [String]) async -> String,
        onAsk: @escaping (String, String) async -> String?,
        onAnswerFile: @escaping (String, String?) async -> String? = { _, _ in nil },
        onNavigate: @escaping (Int, [ScreenEffect]) -> Void,
        onFind: @escaping (FindHighlight?) -> Void = { _ in },
        onSelection: @escaping (FindHighlight?) -> Void = { _ in },
        onGoHome: @escaping () -> Void = {},
        onClickPart: @escaping (Part) -> Void = { _ in },
        onGoStack: @escaping (String, GoDestination?) -> Void = { _, _ in },
        onCardMenu: @escaping (String) -> Void = { _ in },
        assetData: @escaping (String) -> Data? = { _ in nil },
        onAssetWrite: @escaping (String, Data) -> Void = { _, _ in },
        assetsSnapshot: @escaping () -> [String: Data] = { [:] },
        onPresentPrint: @escaping (Data, String) -> Void = { _, _ in },
        onFlash: @escaping (Int) -> Void = { _ in },
        isAuthoring: @escaping () -> Bool = { false },
        onNetworkConsent: @escaping (String) async -> (allow: Bool, always: Bool) = { _ in (false, false) },
        onScheduleSend: ((String, [String], HyperTalkObject, Double) -> Void)? = nil,
        cardWindowViewport: Binding<CGSize?> = .constant(nil),
        menuBar: Binding<[HyperTalkMenu]> = .constant([])
    ) {
        self.stackBinding = stack
        self.currentCardIndex = currentCardIndex
        self.stackPath = stackPath
        self.onMessage = onMessage
        self.onAnswer = onAnswer
        self.onAsk = onAsk
        self.onAnswerFile = onAnswerFile
        self.onNavigate = onNavigate
        self.onFind = onFind
        self.onSelection = onSelection
        self.onGoHome = onGoHome
        self.onClickPart = onClickPart
        self.onGoStack = onGoStack
        self.onCardMenu = onCardMenu
        self.assetData = assetData
        self.onAssetWrite = onAssetWrite
        self.assetsSnapshot = assetsSnapshot
        self.onPresentPrint = onPresentPrint
        self.onFlash = onFlash
        self.isAuthoring = isAuthoring
        self.onNetworkConsent = onNetworkConsent
        self.onScheduleSend = onScheduleSend
        self.cardWindowViewport = cardWindowViewport
        self.menuBar = menuBar
    }

    /// `send <msg> to <object> in <time>` — the document view owns the timer;
    /// pending sends survive navigation and die when the stack closes.
    func scheduleSend(_ message: String, arguments: [String], to target: HyperTalkObject, afterSeconds: Double) throws {
        guard let onScheduleSend else {
            throw HostError("Timed sends aren't available here.")
        }
        onScheduleSend(message, arguments, target, afterSeconds)
    }

    /// The scripted menu bar (`create menu` …) — stored in the document view's
    /// state so it outlives this transient host and renders as a strip.
    private let menuBar: Binding<[HyperTalkMenu]>

    func menuBarSnapshot() -> [HyperTalkMenu] { menuBar.wrappedValue }
    func updateMenuBar(_ menus: [HyperTalkMenu]) { menuBar.wrappedValue = menus }

    /// The card-window viewport (nil = show the whole card). A stack that
    /// "resizes" its card window (`set the rect of card window to …`) really
    /// crops the card to this size — the classic big-card-small-window idiom.
    private let cardWindowViewport: Binding<CGSize?>

    /// Scripted palette/external windows opened by the `palette` XCMD (and
    /// `show/hide/close window`). Session-wide (like the chosen tool), reset
    /// when a stack opens. ContentView observes this to render open palettes as
    /// floating panels; this layer also makes `the windows`, `there is a window
    /// "X"`, and the visible/loc/rect properties behave (Tubers).
    @MainActor final class PaletteRegistry: ObservableObject {
        static let shared = PaletteRegistry()
        struct Window: Identifiable {
            let id = UUID()
            var name: String
            var visible: Bool
            var loc: (x: Int, y: Int)?
            /// The palette's buttons (rect + command), from its PLTE resource.
            /// Empty when the stack carries no matching PLTE — the window still
            /// registers so the scripting idioms work, it just draws no buttons.
            var buttons: [PaletteButtonDefinition] = []
        }
        @Published private(set) var windows: [Window] = []

        func index(of name: String) -> Int? {
            windows.firstIndex { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }
        func open(_ name: String, loc: (Int, Int)?, buttons: [PaletteButtonDefinition] = []) {
            if let i = index(of: name) {
                windows[i].visible = true
                if let loc { windows[i].loc = loc }
                if !buttons.isEmpty { windows[i].buttons = buttons }
            } else {
                windows.append(Window(name: name, visible: true, loc: loc, buttons: buttons))
            }
        }
        func setVisible(_ name: String, _ visible: Bool) { if let i = index(of: name) { windows[i].visible = visible } }
        func setLoc(_ name: String, _ loc: (Int, Int)) { if let i = index(of: name) { windows[i].loc = loc } }
        func close(_ name: String) { windows.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame } }
        func reset() { windows.removeAll() }
    }

    /// The open windows for `the windows`: the card window first, then any
    /// scripted palettes, as HyperCard lists them.
    func windowList() -> [String] {
        ["card window"] + PaletteRegistry.shared.windows.map(\.name)
    }

    func windowProperty(_ property: String, window: String) -> String? {
        // A scripted palette window, by name.
        if let i = PaletteRegistry.shared.index(of: window) {
            let win = PaletteRegistry.shared.windows[i]
            switch property {
            case "visible": return win.visible ? "true" : "false"
            case "name": return win.name
            case "loc", "location":
                let loc = win.loc ?? (0, 0)
                return "\(loc.x),\(loc.y)"
            case "rect", "rectangle":
                let loc = win.loc ?? (0, 0)
                return "\(loc.x),\(loc.y),\(loc.x),\(loc.y)" // size unknown until rendered
            default: return nil
            }
        }
        guard window == "card" || window == "cd" else { return nil }
        let size = cardWindowViewport.wrappedValue
            ?? CGSize(width: stack.cardSize.width, height: stack.cardSize.height)
        switch property {
        case "rect", "rectangle":
            return "0,0,\(Int(size.width)),\(Int(size.height))"
        case "width": return String(Int(size.width))
        case "height": return String(Int(size.height))
        case "scroll": return "0,0" // the idle "fault recovery" reset idiom
        case "visible": return "true"
        default: return nil
        }
    }

    func setWindowProperty(_ property: String, window: String, to value: String) throws {
        // A scripted palette window: show/hide/close/move.
        if PaletteRegistry.shared.index(of: window) != nil {
            let registry = PaletteRegistry.shared
            switch property {
            case "visible": registry.setVisible(window, value.lowercased() == "true")
            case "close": registry.close(window)
            case "loc", "location", "rect", "rectangle":
                let n = value.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                if n.count >= 2 { registry.setLoc(window, (n[0], n[1])) }
            default: break
            }
            return
        }
        guard window == "card" || window == "cd" else { return }
        let current = cardWindowViewport.wrappedValue
            ?? CGSize(width: stack.cardSize.width, height: stack.cardSize.height)
        switch property {
        case "rect", "rectangle":
            let parts = value.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 4 else { return }
            applyViewport(CGSize(width: parts[2] - parts[0], height: parts[3] - parts[1]))
        // The Hacker Crackdown sizes its card window one dimension at a time:
        // `set width of card window to item 1 of line sizeNumber of …`.
        case "width":
            guard let width = Double(value) else { return }
            applyViewport(CGSize(width: width, height: current.height))
        case "height":
            guard let height = Double(value) else { return }
            applyViewport(CGSize(width: current.width, height: height))
        default:
            break // loc/scroll/visible of card window stay cosmetic no-ops
        }
    }

    /// Clamp and store a card-window viewport; a size at least the card's in
    /// both dimensions means "no crop" (nil, so the window hugs the full card).
    private func applyViewport(_ size: CGSize) {
        guard size.width >= 64, size.height >= 64 else { return }
        if size.width >= stack.cardSize.width, size.height >= stack.cardSize.height {
            cardWindowViewport.wrappedValue = nil
        } else {
            cardWindowViewport.wrappedValue = CGSize(
                width: min(size.width, stack.cardSize.width),
                height: min(size.height, stack.cardSize.height))
        }
    }

    private var stack: Stack { stackBinding.wrappedValue }

    /// Set during `sort` so field/property lookups resolve against each card
    /// in turn (see setSortContext); nil means the real current card.
    private var sortContextIndex: Int?

    /// The part a script just created with `doMenu "New Button"/"New Field"`,
    /// so a following `doMenu "Clear Button"/"Clear Field"` can remove it (the
    /// object HyperCard would have left selected). Lives for the dispatch.
    private var selectedPartID: UUID?

    private var cardIndex: Int {
        if let sortContextIndex { return sortContextIndex }
        return min(currentCardIndex.wrappedValue, stack.cards.count - 1)
    }

    func setSortContext(_ cardIndex: Int?) {
        sortContextIndex = cardIndex
    }

    func performMenu(_ item: String) throws {
        switch item.lowercased() {
        case "new card":
            // A new card shares the current card's background but starts with
            // an empty card layer, inserted just after it — as in HyperCard.
            // (Shared parts belong on the background; card parts are per-card.)
            let source = stack.cards[cardIndex]
            var card = Card(id: UUID(), name: "", backgroundID: source.backgroundID, script: "", parts: [])
            card.scriptID = stackBinding.wrappedValue.claimScriptID()
            let at = cardIndex + 1
            stackBinding.wrappedValue.cards.insert(card, at: at)
            onNavigate(at, [])
        case "copy card", "cut card", "paste card":
            // Card cut/copy/paste reuses the document's own clipboard actions
            // (they carry the card's background and asset bytes across stacks),
            // so a script and the Edit menu share one implementation.
            onCardMenu(item.lowercased())
        case "delete card":
            guard stack.cards.count > 1 else { return } // keep at least one card
            guard !stack.cards[cardIndex].cantDelete else {
                throw HostError("This card can't be deleted.")
            }
            let idx = cardIndex
            stackBinding.wrappedValue.cards.remove(at: idx)
            onNavigate(min(idx, stackBinding.wrappedValue.cards.count - 1), [])
        case "new button":
            addCardPart(makeNewButton())
        case "new field":
            addCardPart(makeNewField())
        case "clear button", "cut button":
            clearSelectedPart(where: { if case .button = $0.kind { return true }; return false })
        case "clear field", "cut field":
            clearSelectedPart(where: { if case .field = $0.kind { return true }; return false })
        default:
            return // menu items Contrapt doesn't model — ignore, as a no-op
        }
    }

    /// Appends a freshly-identified part to the current card's card layer (the
    /// layer `doMenu "New Button"/"New Field"` build on) and marks it the
    /// script-selected part, so a following `set … of btn (the number of card
    /// buttons)` addresses it and `doMenu "Clear Button"` can remove it.
    private func addCardPart(_ part: Part) {
        var part = part
        part.scriptID = stackBinding.wrappedValue.claimScriptID()
        guard stack.cards.indices.contains(cardIndex) else { return }
        stackBinding.wrappedValue.cards[cardIndex].parts.append(part)
        selectedPartID = part.id
    }

    /// Deletes the script-selected part when it matches (a button for "Clear
    /// Button", a field for "Clear Field"), as HyperCard clears the selected
    /// object. The selection is set by `doMenu "New Button"/"New Field"` (the
    /// just-created part) or by a `click at` with the button/field tool chosen
    /// (a pre-existing part, on the card or its background — DateBook's
    /// extendWeekly cleans up old "Extend" buttons this way). With no matching
    /// selection this is a no-op rather than an error.
    private func clearSelectedPart(where matches: (Part) -> Bool) {
        guard let id = selectedPartID, stack.cards.indices.contains(cardIndex) else { return }
        let card = stack.cards[cardIndex]
        if let index = card.parts.firstIndex(where: { $0.id == id }), matches(card.parts[index]) {
            stackBinding.wrappedValue.cards[cardIndex].parts.remove(at: index)
            selectedPartID = nil
            return
        }
        if let bgIndex = stack.backgrounds.firstIndex(where: { $0.id == card.backgroundID }),
           let index = stack.backgrounds[bgIndex].parts.firstIndex(where: { $0.id == id }),
           matches(stack.backgrounds[bgIndex].parts[index]) {
            stackBinding.wrappedValue.backgrounds[bgIndex].parts.remove(at: index)
            selectedPartID = nil
        }
    }

    private func makeNewButton() -> Part {
        let size = CGSize(width: 120, height: 40)
        return Part(
            id: UUID(),
            name: "New Button",
            frame: centeredFrame(size),
            script: "",
            kind: .button(ButtonPart(title: "New Button"))
        )
    }

    private func makeNewField() -> Part {
        let size = CGSize(width: 200, height: 120)
        return Part(
            id: UUID(),
            name: "",
            frame: centeredFrame(size),
            script: "",
            kind: .field(FieldPart(text: "", placeholder: "", isMultiline: true))
        )
    }

    /// A frame of the given size centered on the card, clamped into bounds.
    private func centeredFrame(_ size: CGSize) -> PartFrame {
        let w = min(size.width, stack.cardSize.width)
        let h = min(size.height, stack.cardSize.height)
        return PartFrame(
            x: max(0, (stack.cardSize.width - w) / 2),
            y: max(0, (stack.cardSize.height - h) / 2),
            width: w,
            height: h
        )
    }

    /// `choose <name> tool` — browse (the default) makes `click at` click;
    /// the button/field tool makes it *select* the part under the point, so
    /// HyperCard's delete idiom works without re-running the part's script:
    ///   choose button tool / click at loc of btn "X" / doMenu "Clear Button".
    /// The tool persists across dispatches (in PaintSession), as in HyperCard
    /// — the message box runs each line as its own dispatch, so `choose oval
    /// tool` must still be in effect when the next line drags. It only
    /// affects SCRIPTED click/drag; real mouse input never routes through it,
    /// and opening another stack resets to browse.
    func chooseTool(_ name: String) {
        PaintSession.shared.tool = name.lowercased()
    }

    func currentToolName() -> String {
        "\(chosenTool) tool"
    }

    private var chosenTool: String { PaintSession.shared.tool }

    /// The paint tools `drag`/`click` draw with. ("select"/"lasso"/"text"/
    /// "spray" are recognized as paint-family but don't draw yet.)
    private static let drawingTools: Set<String> = [
        "line", "pencil", "brush", "eraser", "rect", "rectangle",
        "round rect", "roundrect", "oval", "bucket", "regular polygon",
        "reg poly", "curve",
    ]

    private var isDrawingToolChosen: Bool { Self.drawingTools.contains(chosenTool) }

    /// Scripted-paint globals (`the lineSize`, `the pattern`, …). Session-wide
    /// (like HyperCard) so an openStack that sets them covers later handlers,
    /// even though each dispatch builds a fresh host.
    final class PaintSession {
        static let shared = PaintSession()
        var tool = "browse"
        var lineSize = 1      // 1…8
        var pattern = 12      // 12 = black; 1 = white
        var filled = false
        var centered = false
        var brush = 8
        var multiple = false
        // The text-paint tool settings — `the textHeight`/`textSize`/… as
        // globals (stored as strings; scripts set then read them back).
        var textSize = "12"
        var textHeight = "0"
        var textFont = "chicago"
        var textStyle = "plain"
        var textAlign = "left"

        func reset() {
            // `reset paint` resets settings; the tool is separate (HyperCard
            // keeps the chosen tool).
            lineSize = 1; pattern = 12; filled = false
            centered = false; brush = 8; multiple = false
        }
    }

    func paintSetting(_ name: String) -> String? {
        let paint = PaintSession.shared
        switch name {
        case "linesize", "pensize": return String(paint.lineSize)
        case "pattern", "penpattern": return String(paint.pattern)
        case "filled": return paint.filled ? "true" : "false"
        case "centered": return paint.centered ? "true" : "false"
        case "brush": return String(paint.brush)
        case "multiple": return paint.multiple ? "true" : "false"
        case "textsize": return paint.textSize
        case "textheight": return paint.textHeight
        case "textfont": return paint.textFont
        case "textstyle": return paint.textStyle
        case "textalign": return paint.textAlign
        default: return nil
        }
    }

    func setPaintSetting(_ name: String, to value: String) -> Bool {
        let paint = PaintSession.shared
        let flag = value.lowercased() == "true"
        switch name {
        case "linesize", "pensize": paint.lineSize = max(1, min(8, Int(Double(value) ?? 1)))
        case "pattern", "penpattern": paint.pattern = max(1, min(40, Int(Double(value) ?? 12)))
        case "filled": paint.filled = flag
        case "centered": paint.centered = flag
        case "brush": paint.brush = max(1, min(32, Int(Double(value) ?? 8)))
        case "multiple": paint.multiple = flag
        case "textsize": paint.textSize = value
        case "textheight": paint.textHeight = value
        case "textfont": paint.textFont = value
        case "textstyle": paint.textStyle = value
        case "textalign": paint.textAlign = value
        default: return false
        }
        return true
    }

    func resetPaint() { PaintSession.shared.reset() }

    /// The environment globals (`the userLevel`, `textArrows`, `powerKeys`,
    /// `blindTyping`) — session-wide, like HyperCard's Preferences. Contrapt
    /// doesn't gate features on them; stacks read back what they set (the
    /// Home Preferences card drives its whole UI off these).
    final class EnvironmentSession {
        static let shared = EnvironmentSession()
        var userLevel = 5
        var textArrows = false
        var powerKeys = false
        var blindTyping = false
    }

    func environmentSetting(_ name: String) -> String? {
        let env = EnvironmentSession.shared
        switch name {
        case "userlevel": return String(env.userLevel)
        case "textarrows": return env.textArrows ? "true" : "false"
        case "powerkeys": return env.powerKeys ? "true" : "false"
        case "blindtyping": return env.blindTyping ? "true" : "false"
        // Full HyperCard, not the Player — stacks with Player/Development twin
        // field sets switch their visible fields on this (see Host.swift).
        case "environment": return "Development"
        default: return nil
        }
    }

    func setEnvironmentSetting(_ name: String, to value: String) -> Bool {
        let env = EnvironmentSession.shared
        let flag = value.lowercased() == "true"
        switch name {
        case "userlevel": env.userLevel = max(1, min(5, Int(Double(value) ?? 5)))
        case "textarrows": env.textArrows = flag
        case "powerkeys": env.powerKeys = flag
        case "blindtyping": env.blindTyping = flag
        default: return false
        }
        return true
    }

    /// `type <expr>`: keystrokes at the insertion point — the script
    /// selection (`select after text of field X` then `type "…"`, the classic
    /// data-entry idiom). The typed text replaces the selected range and the
    /// caret lands after it. With commandKey it would be a menu shortcut —
    /// unmodeled, accepted silently. No selection → nowhere to type → no-op,
    /// as in HyperCard with no open insertion point.
    func typeText(_ text: String, withCommandKey: Bool) {
        guard !withCommandKey else { return }
        let session = SelectionSession.shared
        guard session.partID != nil else { return }
        let domain: HyperTalkObject.PartDomain = session.layer == "bkgnd" ? .background : .card
        let reference = HyperTalkObject.Reference.id(String(session.scriptID))
        guard let current = try? fieldText(reference, domain: domain, onCard: nil) else { return }
        let characters = Array(current)
        let lo = max(0, min(session.range.lowerBound, characters.count))
        let hi = max(lo, min(session.range.upperBound, characters.count))
        let updated = String(characters[0..<lo]) + text + String(characters[hi...])
        guard (try? setFieldText(reference, domain: domain, onCard: nil, to: updated)) != nil else { return }
        let caret = lo + text.count
        session.range = caret..<caret
        if let partID = session.partID {
            onSelection(FindHighlight(partID: partID, range: session.range))
        }
    }

    // MARK: - Printing

    /// `open printing` batches card indexes across dispatches (the classic
    /// loop is go/print per card, often line by line) until `close printing`.
    final class PrintSession {
        static let shared = PrintSession()
        var isOpen = false
        var queued: [Int] = []
    }

    func openPrinting(withDialog: Bool) {
        PrintSession.shared.isOpen = true
        PrintSession.shared.queued = []
    }

    func closePrinting() {
        let session = PrintSession.shared
        guard session.isOpen else { return }
        session.isOpen = false
        let indexes = session.queued
        session.queued = []
        guard !indexes.isEmpty else { return }
        renderAndPresent(cardIndexes: indexes)
    }

    func printCards(_ selection: PrintCardSelection) {
        let indexes: [Int]
        switch selection {
        case .current:
            indexes = [cardIndex]
        case .all:
            indexes = Array(stack.cards.indices)
        case .marked:
            indexes = stack.cards.indices.filter { stack.cards[$0].isMarked }
        case .count(let n):
            indexes = (0..<n).map { (cardIndex + $0) % max(1, stack.cards.count) }
        }
        let session = PrintSession.shared
        if session.isOpen {
            session.queued.append(contentsOf: indexes)
        } else {
            renderAndPresent(cardIndexes: indexes)
        }
    }

    func printText(_ text: String, title: String) {
        guard let pdf = PrintService.pdfData(text: text, title: title) else { return }
        onPresentPrint(pdf, title.isEmpty ? stack.name : title)
    }

    private func renderAndPresent(cardIndexes: [Int]) {
        guard let pdf = PrintService.pdfData(stack: stack, assets: assetsSnapshot(), cardIndexes: cardIndexes) else { return }
        onPresentPrint(pdf, stack.name)
    }

    /// `drag from … to …` with a paint tool: a scripted stroke on the current
    /// card's paint layer. (With any other tool, drag synthesis is unmodeled.)
    func drag(fromX: Int, fromY: Int, toX: Int, toY: Int) {
        // With the button/field tool, dragging MOVES the part under the start
        // point — HyperCard's scripted-authoring idiom
        // (`choose button tool` / `drag from loc of btn 1 to 100,100`).
        if chosenTool == "button" || chosenTool == "field" {
            movePart(kind: chosenTool, from: (fromX, fromY), to: (toX, toY))
            return
        }
        guard isDrawingToolChosen else { return }
        paintOnCard { canvas in
            let paint = PaintSession.shared
            let ink = PaintRasterizer.Ink(pattern: paint.pattern)
            let bounds = PaintRasterizer.dragBounds(from: (fromX, fromY), to: (toX, toY), centered: paint.centered)
            switch chosenTool {
            case "line", "curve":
                PaintRasterizer.line(&canvas, from: (fromX, fromY), to: (toX, toY), size: paint.lineSize, ink: ink)
            case "pencil":
                PaintRasterizer.line(&canvas, from: (fromX, fromY), to: (toX, toY), size: 1, ink: ink)
            case "brush":
                // The brush paints a wider stroke; brush shapes aren't modeled.
                PaintRasterizer.line(&canvas, from: (fromX, fromY), to: (toX, toY), size: max(2, paint.lineSize * 2), ink: ink)
            case "eraser":
                // HyperCard's eraser is a 16×16 block.
                PaintRasterizer.line(&canvas, from: (fromX - 8, fromY - 8), to: (toX - 8, toY - 8), size: 16, ink: .erase)
            case "rect", "rectangle", "regular polygon", "reg poly":
                PaintRasterizer.rect(&canvas, bounds: bounds, size: paint.lineSize, ink: ink, filled: paint.filled)
            case "round rect", "roundrect":
                PaintRasterizer.roundRect(&canvas, bounds: bounds, size: paint.lineSize, ink: ink, filled: paint.filled)
            case "oval":
                PaintRasterizer.oval(&canvas, bounds: bounds, size: paint.lineSize, ink: ink, filled: paint.filled)
            default:
                break
            }
        }
    }

    private func movePart(kind: String, from: (x: Int, y: Int), to: (x: Int, y: Int)) {
        let px = Double(from.x), py = Double(from.y)
        func hitIndex(in parts: [Part]) -> Int? {
            for index in parts.indices.reversed() {
                let part = parts[index]
                guard part.kind.word == kind, part.isVisible else { continue }
                let f = part.frame
                if px >= f.x, px <= f.x + f.width, py >= f.y, py <= f.y + f.height { return index }
            }
            return nil
        }
        func moved(_ frame: PartFrame) -> PartFrame {
            var f = frame
            f.x = Double(to.x) - f.width / 2
            f.y = Double(to.y) - f.height / 2
            return f
        }
        let card = stack.cards[cardIndex]
        if let index = hitIndex(in: card.parts) {
            stackBinding.wrappedValue.cards[cardIndex].parts[index].frame = moved(card.parts[index].frame)
            return
        }
        if let backgroundIndex = stack.backgrounds.firstIndex(where: { $0.id == card.backgroundID }),
           let index = hitIndex(in: stack.backgrounds[backgroundIndex].parts) {
            let frame = stack.backgrounds[backgroundIndex].parts[index].frame
            stackBinding.wrappedValue.backgrounds[backgroundIndex].parts[index].frame = moved(frame)
        }
    }

    /// Renders one drawing operation onto the current card's paint layer,
    /// storing the updated PNG (and the asset name, first time) back on the
    /// document.
    private func paintOnCard(_ draw: (inout PaintRasterizer.Canvas) -> Void) {
        let width = Int(stack.cardSize.width), height = Int(stack.cardSize.height)
        guard width > 0, height > 0 else { return }
        let existing = stack.cards[cardIndex].paintImageAsset
        var canvas = PaintRasterizer.canvas(from: existing.flatMap(assetData), width: width, height: height)
        draw(&canvas)
        guard let png = PaintRasterizer.png(from: canvas) else { return }
        let assetName = existing ?? "scripted-paint-\(stack.cards[cardIndex].id.uuidString).png"
        onAssetWrite(assetName, png)
        if existing == nil {
            stackBinding.wrappedValue.cards[cardIndex].paintImageAsset = assetName
        }
    }

    func click(x: Int, y: Int) {
        // A paint tool clicks paint, not parts: the bucket floods, the
        // pencil/brush dot.
        if isDrawingToolChosen {
            let paint = PaintSession.shared
            let ink = PaintRasterizer.Ink(pattern: paint.pattern)
            switch chosenTool {
            case "bucket":
                paintOnCard { PaintRasterizer.floodFill(&$0, at: (x, y), ink: ink) }
            case "pencil":
                paintOnCard { PaintRasterizer.line(&$0, from: (x, y), to: (x, y), size: 1, ink: ink) }
            case "brush":
                paintOnCard { PaintRasterizer.line(&$0, from: (x, y), to: (x, y), size: max(2, paint.lineSize * 2), ink: ink) }
            case "eraser":
                paintOnCard { PaintRasterizer.line(&$0, from: (x - 8, y - 8), to: (x - 8, y - 8), size: 16, ink: .erase) }
            default:
                break
            }
            return
        }
        let px = Double(x), py = Double(y)
        func hit(_ parts: [Part], matching: ((Part) -> Bool)? = nil) -> Part? {
            // Topmost first (last in z-order).
            for part in parts.reversed() where part.isVisible {
                if let matching, !matching(part) { continue }
                let f = part.frame
                if px >= f.x, px <= f.x + f.width, py >= f.y, py <= f.y + f.height { return part }
            }
            return nil
        }
        let card = stack.cards[cardIndex]
        let background = stack.backgrounds.first { $0.id == card.backgroundID }
        // With a part tool chosen, the click selects (arming Clear Button/
        // Clear Field) rather than dispatching the part's mouseUp.
        let selecting: ((Part) -> Bool)? = switch chosenTool {
        case "button": { if case .button = $0.kind { true } else { false } }
        case "field": { if case .field = $0.kind { true } else { false } }
        default: nil
        }
        if let selecting {
            let target = hit(card.parts, matching: selecting)
                ?? background.flatMap { hit($0.parts, matching: selecting) }
            selectedPartID = target?.id
            return
        }
        if let part = hit(card.parts) { onClickPart(part); return }
        if let part = background.flatMap({ hit($0.parts) }) { onClickPart(part) }
        // Nothing under the point — a click on empty card is a no-op here.
    }

    func reorderCards(_ order: [Int]) throws {
        let cards = stack.cards
        guard order.count == cards.count, Set(order) == Set(0..<cards.count) else {
            throw HostError("Sort produced an invalid card order.")
        }
        // Keep the user on the same card after the reorder.
        let currentID = cards.indices.contains(cardIndex) ? cards[cardIndex].id : nil
        stackBinding.wrappedValue.cards = order.map { cards[$0] }
        if let currentID, let newIndex = stackBinding.wrappedValue.cards.firstIndex(where: { $0.id == currentID }) {
            currentCardIndex.wrappedValue = newIndex
        }
    }

    // MARK: - HyperTalkHost

    func setScreenLocked(_ locked: Bool) {
        isScreenLocked = locked
        guard !locked, let pending = pendingLockedDestination else { return }
        pendingLockedDestination = nil
        switch pending {
        case .home: onGoHome()
        case .stack(let name, let card): onGoStack(name, card)
        default: break
        }
    }

    func goToCard(_ destination: GoDestination, effects: [ScreenEffect]) async throws {
        // Cross-window navigation defers while the screen is locked, so a
        // `lock screen … go home … pop card … unlock screen` peek nets to no
        // window switch (the stack stays frontmost).
        if case .home = destination {
            if isScreenLocked { pendingLockedDestination = .home } else { onGoHome() }
            return
        }
        if case .stack(let name, let card) = destination {
            if isScreenLocked { pendingLockedDestination = destination } else { onGoStack(name, card) }
            return
        }
        // In-stack navigation (including `pop card`) supersedes a deferred peek.
        if isScreenLocked { pendingLockedDestination = nil }
        let count = stack.cards.count
        guard count > 0 else { throw HostError("This stack has no cards.") }
        // `go back` returns to the last card the script navigated away from.
        if case .back = destination {
            guard let id = VisitHistory.shared.ids.popLast(),
                  let index = stack.cards.firstIndex(where: { String($0.scriptID) == id }) else {
                return // nothing to go back to — harmless, as in HyperCard
            }
            onNavigate(index, effects)
            await settle(after: effects)
            return
        }
        let target: Int
        switch destination {
        case .next:
            target = (cardIndex + 1) % count
        case .previous:
            target = (cardIndex + count - 1) % count
        case .first:
            target = 0
        case .last:
            target = count - 1
        case .number(let number):
            guard (1...count).contains(number) else {
                throw HostError("There is no card \(number) — this stack has \(count) card\(count == 1 ? "" : "s").")
            }
            target = number - 1
        case .named(let name):
            guard let index = stack.cards.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                // No card by that name: HyperCard's `go "X"` then resolves a
                // *stack* named X. Hand off to the Stack Library (which opens it
                // or prompts to locate it), matching the DateBook suite's
                // `go to "Address"` / `go to "Phone"` cross-stack jumps.
                if isScreenLocked { pendingLockedDestination = .stack(name: name, card: nil) }
                else { onGoStack(name, nil) }
                return
            }
            target = index
        case .id(let id):
            let wanted = id.trimmingCharacters(in: .whitespaces)
            guard let index = stack.cards.firstIndex(where: { String($0.scriptID) == wanted }) else {
                throw HostError("There is no card with id \(id).")
            }
            target = index
        case .inBackground, .markedCard, .relativeMarked:
            target = try resolveCardIndex(destination)
            // The script selection doesn't survive leaving the card.
            if target != cardIndex { clearSelection() }
        case .home, .back, .stack:
            return // handled above / not a same-stack destination
        }
        // Remember where we came from so a later `go back` can return here.
        VisitHistory.shared.ids.append(String(stack.cards[cardIndex].scriptID))
        // The view owns the animated transition (see ContentView.navigate).
        onNavigate(target, effects)
        await settle(after: effects)
    }

    /// Holds the script while a transition plays, as HyperCard did. The view
    /// swaps the card-index binding a runloop tick into the animation, so the
    /// pause is also what lets a chained `go next cd` compute from the card
    /// actually showing — five dissolves in a repeat loop land on five
    /// successive cards instead of collapsing into one step.
    private func settle(after effects: [ScreenEffect]) async {
        guard let effect = effects.first else { return }
        try? await Task.sleep(for: .seconds(effect.duration + 0.05))
    }

    func count(_ countable: Countable) throws -> Int {
        switch countable {
        case .cards(let scope):
            guard let scope else { return stack.cards.count }
            let wanted: UUID?
            switch scope {
            case .current:
                wanted = stack.cards[cardIndex].backgroundID
            case .reference(let reference):
                wanted = backgroundID(for: reference)
            }
            guard let wanted else {
                throw HostError("There is no such background.")
            }
            return stack.cards.count { $0.backgroundID == wanted }
        case .backgrounds:
            return stack.backgrounds.count
        case .markedCards:
            return stack.cards.count { $0.isMarked }
        case .parts(let kind, let domain):
            let card = stack.cards[cardIndex]
            let cardParts = card.parts
            let backgroundParts = stack.backgrounds.first(where: { $0.id == card.backgroundID })?.parts ?? []
            func matching(_ parts: [Part]) -> Int {
                if kind == "part" {
                    return parts.filter { $0.kind.word == "button" || $0.kind.word == "field" }.count
                }
                return parts.filter { $0.kind.word == kind }.count
            }
            switch domain {
            case .card: return matching(cardParts)
            case .background: return matching(backgroundParts)
            case .any: return matching(cardParts) + matching(backgroundParts)
            }
        }
    }

    func fieldText(_ reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, onCard: GoDestination?) throws -> String {
        let ci = try onCard.map { try resolveCardIndex($0) } ?? cardIndex
        let location = try locateField(reference: reference, domain: domain, cardIndex: ci)
        let part = fieldPart(at: location)
        guard case .field(let properties) = part.kind else {
            throw HostError("That part is not a field.")
        }
        // A non-sharedText background field's text is per card (the overlay);
        // a missing entry reads empty, as in HyperCard.
        if case .background = location, !properties.sharedText {
            return stack.cards[ci].backgroundFieldContent[part.id.uuidString]?.text ?? ""
        }
        return properties.text
    }

    func setFieldText(_ reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, onCard: GoDestination?, to text: String) throws {
        let ci = try onCard.map { try resolveCardIndex($0) } ?? cardIndex
        let location = try locateField(reference: reference, domain: domain, cardIndex: ci)
        let part = fieldPart(at: location)
        guard case .field(var properties) = part.kind else {
            throw HostError("That part is not a field.")
        }
        if case .background = location, !properties.sharedText {
            var content = stack.cards[ci].backgroundFieldContent[part.id.uuidString] ?? BackgroundFieldContent()
            content.text = text
            stackBinding.wrappedValue.cards[ci].backgroundFieldContent[part.id.uuidString] = content
            return
        }
        properties.text = text
        switch location {
        case .card(let cardIndex, let partIndex):
            stackBinding.wrappedValue.cards[cardIndex].parts[partIndex].kind = .field(properties)
        case .background(let backgroundIndex, let partIndex):
            stackBinding.wrappedValue.backgrounds[backgroundIndex].parts[partIndex].kind = .field(properties)
        }
    }

    /// Where a field lives, including which card — so `field "X" of prev card`
    /// can read/write without navigating.
    private enum RemoteFieldLocation {
        case card(cardIndex: Int, partIndex: Int)
        case background(backgroundIndex: Int, partIndex: Int)
    }

    private func fieldPart(at location: RemoteFieldLocation) -> Part {
        switch location {
        case .card(let cardIndex, let partIndex): stack.cards[cardIndex].parts[partIndex]
        case .background(let backgroundIndex, let partIndex): stack.backgrounds[backgroundIndex].parts[partIndex]
        }
    }

    private func locateField(reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, cardIndex ci: Int) throws -> RemoteFieldLocation {
        let card = stack.cards[ci]
        let backgroundIndex = stack.backgrounds.firstIndex(where: { $0.id == card.backgroundID })
        func onCard() -> RemoteFieldLocation? {
            index(ofKind: "field", matching: reference, in: card.parts).map { .card(cardIndex: ci, partIndex: $0) }
        }
        func onBackground() -> RemoteFieldLocation? {
            guard let backgroundIndex,
                  let partIndex = index(ofKind: "field", matching: reference, in: stack.backgrounds[backgroundIndex].parts) else { return nil }
            return .background(backgroundIndex: backgroundIndex, partIndex: partIndex)
        }
        // Honor the requested layer first, then fall back to the other —
        // kept for documents from before background fields became true shared
        // parts (their copies live on cards), and for loose references.
        if domain != .background, let found = onCard() { return found }
        if domain != .card, let found = onBackground() { return found }
        if let found = onCard() ?? onBackground() { return found }
        switch reference {
        case .named(let name): throw HostError("There is no field named \"\(name)\" on that card.")
        case .number(let number): throw HostError("There is no field \(number) on that card.")
        case .id(let id): throw HostError("There is no field with id \(id) on that card.")
        }
    }

    /// Resolves a card destination (from `field … of <card>`) to an index.
    func setMarked(_ marked: Bool, card: GoDestination?) throws {
        let index = try card.map { try resolveCardIndex($0) } ?? cardIndex
        stackBinding.wrappedValue.cards[index].isMarked = marked
    }

    /// `delete [the] <card>` — remove a card (nil = the current one), guarding
    /// the last remaining card and cantDelete, then land on the nearest card.
    func deleteCard(_ card: GoDestination?) throws {
        let index = try card.map { try resolveCardIndex($0) } ?? cardIndex
        guard stack.cards.count > 1 else { throw HostError("The last remaining card can't be deleted.") }
        guard !stack.cards[index].cantDelete else { throw HostError("This card can't be deleted.") }
        let current = cardIndex   // before removal — it clamps to the array
        stackBinding.wrappedValue.cards.remove(at: index)
        let next = min(current > index ? current - 1 : current, stackBinding.wrappedValue.cards.count - 1)
        onNavigate(max(0, next), [])
    }

    /// `delete button 1` / `delete card field "x"` / `delete image 2` — remove
    /// a part, honoring the requested layer first (as lookups do).
    func deletePart(_ object: HyperTalkObject) throws {
        guard case .part(let kind, let domain, let reference, let onCard) = object else {
            throw HostError("That isn't a deletable object.")
        }
        let ci = try onCard.map { try resolveCardIndex($0) } ?? cardIndex
        let card = stack.cards[ci]
        let backgroundIndex = stack.backgrounds.firstIndex { $0.id == card.backgroundID }
        func cardHit() -> Int? { index(ofKind: kind, matching: reference, in: card.parts) }
        func backgroundHit() -> Int? {
            guard let backgroundIndex else { return nil }
            return index(ofKind: kind, matching: reference, in: stack.backgrounds[backgroundIndex].parts)
        }
        if domain != .background, let i = cardHit() {
            stackBinding.wrappedValue.cards[ci].parts.remove(at: i); return
        }
        if domain != .card, let backgroundIndex, let i = backgroundHit() {
            stackBinding.wrappedValue.backgrounds[backgroundIndex].parts.remove(at: i); return
        }
        if let i = cardHit() {
            stackBinding.wrappedValue.cards[ci].parts.remove(at: i); return
        }
        if let backgroundIndex, let i = backgroundHit() {
            stackBinding.wrappedValue.backgrounds[backgroundIndex].parts.remove(at: i); return
        }
        throw HostError("There is no such \(kind) here.")
    }

    /// `delete background <ref>` — only a background no card uses can go.
    func deleteBackground(_ reference: HyperTalkObject.Reference) throws {
        guard let id = backgroundID(for: reference) else { throw HostError("There is no such background.") }
        guard !stack.cards.contains(where: { $0.backgroundID == id }) else {
            throw HostError("That background still has cards — delete them first.")
        }
        stackBinding.wrappedValue.backgrounds.removeAll { $0.id == id }
    }

    /// Merge scaffolding: a background with NO fields yet gets one per key —
    /// stacked single-line fields, with a "text" key given the tall multiline
    /// slot. A designed background (any field present) is left untouched.
    /// A missing background is left for makeCard to report.
    func scaffoldBackgroundFields(keys: [String], background: HyperTalkObject.Reference?) throws {
        let targetBackground = background.flatMap { backgroundID(for: $0) }
            ?? (background == nil ? stack.cards[cardIndex].backgroundID : nil)
        guard let targetBackground,
              let backgroundIndex = stack.backgrounds.firstIndex(where: { $0.id == targetBackground }),
              !keys.isEmpty,
              !stack.backgrounds[backgroundIndex].parts.contains(where: {
                  if case .field = $0.kind { return true } else { return false }
              }) else { return }
        // The layout: margins all around, a short row per key, and the
        // remaining height to a key named "text" (the feed/article body).
        let margin = 20.0, rowHeight = 32.0, gap = 10.0
        let width = stack.cardSize.width - margin * 2
        let shortRows = Double(keys.filter { $0.lowercased() != "text" }.count)
        let tallHeight = max(100, stack.cardSize.height - margin * 2 - shortRows * (rowHeight + gap))
        var y = margin
        for key in keys {
            let isBody = key.lowercased() == "text"
            var part = Part(id: UUID(), name: key,
                            frame: PartFrame(x: margin, y: y, width: width,
                                             height: isBody ? tallHeight : rowHeight),
                            script: "",
                            kind: .field(FieldPart(text: "", placeholder: "", isMultiline: isBody)))
            part.scriptID = stackBinding.wrappedValue.claimScriptID()
            stackBinding.wrappedValue.backgrounds[backgroundIndex].parts.append(part)
            y += (isBody ? tallHeight : rowHeight) + gap
        }
    }


    /// `the selectedButton of family N` — the hilited member on the layer
    /// (bare/card-qualified = the card layer; bkgnd-qualified = background),
    /// as "card button <n>" / "bkgnd button <n>" by button number. Card and
    /// background families are distinct namespaces (HyperCard Help's rule).
    func selectedButtonOfFamily(_ family: Int, domain: HyperTalkObject.PartDomain, onCard: GoDestination?) -> String {
        guard family > 0, let layer = familyLayer(domain: domain, onCard: onCard) else { return "" }
        var buttonNumber = 0
        for part in layer.parts {
            guard case .button(let button) = part.kind else { continue }
            buttonNumber += 1
            if button.family == family, button.hilite {
                return "\(layer.isBackground ? "bkgnd" : "card") button \(buttonNumber)"
            }
        }
        return ""
    }

    func familyExists(_ family: Int, domain: HyperTalkObject.PartDomain, onCard: GoDestination?) -> Bool {
        guard family > 0, let layer = familyLayer(domain: domain, onCard: onCard) else { return false }
        return layer.parts.contains { part in
            if case .button(let button) = part.kind { return button.family == family }
            return false
        }
    }

    private func familyLayer(domain: HyperTalkObject.PartDomain, onCard: GoDestination?) -> (parts: [Part], isBackground: Bool)? {
        let index: Int
        if let onCard {
            guard let resolved = try? resolveCardIndex(onCard) else { return nil }
            index = resolved
        } else {
            index = cardIndex
        }
        guard stack.cards.indices.contains(index) else { return nil }
        let card = stack.cards[index]
        if domain == .background {
            guard let background = stack.backgrounds.first(where: { $0.id == card.backgroundID }) else { return nil }
            return (background.parts, true)
        }
        return (card.parts, false)
    }

    /// `import picture from url … [into image <ref>]` — fetch the bytes
    /// (behind the same per-host consent as the url container), store them
    /// as a document asset, and point the image part at it. Nil target = a
    /// new centered image part on the current card. Returns the part's id.
    func importPicture(fromURL urlString: String, into target: HyperTalkObject?) async throws -> Int {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let webHost = url.host else {
            throw HostError("import picture needs a web address, like \"https://example.com/photo.png\".")
        }
        guard await isNetworkAllowed(host: webHost) else {
            throw HostError("\"\(stack.name)\" isn't allowed to connect to \(webHost).")
        }
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(from: url)
        } catch {
            throw HostError("Couldn't fetch the picture: \(error.localizedDescription)")
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw HostError("That url didn't return a picture.")
        }
        let ext = ["png", "jpg", "jpeg", "gif", "heic", "webp"].contains(url.pathExtension.lowercased())
            ? url.pathExtension.lowercased() : "png"
        let assetName = "imported-\(UUID().uuidString).\(ext)"
        onAssetWrite(assetName, data)
        if let target {
            guard case .part(let kind, let domain, let reference, let onCard) = target, kind == "image" else {
                throw HostError("'import picture … into' needs an image part, like image \"Photo\".")
            }
            let location = try locatePart(kind: "image", domain: domain, reference: reference, onCard: onCard)
            setKind(.image(ImagePart(assetName: assetName)), at: location)
            return part(at: location).scriptID
        }
        let width = min(200.0, stack.cardSize.width - 40)
        let height = min(150.0, stack.cardSize.height - 40)
        var newPart = Part(id: UUID(), name: "",
                           frame: PartFrame(x: (stack.cardSize.width - width) / 2,
                                            y: (stack.cardSize.height - height) / 2,
                                            width: width, height: height),
                           script: "", kind: .image(ImagePart(assetName: assetName)))
        newPart.scriptID = stackBinding.wrappedValue.claimScriptID()
        stackBinding.wrappedValue.cards[cardIndex].parts.append(newPart)
        return newPart.scriptID
    }

    /// `make a card [using background <ref>]` — append a card at the end of
    /// the stack (nil background = the current card's), without navigating.
    func makeCard(background: HyperTalkObject.Reference?) throws -> Int {
        var targetBackground = stack.cards[cardIndex].backgroundID
        if let background {
            guard let found = backgroundID(for: background) else {
                throw HostError("There is no such background to make the card with.")
            }
            targetBackground = found
        }
        var card = Card(id: UUID(), name: "", backgroundID: targetBackground, script: "", parts: [])
        card.scriptID = stackBinding.wrappedValue.claimScriptID()
        stackBinding.wrappedValue.cards.append(card)
        return stackBinding.wrappedValue.cards.count
    }

    /// `delete [the] [card|bkgnd] picture [of <card>]` — remove the paint
    /// layer's assets (the drawing and its rendered image).
    func clearPicture(background: Bool, card: GoDestination?) throws {
        let ci = try card.map { try resolveCardIndex($0) } ?? cardIndex
        if background {
            let bgID = stack.cards[ci].backgroundID
            guard let bi = stack.backgrounds.firstIndex(where: { $0.id == bgID }) else { return }
            stackBinding.wrappedValue.backgrounds[bi].paintImageAsset = nil
            stackBinding.wrappedValue.backgrounds[bi].paintDrawingAsset = nil
        } else {
            stackBinding.wrappedValue.cards[ci].paintImageAsset = nil
            stackBinding.wrappedValue.cards[ci].paintDrawingAsset = nil
        }
    }

    func beginUsingStack(_ name: String) { UsingStackStore.shared.begin(name) }
    func endUsingStack(_ name: String) { UsingStackStore.shared.end(name) }
    func inUseStackScripts() -> [(name: String, source: String)] { UsingStackStore.shared.stacks }

    func adjacentBackgroundCardNumber(forward: Bool) -> Int? {
        let cards = stack.cards
        guard !cards.isEmpty else { return nil }
        // Distinct backgrounds in stack (card) order.
        var order: [UUID] = []
        for c in cards where !order.contains(c.backgroundID) { order.append(c.backgroundID) }
        guard order.count > 1 else { return nil }
        let current = cards[cardIndex].backgroundID
        guard let pos = order.firstIndex(of: current) else { return nil }
        let target = forward ? order[(pos + 1) % order.count]
                             : order[(pos - 1 + order.count) % order.count]
        guard let i = cards.firstIndex(where: { $0.backgroundID == target }) else { return nil }
        return i + 1
    }

    private func resolveCardIndex(_ destination: GoDestination) throws -> Int {
        let count = stack.cards.count
        guard count > 0 else { throw HostError("This stack has no cards.") }
        switch destination {
        case .next: return (cardIndex + 1) % count
        case .previous: return (cardIndex + count - 1) % count
        case .first: return 0
        case .last: return count - 1
        case .number(let number):
            guard (1...count).contains(number) else { throw HostError("There is no card \(number).") }
            return number - 1
        case .named(let name):
            guard let index = stack.cards.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw HostError("There is no card named \"\(name)\".")
            }
            return index
        case .id(let id):
            let wanted = id.trimmingCharacters(in: .whitespaces)
            guard let index = stack.cards.firstIndex(where: { String($0.scriptID) == wanted }) else {
                throw HostError("There is no card with id \(id).")
            }
            return index
        case .inBackground(let inner, let background):
            let indices: [Int]
            if let background {
                indices = stack.cards.indices.filter {
                    backgroundName(ofCardAt: $0)?.caseInsensitiveCompare(background) == .orderedSame
                }
                guard !indices.isEmpty else {
                    throw HostError("There is no background named \"\(background)\".")
                }
            } else {
                // Unnamed (`of bkgnd` / `of this bkgnd`) — the current card's.
                let wanted = stack.cards[cardIndex].backgroundID
                indices = stack.cards.indices.filter { stack.cards[$0].backgroundID == wanted }
            }
            switch inner {
            case .first: return indices.first!
            case .last: return indices.last!
            case .number(let number):
                guard (1...indices.count).contains(number) else {
                    throw HostError("There is no card \(number) in that background.")
                }
                return indices[number - 1]
            case .named(let name):
                guard let index = indices.first(where: { stack.cards[$0].name.caseInsensitiveCompare(name) == .orderedSame }) else {
                    throw HostError("There is no card named \"\(name)\" in that background.")
                }
                return index
            case .id(let id):
                let wanted = id.trimmingCharacters(in: .whitespaces)
                guard let index = indices.first(where: { String(stack.cards[$0].scriptID) == wanted }) else {
                    throw HostError("There is no card with id \(id) in that background.")
                }
                return index
            default:
                throw HostError("That card reference isn't supported within a background.")
            }
        case .markedCard(let n):
            let marked = stack.cards.indices.filter { stack.cards[$0].isMarked }
            guard (1...marked.count).contains(n) else { throw HostError("There is no marked card \(n).") }
            return marked[n - 1]
        case .relativeMarked(let forward):
            let marked = stack.cards.indices.filter { stack.cards[$0].isMarked }
            guard !marked.isEmpty else { throw HostError("There are no marked cards.") }
            return forward ? (marked.first { $0 > cardIndex } ?? marked.first!)
                           : (marked.last { $0 < cardIndex } ?? marked.last!)
        case .home, .back, .stack:
            throw HostError("Can't address a field of that card.")
        }
    }

    /// Resolves a background named by a count scope (`bg "Paths"`, `bg 2`,
    /// `bg id 7`) to its model id. Nil when there's no such background.
    private func backgroundID(for reference: HyperTalkObject.Reference) -> UUID? {
        switch reference {
        case .named(let name):
            return stack.backgrounds.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id
        case .number(let number):
            guard (1...stack.backgrounds.count).contains(number) else { return nil }
            return stack.backgrounds[number - 1].id
        case .id(let id):
            let wanted = id.trimmingCharacters(in: .whitespaces)
            return stack.backgrounds.first { String($0.scriptID) == wanted }?.id
        }
    }

    private func backgroundName(ofCardAt index: Int) -> String? {
        let backgroundID = stack.cards[index].backgroundID
        return stack.backgrounds.first(where: { $0.id == backgroundID })?.name
    }

    func showMessage(_ text: String) {
        onMessage(text)
    }

    /// `the clickLine` / `the clickText` / `the clickLoc` — the last click.
    func clickValue(_ field: ClickField) -> String {
        switch field {
        case .line: return ClickRecord.shared.line
        case .text: return ClickRecord.shared.text
        case .chunk: return ClickRecord.shared.chunk
        case .location:
            guard let point = ClickRecord.shared.clickLocation else { return "" }
            return "\(Int(point.x.rounded())),\(Int(point.y.rounded()))"
        }
    }

    /// `the mouse` — down while a browse-mode press is held.
    func mouseIsDown() -> Bool {
        MouseState.shared.isDown
    }

    /// `the mouseClick` — true once for each browse-mode click since the last
    /// read (consumed here). Cleared at dispatch so the launching click is
    /// excluded.
    func consumeMouseClick() -> Bool {
        ClickRecord.shared.consumeClick()
    }

    /// `the mouseLoc` — the pointer's card location, live while a press drags
    /// (between presses: where the last press ended; hover isn't tracked).
    func mouseLocation() -> (x: Int, y: Int)? {
        let point = MouseState.shared.location
        return (Int(point.x.rounded()), Int(point.y.rounded()))
    }

    /// `play <voice> …` — the stack's imported `snd ` sound by (lowercased)
    /// name, or the synthesized fallback voice when there's no such sound.
    func play(voice: String, tempo: Double, notes: [PlayNote]) {
        let sound = stack.sounds[voice.lowercased()]
        let wav = sound.flatMap { assetData($0.asset) }
        SoundPlayer.shared.play(name: voice, wav: wav, baseNote: sound?.baseNote ?? 60, tempo: tempo, notes: notes)
    }

    func stopPlay() {
        SoundPlayer.shared.stop()
    }

    /// `the sound` — the playing voice's name, "done" when idle.
    func playingSoundName() -> String {
        SoundPlayer.shared.playingName
    }

    /// The current card's card/background/stack scripts, for the interpreter to
    /// re-read after navigation so the message path follows the moving card.
    /// Mirrors the tail ContentView.scriptPath builds for the initial dispatch.
    func systemScriptLayers() -> [ScriptLayer]? {
        systemScriptLayers(forCardAt: cardIndex)
    }

    /// The card/background/stack layers for the card at `index`.
    private func systemScriptLayers(forCardAt index: Int) -> [ScriptLayer]? {
        guard stack.cards.indices.contains(index) else { return nil }
        let card = stack.cards[index]
        var layers: [ScriptLayer] = [
            ScriptLayer(name: "card \"\(card.name)\" script", source: card.script, object: .thisCard)
        ]
        if let background = stack.backgrounds.first(where: { $0.id == card.backgroundID }) {
            layers.append(ScriptLayer(name: "background script", source: background.script, object: .thisBackground))
        }
        layers.append(ScriptLayer(name: "stack script", source: stack.script, object: .thisStack))
        return layers
    }

    /// The full dispatch path for `send <msg> to <object>` when the target
    /// isn't on the running path: the object's own script, then the layers
    /// beneath it — a part falls through its card/background/stack; another
    /// card falls through its own background and the stack.
    func scriptLayers(for object: HyperTalkObject) -> [ScriptLayer]? {
        switch object {
        case .part(let kind, let domain, let reference, let onCard):
            guard let location = try? locatePart(kind: kind, domain: domain, reference: reference, onCard: onCard) else { return nil }
            let target = part(at: location)
            let layerDomain: HyperTalkObject.PartDomain = if case .background = location { .background } else { .card }
            let layer = ScriptLayer(
                name: "\(kind) \"\(target.name)\" script",
                source: target.script,
                object: .part(kind: kind, domain: layerDomain, reference: .id(String(target.scriptID)), onCard: nil)
            )
            return [layer] + (systemScriptLayers() ?? [])
        case .card(let destination):
            guard let index = try? resolveCardIndex(destination) else { return nil }
            return systemScriptLayers(forCardAt: index)
        case .thisCard, .thisBackground, .thisStack:
            // Already on every running path; the interpreter dispatches there
            // directly, so this is only a fallback for pathless contexts.
            guard let system = systemScriptLayers() else { return nil }
            if let start = system.firstIndex(where: { $0.object == object }) {
                return Array(system[start...])
            }
            return nil
        }
    }

    // MARK: - Script selection (`select` / the selected* readers)

    func setSelection(field reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, start: Int, end: Int) throws {
        let location = try locatePart(kind: "field", domain: domain, reference: reference)
        let selected = part(at: location)
        let session = SelectionSession.shared
        session.partID = selected.id
        session.scriptID = selected.scriptID
        if case .background = location { session.layer = "bkgnd" } else { session.layer = "card" }
        let length = fieldContents(of: selected).count
        let lo = max(0, min(start, length))
        session.range = lo..<max(lo, min(end, length))
        onSelection(FindHighlight(partID: selected.id, range: session.range))
    }

    func clearSelection() {
        SelectionSession.shared.clear()
        onSelection(nil)
    }

    func selectionValue(_ component: SelectionComponent) -> String {
        let session = SelectionSession.shared
        guard session.partID != nil, let selected = partWithScriptID(session.scriptID) else { return "" }
        let descriptor = "\(session.layer) field id \(session.scriptID)"
        let text = Array(fieldContents(of: selected))
        let range = session.range.clamped(to: 0..<text.count)
        switch component {
        case .field:
            return descriptor
        case .text:
            return String(text[range])
        case .chunk:
            return "char \(range.lowerBound + 1) to \(range.upperBound) of \(descriptor)"
        case .line:
            let startLine = text[0..<range.lowerBound].count { $0 == "\n" } + 1
            let endLine = text[0..<max(range.lowerBound, range.upperBound == 0 ? 0 : range.upperBound - 1)]
                .count { $0 == "\n" } + 1
            return startLine == endLine
                ? "line \(startLine) of \(descriptor)"
                : "line \(startLine) to \(endLine) of \(descriptor)"
        }
    }

    private func fieldContents(of part: Part) -> String {
        if case .field(let properties) = part.kind {
            // Only non-sharedText background fields have overlay entries;
            // card fields fall through to their own text.
            if !properties.sharedText,
               let content = stack.cards[cardIndex].backgroundFieldContent[part.id.uuidString] {
                return content.text
            }
            return properties.text
        }
        return ""
    }

    private func partWithScriptID(_ id: Int) -> Part? {
        let card = stack.cards[cardIndex]
        if let part = card.parts.first(where: { $0.scriptID == id }) { return part }
        return stack.backgrounds.first { $0.id == card.backgroundID }?
            .parts.first { $0.scriptID == id }
    }

    /// The XCMD/XFCN names recorded at import — calls to them no-op rather
    /// than raising "Can't understand" (the compiled code can't run here).
    /// Names we shim natively are always treated as externals — even when the
    /// stack doesn't carry the XCMD resource (stacks often rely on these being
    /// installed in Home / the app). So `Flash`/`SpeakText`/`PopMenu`/… route
    /// to callExternal rather than erroring "Can't understand".
    static let builtinExternals: Set<String> = [
        "popmenu", "popupmenu", "hpopupmenu", "filename", "newfilename",
        "fontexists", "flash", "flasher", "flashrect", "speaktext", "speak",
        "palette", "newpalette", "generalpalette", "audiopalette", "fieldpalette",
    ]

    func isExternalName(_ name: String) -> Bool {
        Self.builtinExternals.contains(name.lowercased())
            || stack.externalCommands.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    func modifierKey(_ name: String) -> String {
        #if canImport(AppKit)
        let flags = NSEvent.modifierFlags
        let down = switch name {
        case "optionkey": flags.contains(.option)
        case "shiftkey": flags.contains(.shift)
        case "commandkey", "cmdkey": flags.contains(.command)
        case "controlkey": flags.contains(.control)
        default: false
        }
        return down ? "down" : "up"
        #else
        return "up"
        #endif
    }

    func beep() {
        Beeper.shared.beep()
    }

    // MARK: - XCMD/XFCN native shims

    /// Native implementations of the popular externals (corpus scan 2026-10-07:
    /// FileName ×11, PopMenu ×9, NewFileName ×9, FontExists ×5 — the rest is a
    /// 1–2-stack tail). Unknown names return nil → accepted-and-ignored.
    func callExternal(_ name: String, arguments: [String]) async throws -> String? {
        switch name.lowercased() {
        case "popmenu", "popupmenu", "hpopupmenu":
            // Eric Celeste's popMenu.XFCN (1988, the Culture stacks):
            // PopMenu(top, left, defaultLine, itemList) — items are comma-
            // separated, "text|metas" carries Mac menu metacharacters
            // ("-|(" = disabled separator). Returns empty when dismissed, else
            // "line,text,level,text" — scripts read item 4 (the chosen text).
            // A 1–2 argument call is the generic (itemList[, defaultLine]) form.
            let list: String
            let defaultLine: Int
            if arguments.count >= 4 {
                list = arguments[3]
                defaultLine = Int(arguments[2]) ?? 0
            } else {
                list = arguments.first ?? ""
                defaultLine = arguments.count > 1 ? Int(arguments[1]) ?? 0 : 0
            }
            let rawItems = list.contains("\n") ? list.components(separatedBy: "\n")
                                                : list.components(separatedBy: ",")
            return await presentPopUpMenu(rawItems: rawItems, defaultLine: defaultLine)
        case "filename":
            // FileName([type]) — a file-open dialog; the chosen path or "" on
            // cancel (the result carries "Cancel", as the classic XFCN did).
            let picked = await onAnswerFile("Choose a file", arguments.first.flatMap { $0.isEmpty ? nil : $0 })
            return picked ?? ""
        case "newfilename":
            // NewFileName([prompt [, defaultName]]) — a save dialog.
            return await presentSavePanel(prompt: arguments.first ?? "",
                                          defaultName: arguments.count > 1 ? arguments[1] : "")
        case "palette", "newpalette", "generalpalette", "audiopalette", "fieldpalette":
            // The Palette XCMD opens a floating palette window from a PLTE
            // resource: `palette "Tuber","2,40"` (name, "h,v" loc). We register
            // the window so `the windows` / `there is a window "X"` / the
            // visible/loc properties behave; the visible panel is a later
            // increment. A command → returns "".
            guard let name = arguments.first, !name.isEmpty else { return "" }
            var loc: (Int, Int)? = nil
            if arguments.count > 1 {
                let n = arguments[1].split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                if n.count >= 2 { loc = (n[0], n[1]) }
            }
            let buttons = stack.palettes[name.lowercased()]?.buttons ?? []
            PaletteRegistry.shared.open(name, loc: loc, buttons: buttons)
            return ""
        case "flash", "flasher", "flashrect":
            // Flash.XCMD inverts the screen a few times (default 3; Flash(n)
            // takes a count; FlashRect ignores its rect args). A command, so
            // it returns "".
            let count = arguments.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.first ?? 3
            onFlash(max(1, min(count, 20)))
            return ""
        case "speaktext", "speak":
            // SpeakText.XCMD / Speak — read the text aloud via the system
            // speech synthesizer. A command; returns "".
            let text = arguments.first ?? ""
            if !text.isEmpty { Self.speak(text) }
            return ""
        case "fontexists":
            guard let fontName = arguments.first, !fontName.isEmpty else { return "false" }
            #if canImport(AppKit)
            let exists = NSFontManager.shared.availableFontFamilies.contains { $0.caseInsensitiveCompare(fontName) == .orderedSame }
            #else
            let exists = UIFont.familyNames.contains { $0.caseInsensitiveCompare(fontName) == .orderedSame }
            #endif
            return exists ? "true" : "false"
        default:
            return nil
        }
    }

    /// The system speech synthesizer for SpeakText — retained so an utterance
    /// isn't cut off when the host is released at the end of a dispatch.
    private static let speechSynthesizer = AVSpeechSynthesizer()

    private static func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        speechSynthesizer.speak(utterance)
    }

    /// Shows a pop-up menu at the mouse; returns Celeste's popMenu record
    /// "line,text,1,text" for the chosen item, or "" when dismissed.
    private func presentPopUpMenu(rawItems: [String], defaultLine: Int) async -> String {
        #if canImport(AppKit)
        let items = rawItems.filter { !$0.isEmpty }
        guard !items.isEmpty else { return "" }
        let menu = NSMenu()
        for (i, raw) in items.enumerated() {
            // "text|metas": classic menu metacharacters — "(" disables,
            // "-" (as the text) is a separator.
            let pieces = raw.components(separatedBy: "|")
            let title = pieces[0]
            let metas = pieces.count > 1 ? pieces[1] : ""
            if title == "-" { menu.addItem(.separator()); continue }
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.tag = i + 1
            if metas.contains("(") { item.isEnabled = false }
            if i + 1 == defaultLine { item.state = .on }
            menu.addItem(item)
        }
        menu.autoenablesItems = false
        let target = PopMenuTarget()
        for item in menu.items where !item.isSeparatorItem {
            item.target = target
            item.action = #selector(PopMenuTarget.pick(_:))
        }
        guard let window = NSApp.keyWindow, let contentView = window.contentView else { return "" }
        let location = contentView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let anchor = defaultLine > 0 && defaultLine <= menu.items.count ? menu.items[defaultLine - 1] : nil
        _ = menu.popUp(positioning: anchor, at: location, in: contentView)
        guard target.pickedTag > 0 else { return "" }
        let chosenTitle = menu.items.first { $0.tag == target.pickedTag }?.title ?? ""
        return "\(target.pickedTag),\(chosenTitle),1,\(chosenTitle)"
        #else
        return ""
        #endif
    }

    #if canImport(AppKit)
    /// Captures which pop-up item was chosen (NSMenu reports via action).
    private final class PopMenuTarget: NSObject {
        var pickedTag = 0
        @objc func pick(_ sender: NSMenuItem) { pickedTag = sender.tag }
    }
    #endif

    /// NSSavePanel for the NewFileName XFCN; the chosen path or "" on cancel.
    private func presentSavePanel(prompt: String, defaultName: String) async -> String {
        #if canImport(AppKit)
        let panel = NSSavePanel()
        if !prompt.isEmpty { panel.message = prompt }
        if !defaultName.isEmpty { panel.nameFieldStringValue = defaultName }
        let response = await panel.begin()
        guard response == .OK, let url = panel.url else { return "" }
        return url.path
        #else
        return ""
        #endif
    }

    // MARK: - File I/O

    /// Open files for `open/read/write/close file`: the buffered text, the
    /// read/write mark, and where the file lives on disk. Keyed by the
    /// script's path string, so close/read refer to the same open.
    private struct OpenFile {
        var characters: [Character]
        var mark: Int
        var url: URL
    }
    private var openFiles: [String: OpenFile] = [:]

    /// Where script-created files live: a "HyperTalk Files" folder in the
    /// app's container (sandbox-safe, no user grant needed). A classic
    /// colon path ("HD:Data:scores") maps to its last component.
    private func fileURL(for path: String) throws -> URL {
        let name = path.split(separator: ":").last.map(String.init) ?? path
        let safe = name.replacingOccurrences(of: "/", with: "-")
        guard !safe.isEmpty else { throw HostError("Can't open that file.") }
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("HyperTalk Files", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(safe)
    }

    func fileOpen(_ path: String) throws {
        let url = try fileURL(for: path)
        // Open creates the file if it doesn't exist, as in HyperCard. Classic
        // CR (and CRLF) line endings read as the model's \n.
        let raw = (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .macOSRoman)) ?? ""
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        openFiles[path] = OpenFile(characters: Array(text), mark: 0, url: url)
    }

    func fileClose(_ path: String) throws {
        guard let file = openFiles.removeValue(forKey: path) else { throw HostError("File not open.") }
        try String(file.characters).write(to: file.url, atomically: true, encoding: .utf8)
    }

    func clipboardContents() -> String {
        #if canImport(AppKit)
        return NSPasteboard.general.string(forType: .string) ?? ""
        #else
        return UIPasteboard.general.string ?? ""
        #endif
    }

    func setClipboardContents(_ text: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    func pictureExists(background: Bool) -> Bool {
        guard stack.cards.indices.contains(cardIndex) else { return false }
        let card = stack.cards[cardIndex]
        if background {
            guard let bg = stack.backgrounds.first(where: { $0.id == card.backgroundID }) else { return false }
            return bg.paintImageAsset != nil || bg.paintDrawingAsset != nil
        }
        return card.paintImageAsset != nil || card.paintDrawingAsset != nil
    }

    func fileExists(_ path: String) -> Bool {
        // `there is a file X` — true when the app's file store already holds it
        // (a file this stack created via `open/write file`). External files on
        // the user's disk aren't reachable from the sandbox, so those read
        // absent — the right answer for a stack probing a file Contrapt lacks.
        guard let url = try? fileURL(for: path) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func fileRead(_ path: String, until delimiter: String?, count: Int?, at position: Int?) throws -> (text: String, atEOF: Bool) {
        guard var file = openFiles[path] else { throw HostError("File not open.") }
        // `read … at <pos>` seeks before reading — 1-based like HyperCard's
        // write-at (0 and 1 both mean the start). Cloze Text.
        if let position { file.mark = max(0, position - 1) }
        guard file.mark < file.characters.count else { return ("", true) }
        var end = file.characters.count
        if let count { end = min(end, file.mark + max(0, count)) }
        else if let delimiter, let d = delimiter.first {
            if let found = file.characters[file.mark...].firstIndex(of: d) { end = found + 1 }
        }
        let text = String(file.characters[file.mark..<end])
        file.mark = end
        openFiles[path] = file
        return (text, end >= file.characters.count)
    }

    func fileWrite(_ path: String, text: String, at position: FileWritePosition) throws {
        guard var file = openFiles[path] else { throw HostError("File not open.") }
        let start: Int
        switch position {
        case .mark: start = file.mark
        case .eof: start = file.characters.count
        case .offset(let n): start = max(0, n - 1) // 1-based, as in HC
        }
        let incoming = Array(text)
        if start >= file.characters.count {
            file.characters.append(contentsOf: Array(repeating: " ", count: start - file.characters.count))
            file.characters.append(contentsOf: incoming)
        } else {
            // Overwrite at the mark without inserting, keeping any tail.
            let overwriteEnd = min(file.characters.count, start + incoming.count)
            file.characters.replaceSubrange(start..<overwriteEnd, with: incoming)
            if start + incoming.count > overwriteEnd {
                file.characters.append(contentsOf: incoming[(overwriteEnd - start)...])
            }
        }
        file.mark = start + incoming.count
        openFiles[path] = file
    }

    // MARK: - Globals

    func globalValue(_ name: String) -> String? {
        GlobalStore.shared.values[name]
    }

    func setGlobalValue(_ name: String, to value: String) {
        GlobalStore.shared.values[name] = value
    }

    // MARK: - Persistent stack data (`stackData`)

    func persistentData() -> String {
        StackDataStore.shared.data(for: stack.id.uuidString)
    }

    func setPersistentData(_ encoded: String) {
        StackDataStore.shared.set(encoded, for: stack.id.uuidString)
    }

    // MARK: - Clock

    func clock(_ field: ClockField) -> String {
        let now = Date()
        switch field {
        case .seconds:
            return String(HyperCardDate.seconds(of: now)) // 1904 epoch, as in HyperCard
        case .ticks:
            return String(Int(now.timeIntervalSince1970 * 60))
        case .shortDate, .longDate, .abbreviatedDate, .shortTime, .longTime:
            let formatter = DateFormatter()
            switch field {
            case .shortDate: formatter.dateStyle = .short
            case .longDate: formatter.dateStyle = .full
            case .abbreviatedDate:
                // HC's abbreviated date includes the weekday:
                // "Fri, Jan 15, 2094" (oracle-verified, HC 2.3).
                formatter.dateFormat = "EEE, MMM d, yyyy"
            case .shortTime: formatter.timeStyle = .short
            case .longTime: formatter.timeStyle = .medium
            default: break
            }
            return formatter.string(from: now)
        }
    }

    // MARK: - Convert

    /// Reformats a date/time, matching the styles `the date` / `the time`
    /// produce so values round-trip. Uses the user's calendar and locale;
    /// `seconds` counts from the Unix epoch, as `the seconds` does.
    func convert(_ value: String, from: [ConvertFormat], to: [ConvertFormat]) throws -> String {
        let date = try convertParse(value, from: from)
        return try convertRender(date, to: to)
    }

    // MARK: - Dialogs

    func answer(_ prompt: String, buttons: [String]) async -> String {
        await onAnswer(prompt, buttons)
    }

    func ask(_ prompt: String, initialAnswer: String) async -> String? {
        await onAsk(prompt, initialAnswer)
    }

    func answerFile(_ prompt: String, type: String?) async -> String? {
        await onAnswerFile(prompt, type)
    }

    func wait(seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }

    // MARK: - Networking

    /// `ask <prompt> with ai` — send the prompt to the cloud model (the same
    /// key the AI co-author uses), gated by the per-host network-consent
    /// prompt so a browsed stack can't silently spend the key. The reply goes
    /// to `it`; any error (no key, offline, declined) to `the result`.
    func aiRespond(prompt: String) async -> (reply: String, error: String?) {
        let provider = CloudCoAuthor()
        if let unavailable = provider.unavailableReason {
            return ("", unavailable)   // e.g. no key set — add one in Settings
        }
        guard await isNetworkAllowed(host: "api.anthropic.com") else {
            return ("", "\"\(stack.name)\" isn't allowed to use AI.")
        }
        let request = CoAuthorRequest(
            instructions: "You are a helpful assistant answering from inside a HyperCard-style stack. "
                + "Reply in plain text only — no Markdown, no code fences — suitable to drop straight into a card field. Be concise.",
            prompt: prompt)
        do {
            return (try await provider.respond(to: request), nil)
        } catch {
            return ("", error.localizedDescription)
        }
    }

    /// `url`/`post`/`delete url` — a real HTTP request, gated by per-stack/per-
    /// host consent (see isNetworkAllowed). Carries the script's httpHeaders and
    /// httpTimeout; returns the body, status, response headers, and (on failure)
    /// an error that the interpreter routes to `the result`.
    func httpRequest(method: String, url: String, body: String?,
                     headers: [String: String], timeout: Double)
        async -> (body: String, status: Int, headers: [String: String], error: String?) {

        guard let parsed = URL(string: url),
              let scheme = parsed.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let hostName = parsed.host else {
            return ("", 0, [:], "That isn't a valid web address.")
        }

        guard await isNetworkAllowed(host: hostName) else {
            return ("", 0, [:], "This stack isn't allowed to connect to \(hostName).")
        }

        var request = URLRequest(url: parsed)
        request.httpMethod = method
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let body { request.httpBody = Data(body.utf8) }
        if timeout > 0 { request.timeoutInterval = timeout }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            var responseHeaders: [String: String] = [:]
            for (key, value) in http?.allHeaderFields ?? [:] {
                if let name = key as? String, let text = value as? String { responseHeaders[name] = text }
            }
            return (String(data: data, encoding: .utf8) ?? "",
                    http?.statusCode ?? 0, responseHeaders, nil)
        } catch {
            return ("", 0, [:], error.localizedDescription)
        }
    }

    /// Whether the running stack may reach `host`: the authored stack is always
    /// allowed; a remembered decision wins; otherwise prompt once and remember
    /// the Always answers (keyed by stack path + host).
    private func isNetworkAllowed(host: String) async -> Bool {
        if isAuthoring() { return true }
        let key = NetworkConsentStore.key(stackPath: stackPath, host: host)
        if let remembered = NetworkConsentStore.shared.remembered(key) { return remembered }
        let decision = await onNetworkConsent(host)
        NetworkConsentStore.shared.record(key, allow: decision.allow, always: decision.always)
        return decision.allow
    }

    func exists(_ object: HyperTalkObject) -> Bool {
        switch object {
        case .part(let kind, let domain, let reference, let onCard):
            return (try? locatePart(kind: kind, domain: domain, reference: reference, onCard: onCard)) != nil
        case .card(let destination):
            return (try? resolveCardIndex(destination)) != nil
        case .thisCard:
            return !stack.cards.isEmpty
        case .thisBackground:
            let card = stack.cards[cardIndex]
            return stack.backgrounds.contains { $0.id == card.backgroundID }
        case .thisStack:
            return true
        }
    }

    // MARK: - Find

    /// One searchable field, in stack traversal order.
    private struct FieldSlot {
        let cardIndex: Int
        let isBackground: Bool
        let ordinal: Int       // position among fields in its own layer
        let partID: UUID
        let text: String
    }

    func find(_ text: String, mode: FindMode, inField reference: HyperTalkObject.Reference?, fieldDomain domain: HyperTalkObject.PartDomain) throws -> Bool {
        let query = text.trimmingCharacters(in: .whitespaces)
        let session = FindSession.shared
        let slots = fieldSlots(inField: reference, domain: domain)
        // A named-but-missing scoped field is an error, not a quiet miss —
        // otherwise `find "x" in card field id 16` looks like "x isn't there".
        if slots.isEmpty, let reference {
            throw HostError("There is no \(fieldDescription(reference, domain)) to search.")
        }
        guard !query.isEmpty, !slots.isEmpty else {
            beep(); onFind(nil); return false
        }

        // Continue from the last match when the same search repeats, so
        // repeating `find` walks to the next occurrence.
        let scopeKey = reference.map { referenceKey($0, domain) }
        let continuing = session.query == query && session.mode == mode && session.scope == scopeKey && session.partID != nil
        let startIndex: Int
        if continuing, let index = slots.firstIndex(where: { $0.cardIndex == session.cardIndex && $0.partID == session.partID }) {
            startIndex = index
        } else {
            startIndex = slots.firstIndex { $0.cardIndex >= cardIndex } ?? 0
        }

        // Scan every slot from the start point, giving the first slot the
        // supplied offset (the rest start at 0).
        func scan(firstOffset: Int) -> (slot: FieldSlot, range: Range<Int>)? {
            for step in 0..<slots.count {
                let slot = slots[(startIndex + step) % slots.count]
                let from = step == 0 ? firstOffset : 0
                if let range = FindMatcher.firstRange(in: slot.text, query: query, mode: mode, from: from) {
                    return (slot, range)
                }
            }
            return nil
        }

        // Continuing, resume past the last match; if that finds nothing, wrap
        // around from the top (so repeating `find` on a lone match re-boxes
        // it, as HyperCard does) rather than reporting "not found".
        let match = scan(firstOffset: continuing ? session.matchStart + 1 : 0)
            ?? (continuing ? scan(firstOffset: 0) : nil)
        guard let (slot, range) = match else {
            // HyperCard beeps and leaves everything put.
            beep()
            onFind(nil)
            return false
        }

        // Record the match, navigate to its card, and box the field.
        let characters = Array(slot.text)
        let matched = String(characters[range])
        let descriptor = "\(slot.isBackground ? "background" : "card") field \(slot.ordinal)"
        let lineNumber = characters[0..<range.lowerBound].filter { $0 == "\n" }.count + 1
        session.query = query
        session.mode = mode
        session.scope = scopeKey
        session.cardIndex = slot.cardIndex
        session.partID = slot.partID
        session.matchStart = range.lowerBound
        session.found = [
            .text: matched,
            .field: descriptor,
            .chunk: "char \(range.lowerBound + 1) to \(range.upperBound) of \(descriptor)",
            .line: "line \(lineNumber) of \(descriptor)",
        ]
        currentCardIndex.wrappedValue = slot.cardIndex
        onFind(FindHighlight(partID: slot.partID, range: range))
        return true
    }

    func foundValue(_ field: FoundField) -> String {
        FindSession.shared.found[field] ?? ""
    }

    // MARK: - Push / pop card

    func pushCard() {
        guard cardIndex < stack.cards.count else { return }
        CardBackStack.shared.ids.append(String(stack.cards[cardIndex].scriptID))
    }

    func popCard() -> String? {
        CardBackStack.shared.ids.isEmpty ? nil : CardBackStack.shared.ids.removeLast()
    }

    /// Every searchable field across the stack, in card order (card fields
    /// before background fields), honoring `dontSearch` on cards and
    /// backgrounds and any `in <field>` restriction.
    private func fieldSlots(inField reference: HyperTalkObject.Reference?, domain: HyperTalkObject.PartDomain) -> [FieldSlot] {
        var slots: [FieldSlot] = []
        for (index, card) in stack.cards.enumerated() where !card.dontSearch {
            if domain != .background {
                appendFieldSlots(from: card.parts, cardIndex: index, isBackground: false, reference: reference, into: &slots)
            }
            if domain != .card,
               let background = stack.backgrounds.first(where: { $0.id == card.backgroundID }),
               !background.dontSearch {
                appendFieldSlots(from: background.parts, cardIndex: index, isBackground: true, reference: reference, into: &slots)
            }
        }
        return slots
    }

    private func appendFieldSlots(from parts: [Part], cardIndex: Int, isBackground: Bool, reference: HyperTalkObject.Reference?, into slots: inout [FieldSlot]) {
        var ordinal = 0
        for part in parts {
            guard case .field(let properties) = part.kind else { continue }
            ordinal += 1
            if let reference, !fieldMatches(part: part, ordinal: ordinal, reference: reference) { continue }
            let text = (isBackground && !properties.sharedText)
                ? (stack.cards[cardIndex].backgroundFieldContent[part.id.uuidString]?.text ?? "")
                : properties.text
            slots.append(FieldSlot(cardIndex: cardIndex, isBackground: isBackground, ordinal: ordinal, partID: part.id, text: text))
        }
    }

    private func fieldMatches(part: Part, ordinal: Int, reference: HyperTalkObject.Reference) -> Bool {
        switch reference {
        case .named(let name): return part.name.caseInsensitiveCompare(name) == .orderedSame
        case .number(let number): return ordinal == number
        case .id(let id): return String(part.scriptID) == id.trimmingCharacters(in: .whitespaces)
        }
    }

    /// A human-readable field reference for `find` errors, e.g.
    /// "card field id 16" or "background field \"Notes\"".
    private func fieldDescription(_ reference: HyperTalkObject.Reference, _ domain: HyperTalkObject.PartDomain) -> String {
        let layer = switch domain {
        case .any: ""
        case .card: "card "
        case .background: "background "
        }
        switch reference {
        case .named(let name): return "\(layer)field \"\(name)\""
        case .number(let number): return "\(layer)field \(number)"
        case .id(let id): return "\(layer)field id \(id)"
        }
    }

    private func referenceKey(_ reference: HyperTalkObject.Reference, _ domain: HyperTalkObject.PartDomain) -> String {
        let prefix = switch domain {
        case .any: ""
        case .card: "card "
        case .background: "background "
        }
        switch reference {
        case .named(let name): return prefix + name.lowercased()
        case .number(let number): return prefix + String(number)
        case .id(let id): return prefix + "id " + id
        }
    }

    private func convertFormatter(_ formats: [ConvertFormat]) -> DateFormatter? {
        let formatter = DateFormatter()
        // Two-digit years resolve into the CURRENT century, as in HyperCard
        // ("1/15/94" on a 2026 clock is 2094) — oracle-verified.
        formatter.twoDigitStartDate = HyperCardDate.centuryStart
        for format in formats {
            switch format {
            case .shortDate: formatter.dateStyle = .short
            case .longDate: formatter.dateStyle = .full
            case .abbreviatedDate:
                // HC's abbreviated date includes the weekday:
                // "Fri, Jan 15, 2094" (oracle-verified, HC 2.3).
                formatter.dateFormat = "EEE, MMM d, yyyy"
            case .shortTime: formatter.timeStyle = .short
            case .longTime: formatter.timeStyle = .medium
            case .seconds, .dateItems: return nil
            }
        }
        return formatter
    }

    private func convertParse(_ value: String, from: [ConvertFormat]) throws -> Date {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        // HyperCard fills any date/time components the value doesn't supply from
        // the current date and time — so an empty value converts as "now"
        // (rather than erroring). DateBook relies on this: `goSixMonthly field
        // "weekSecs"` on a card whose field is empty degrades to the current
        // period instead of stopping the handler.
        if trimmed.isEmpty {
            return Date()
        }
        if from == [.seconds] || (from.isEmpty && Double(trimmed) != nil) {
            guard let seconds = Double(trimmed) else {
                throw HostError("Can't read \"\(value)\" as seconds.")
            }
            return HyperCardDate.date(fromSeconds: seconds) // 1904 epoch (oracle-verified)
        }
        if from == [.dateItems] || (from.isEmpty && trimmed.contains(",")) {
            // Missing or empty components inherit from the current date/time,
            // as in HyperCard — so `,,,0,0,0` (from `put 0 into item 4/5/6`) is
            // today at midnight, not an invalid year-0 date.
            let now = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
            let raw = trimmed.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            func part(_ index: Int, _ fallback: Int) -> Int {
                guard index < raw.count, !raw[index].isEmpty, let n = Int(raw[index]) else { return fallback }
                return n
            }
            var components = DateComponents()
            components.year = part(0, now.year!)
            components.month = part(1, now.month!)
            components.day = part(2, now.day!)
            components.hour = part(3, now.hour!)
            components.minute = part(4, now.minute!)
            components.second = part(5, now.second!)
            guard let date = Calendar.current.date(from: components) else {
                throw HostError("Can't read \"\(value)\" as dateItems.")
            }
            return date
        }
        if !from.isEmpty {
            guard let date = convertFormatter(from)?.date(from: trimmed) else {
                throw HostError("Can't read \"\(value)\" in that format.")
            }
            return date
        }
        // Auto-detect: try the style combinations until one reads it.
        let candidates: [[ConvertFormat]] = [
            [.shortDate, .shortTime], [.longDate, .longTime],
            [.longDate], [.abbreviatedDate], [.shortDate],
            [.longTime], [.shortTime],
        ]
        for candidate in candidates {
            if let date = convertFormatter(candidate)?.date(from: trimmed) { return date }
        }
        throw HostError("Can't read \"\(value)\" as a date or time.")
    }

    private func convertRender(_ date: Date, to: [ConvertFormat]) throws -> String {
        if to == [.seconds] { return String(HyperCardDate.seconds(of: date)) } // 1904 epoch
        if to == [.dateItems] {
            let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
            return [c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!, c.weekday!]
                .map(String.init).joined(separator: ",")
        }
        guard let formatter = convertFormatter(to) else {
            throw HostError("Can't convert to that combination of formats.")
        }
        return formatter.string(from: date)
    }

    // MARK: - Properties

    func propertyValue(_ property: String, of object: HyperTalkObject) throws -> String {
        switch object {
        case .part(let kind, let domain, let reference, let onCard):
            let location = try locatePart(kind: kind, domain: domain, reference: reference, onCard: onCard)
            if property == "number" {
                return String(ordinal(of: location, kind: kind))
            }
            let ci = try onCard.map { try resolveCardIndex($0) } ?? cardIndex
            return try partProperty(property, of: effectivePart(at: location, cardIndex: ci), kind: kind)
        case .card(let destination):
            let index = try resolveCardIndex(destination)
            return try cardProperty(property, cardAt: index)
        case .thisCard:
            return try cardProperty(property, cardAt: cardIndex)
        case .thisBackground:
            let card = stack.cards[cardIndex]
            guard let background = stack.backgrounds.first(where: { $0.id == card.backgroundID }) else {
                throw HostError("This card has no background.")
            }
            switch property {
            case "name": return background.name
            case "longname": return "bkgnd \"\(background.name)\""
            case "longid": return "bkgnd id \(background.scriptID)"
            case "showpict", "showbgpict": return background.showPicture ? "true" : "false"
            case "id": return String(background.scriptID)
            case "number":
                // The background's 1-based position among the stack's
                // backgrounds — `the number of this background` (DateBook's
                // doMenu guards on it).
                return String((stack.backgrounds.firstIndex(where: { $0.id == background.id }) ?? 0) + 1)
            case "script": return background.script
            case "cantdelete": return background.cantDelete ? "true" : "false"
            case "dontsearch": return background.dontSearch ? "true" : "false"
            default: throw Self.noSuchProperty(property, of: "this background")
            }
        case .thisStack:
            switch property {
            case "name": return stack.name
            case "longname", "longid":
                // HyperCard's long name is the full colon path (`stack
                // "HD:Folder:Name"`). Stacks parse the folder out of it — e.g.
                // the Klingon Dictionary strips chars until the last ":" — so a
                // colonless name spins that loop forever. Use the document's
                // real path, colonized; fall back to the bare name when unsaved.
                return "stack \"\(stackPath.isEmpty ? stack.name : stackPath)\""
            case "script": return stack.script
            case "cards": return String(stack.cards.count)
            case "width": return numberText(stack.cardSize.width)
            case "height": return numberText(stack.cardSize.height)
            case "fullscreen": return stack.isFullScreen ? "true" : "false"
            case "paddingcolor": return stack.paddingColor
            case "theme": return stack.theme
            // Stack properties Contrapt doesn't model (the SET side no-ops these
            // too — see the interpreter's ignorableStackProperties): report
            // benign defaults so guards like `if the cantModify of this stack`
            // run. `freeSize`/`size` are byte counts we don't track → 0.
            case "cantmodify", "cantabort", "cantpeek", "cantdelete", "usermodify": return "false"
            case "freesize", "size": return "0"
            default: throw Self.noSuchProperty(property, of: "this stack")
            }
        }
    }

    func setProperty(_ property: String, of object: HyperTalkObject, to value: String) throws {
        guard property != "id" else {
            throw HostError("The id of an object can't be changed.")
        }
        switch object {
        case .part(let kind, let domain, let reference, let onCard):
            let location = try locatePart(kind: kind, domain: domain, reference: reference, onCard: onCard)
            if property == "text", usesOverlay(location) {
                let ci = try onCard.map { try resolveCardIndex($0) } ?? cardIndex
                writeOverlay(text: value, partID: part(at: location).id, cardIndex: ci)
                return
            }
            var updated = part(at: location)
            try applyPartProperty(property, to: &updated, kind: kind, value: value)
            setPart(updated, at: location)
            // HyperCard family rule, script side: SETTING a family member's
            // hilite to true unhilights its same-layer siblings — the What is
            // HyperCard? topic buttons rely on it (each card's openCard does
            // `set the hilite of bkgnd btn <topic> to true`; nothing ever
            // clears the old one by hand). The click path does this in
            // ContentView.clearFamilySiblings; this is its set-path twin.
            if ["hilite", "hilight", "highlight", "highlite"].contains(property),
               case .button(let button) = updated.kind, button.family > 0, button.hilite {
                clearFamilyHiliteSiblings(of: updated, family: button.family, at: location)
            }
        case .card(let destination):
            try setCardProperty(property, cardAt: try resolveCardIndex(destination), to: value)
        case .thisCard:
            try setCardProperty(property, cardAt: cardIndex, to: value)
        case .thisBackground:
            let card = stack.cards[cardIndex]
            guard let index = stack.backgrounds.firstIndex(where: { $0.id == card.backgroundID }) else {
                throw HostError("This card has no background.")
            }
            switch property {
            case "name": stackBinding.wrappedValue.backgrounds[index].name = value
            case "cantdelete": stackBinding.wrappedValue.backgrounds[index].cantDelete = try boolean(value, for: property)
            case "dontsearch": stackBinding.wrappedValue.backgrounds[index].dontSearch = try boolean(value, for: property)
            case "showpict", "showbgpict":
                stackBinding.wrappedValue.backgrounds[index].showPicture = try boolean(value, for: property)
            default: throw Self.noSuchProperty(property, of: "this background")
            }
        case .thisStack:
            switch property {
            case "name": stackBinding.wrappedValue.name = value
            case "width": stackBinding.wrappedValue.cardSize.width = try number(value, for: property)
            case "height": stackBinding.wrappedValue.cardSize.height = try number(value, for: property)
            case "fullscreen": stackBinding.wrappedValue.isFullScreen = try boolean(value, for: property)
            case "paddingcolor": stackBinding.wrappedValue.paddingColor = value
            case "theme": stackBinding.wrappedValue.theme = ThemeSpec.canonicalName(value)
            default: throw Self.noSuchProperty(property, of: "this stack")
            }
        }
    }

    private func partProperty(_ property: String, of part: Part, kind: String) throws -> String {
        switch property {
        case "name": return part.name
        case "longname": return "\(kind) \"\(part.name)\""
        case "longid": return "\(kind) id \(part.scriptID)"
        case "id": return String(part.scriptID)
        case "script": return part.script
        case "visible": return part.isVisible ? "true" : "false"
        case "width": return numberText(part.frame.width)
        case "height": return numberText(part.frame.height)
        case "left": return numberText(part.frame.x)
        case "top": return numberText(part.frame.y)
        case "right": return numberText(part.frame.x + part.frame.width)
        case "bottom": return numberText(part.frame.y + part.frame.height)
        case "rect", "rectangle":
            return [part.frame.x, part.frame.y, part.frame.x + part.frame.width, part.frame.y + part.frame.height]
                .map(numberText).joined(separator: ",")
        case "loc", "location":
            return [part.frame.x + part.frame.width / 2, part.frame.y + part.frame.height / 2]
                .map(numberText).joined(separator: ",")
        case "title":
            guard case .button(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.title
        case "showname":
            guard case .button(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.showName ? "true" : "false"
        case "autohilite", "autohilight", "autohighlight", "autohighlite":
            guard case .button(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.autoHilite ? "true" : "false"
        case "family":
            guard case .button(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return String(properties.family)
        case "style":
            switch part.kind {
            case .button(let properties): return properties.style.rawValue
            case .field(let properties): return properties.style.rawValue
            default: throw Self.noSuchProperty(property, of: kind)
            }
        case "hilite", "hilight", "highlight", "highlite":
            guard case .button(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.hilite ? "true" : "false"
        case "contents":
            // HyperCard 2.x button contents (popup/list text) — also what a
            // bare `btn "X"` reads in an expression.
            guard case .button(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.contents
        case "fillcolor":
            // A button's custom fill (empty = the themed default).
            guard case .button(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.fillColor ?? ""
        case "bordercolor", "edgecolor":
            // A button's or field's custom edge color (empty = themed default).
            switch part.kind {
            case .button(let properties): return properties.borderColor ?? ""
            case .field(let properties): return properties.borderColor ?? ""
            default: throw Self.noSuchProperty(property, of: kind)
            }
        case "textcolor":
            // A field's whole-text / a button's title color (empty = default).
            switch part.kind {
            case .field(let properties): return properties.textColor ?? ""
            case .button(let properties): return properties.textColor ?? ""
            default: throw Self.noSuchProperty(property, of: kind)
            }
        case "icon":
            // The button's icon resource id (0 = none). Contrapt draws the
            // rendered `iconAsset`, so a `set` round-trips the id but doesn't
            // re-resolve a new glyph at run time.
            guard case .button(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return String(properties.iconID)
        case "text":
            switch part.kind {
            case .field(let properties): return properties.text
            case .label(let properties): return properties.text
            default: throw Self.noSuchProperty(property, of: kind)
            }
        case "placeholder":
            guard case .field(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.placeholder
        case "textfont":
            guard let format = Self.format(of: part) else { throw Self.noSuchProperty(property, of: kind) }
            return format.fontDesign.rawValue
        case "textsize":
            guard let format = Self.format(of: part) else { throw Self.noSuchProperty(property, of: kind) }
            return numberText(format.size)
        case "textheight":
            // A field's line height (`the textHeight of field`). 0 = the font's
            // natural height, as HyperCard reports when unset.
            guard case .field(let f) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return numberText(f.textHeight ?? 0)
        case "textstyle":
            guard let format = Self.format(of: part) else { throw Self.noSuchProperty(property, of: kind) }
            return Self.styleList(format)
        case "textalign":
            guard let format = Self.format(of: part) else { throw Self.noSuchProperty(property, of: kind) }
            return format.align.rawValue
        case "locktext":
            guard case .field(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.lockText ? "true" : "false"
        case "showlines":
            guard case .field(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.showLines ? "true" : "false"
        case "widemargins":
            guard case .field(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.wideMargins ? "true" : "false"
        case "dontwrap":
            guard case .field(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.dontWrap ? "true" : "false"
        case "autotab":
            guard case .field(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.autoTab ? "true" : "false"
        case "autoselect":
            guard case .field(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.autoSelect ? "true" : "false"
        case "multiplelines":
            guard case .field(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.multipleLines ? "true" : "false"
        case "fixedlineheight":
            guard case .field(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return properties.fixedLineHeight ? "true" : "false"
        case "enabled":
            // `the enabled of button X` — false after `disable`.
            return part.isEnabled ? "true" : "false"
        case "scroll":
            // `the scroll of field X` — the field's scroll offset in points.
            guard case .field(let properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return String(Int(properties.scroll))
        default:
            throw Self.noSuchProperty(property, of: kind)
        }
    }

    private func applyPartProperty(_ property: String, to part: inout Part, kind: String, value: String) throws {
        switch property {
        case "name":
            part.name = value
        case "script":
            // `set the script of button "X" to …` — scripts build buttons and
            // wire their behavior at run time (DateBook's fillWeekly). Capped
            // like any loaded script so a runaway can't grow it unbounded.
            part.script = Stack.cappedScript(value)
        case "visible":
            part.isVisible = try boolean(value, for: property)
        case "enabled":
            part.isEnabled = try boolean(value, for: property)
        case "width": part.frame.width = max(1, try number(value, for: property))
        case "height": part.frame.height = max(1, try number(value, for: property))
        case "left": part.frame.x = try number(value, for: property)
        case "top": part.frame.y = try number(value, for: property)
        case "right": part.frame.x = try number(value, for: property) - part.frame.width
        case "bottom": part.frame.y = try number(value, for: property) - part.frame.height
        case "rect", "rectangle":
            let n = try numberList(value, count: 4, for: property)
            part.frame = PartFrame(x: n[0], y: n[1], width: max(1, n[2] - n[0]), height: max(1, n[3] - n[1]))
        case "loc", "location":
            let n = try numberList(value, count: 2, for: property)
            part.frame.x = n[0] - part.frame.width / 2
            part.frame.y = n[1] - part.frame.height / 2
        case "title":
            guard case .button(var properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            properties.title = value
            part.kind = .button(properties)
        case "showname":
            guard case .button(var properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            properties.showName = try boolean(value, for: property)
            part.kind = .button(properties)
        case "autohilite", "autohilight", "autohighlight", "autohighlite":
            guard case .button(var properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            properties.autoHilite = try boolean(value, for: property)
            part.kind = .button(properties)
        case "family":
            guard case .button(var properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            guard let family = Int(value.trimmingCharacters(in: .whitespaces)), (0...15).contains(family) else {
                throw HostError("The family of a button is a number from 0 to 15.")
            }
            properties.family = family
            part.kind = .button(properties)
        case "style":
            switch part.kind {
            case .button(var properties):
                guard let style = ButtonStyleKind.parse(value) else {
                    throw HostError("Unknown button style \"\(value)\". Try roundRect, rectangle, shadow, opaque, transparent, checkbox, or radio.")
                }
                properties.style = style
                part.kind = .button(properties)
            case .field(var properties):
                guard let style = FieldStyle(rawValue: value.lowercased().trimmingCharacters(in: .whitespaces)) else {
                    throw HostError("Unknown field style \"\(value)\". Try transparent, opaque, rectangle, or shadow.")
                }
                properties.style = style
                part.kind = .field(properties)
            default:
                throw Self.noSuchProperty(property, of: kind)
            }
        case "hilite", "hilight", "highlight", "highlite":
            guard case .button(var properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            properties.hilite = try boolean(value, for: property)
            part.kind = .button(properties)
        case "contents":
            // `put x into btn "X"` routes here — HC 2.x button contents.
            guard case .button(var properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            properties.contents = value
            part.kind = .button(properties)
        case "fillcolor":
            // A color name or #RRGGBB; empty restores the themed default.
            guard case .button(var properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            properties.fillColor = trimmed.isEmpty ? nil : trimmed
            part.kind = .button(properties)
        case "bordercolor", "edgecolor":
            let trimmedBorder = value.trimmingCharacters(in: .whitespaces)
            switch part.kind {
            case .button(var properties):
                properties.borderColor = trimmedBorder.isEmpty ? nil : trimmedBorder
                part.kind = .button(properties)
            case .field(var properties):
                properties.borderColor = trimmedBorder.isEmpty ? nil : trimmedBorder
                part.kind = .field(properties)
            default: throw Self.noSuchProperty(property, of: kind)
            }
        case "textcolor":
            let trimmedText = value.trimmingCharacters(in: .whitespaces)
            switch part.kind {
            case .field(var properties):
                properties.textColor = trimmedText.isEmpty ? nil : trimmedText
                part.kind = .field(properties)
            case .button(var properties):
                properties.textColor = trimmedText.isEmpty ? nil : trimmedText
                part.kind = .button(properties)
            default: throw Self.noSuchProperty(property, of: kind)
            }
        case "icon":
            // HyperCard sets an icon by numeric resource id OR by its name
            // (`set icon of btn to "General Essay"`). A numeric id resolves
            // through the stack's imported icon library (stack.icons) so the
            // DRAWN glyph swaps too — the animation-button idiom; an id the
            // library lacks keeps the number (round-trips) but shows the
            // missing-icon fallback. Setting 0 clears; a NAME leaves the
            // current icon (names aren't imported).
            guard case .button(var properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            if let id = Int(value.trimmingCharacters(in: .whitespaces)) {
                properties.iconID = id
                if id == 0 {
                    properties.iconAsset = nil; properties.iconSymbol = nil; properties.iconMissing = false
                } else if let asset = stack.icons[String(id)] {
                    properties.iconAsset = asset; properties.iconSymbol = nil; properties.iconMissing = false
                } else {
                    properties.iconAsset = nil; properties.iconSymbol = nil; properties.iconMissing = true
                }
            }
            part.kind = .button(properties)
        case "text":
            switch part.kind {
            case .field(var properties):
                properties.text = value
                part.kind = .field(properties)
            case .label(var properties):
                properties.text = value
                part.kind = .label(properties)
            default:
                throw Self.noSuchProperty(property, of: kind)
            }
        case "placeholder":
            guard case .field(var properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            properties.placeholder = value
            part.kind = .field(properties)
        case "textfont":
            try withFieldFormat(&part, kind: kind) { format in
                format.fontDesign = Self.fontDesign(for: value)
            }
        case "textsize":
            let size = try number(value, for: property)
            try withFieldFormat(&part, kind: kind) { $0.size = min(max(size, 4), 256) }
        case "textheight":
            // `set the textHeight of field … to N` — the field's line height
            // (0 clears to the font's natural height).
            guard case .field(var properties) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            let h = try number(value, for: property)
            properties.textHeight = h > 0 ? h : nil
            part.kind = .field(properties)
        case "textstyle":
            try withFieldFormat(&part, kind: kind) { Self.applyStyleList(value, to: &$0) }
        case "textalign":
            guard let align = TextAlign(rawValue: value.lowercased().trimmingCharacters(in: .whitespaces)) else {
                throw HostError("Unknown alignment \"\(value)\". Try left, center, or right.")
            }
            try withFieldFormat(&part, kind: kind) { $0.align = align }
        case "locktext":
            try withField(&part, kind: kind) { $0.lockText = try boolean(value, for: property) }
        case "showlines":
            try withField(&part, kind: kind) { $0.showLines = try boolean(value, for: property) }
        case "widemargins":
            try withField(&part, kind: kind) { $0.wideMargins = try boolean(value, for: property) }
        case "dontwrap":
            try withField(&part, kind: kind) { $0.dontWrap = try boolean(value, for: property) }
        case "autotab":
            try withField(&part, kind: kind) { $0.autoTab = try boolean(value, for: property) }
        case "autoselect":
            try withField(&part, kind: kind) { $0.autoSelect = try boolean(value, for: property) }
        case "multiplelines":
            try withField(&part, kind: kind) { $0.multipleLines = try boolean(value, for: property) }
        case "fixedlineheight":
            try withField(&part, kind: kind) { $0.fixedLineHeight = try boolean(value, for: property) }
        case "sharedtext":
            // Contrapt background fields inherently share their text (they
            // live on the background); per-card bg text isn't modeled, so
            // setting sharedText is accepted and ignored.
            _ = try boolean(value, for: property)
        case "scroll":
            // `set the scroll of field X to N` — scrolls the field's text.
            let offset = max(0, try number(value, for: property))
            try withField(&part, kind: kind) { $0.scroll = offset }
        default:
            throw Self.noSuchProperty(property, of: kind)
        }
    }

    /// Mutates a field's FieldPart, or throws if the part isn't a field.
    private func withField(_ part: inout Part, kind: String, _ body: (inout FieldPart) throws -> Void) throws {
        guard case .field(var properties) = part.kind else { throw Self.noSuchProperty("field option", of: kind) }
        try body(&properties)
        part.kind = .field(properties)
    }

    /// The text format of a part that has one (fields and buttons), else nil.
    private static func format(of part: Part) -> TextFormat? {
        switch part.kind {
        case .field(let properties): properties.format
        case .button(let properties): properties.format
        default: nil
        }
    }

    /// Mutates the text format of a field or button, or throws otherwise.
    private func withFieldFormat(_ part: inout Part, kind: String, _ body: (inout TextFormat) throws -> Void) throws {
        switch part.kind {
        case .field(var properties):
            try body(&properties.format)
            part.kind = .field(properties)
        case .button(var properties):
            try body(&properties.format)
            part.kind = .button(properties)
        default:
            throw Self.noSuchProperty("text formatting", of: kind)
        }
    }

    /// "plain", or a comma list of bold/italic/underline.
    static func styleList(_ format: TextFormat) -> String {
        var parts: [String] = []
        if format.isBold { parts.append("bold") }
        if format.isItalic { parts.append("italic") }
        if format.isUnderline { parts.append("underline") }
        if format.isOutline { parts.append("outline") }
        if format.isGroup { parts.append("group") }
        return parts.isEmpty ? "plain" : parts.joined(separator: ",")
    }

    static func applyStyleList(_ value: String, to format: inout TextFormat) {
        let tokens = value.lowercased().split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
        format.isBold = tokens.contains("bold")
        format.isItalic = tokens.contains("italic")
        format.isUnderline = tokens.contains("underline")
        format.isOutline = tokens.contains("outline")
        // `group` makes the field's text click as a unit (see TextFormat.isGroup
        // and FieldClickHitTest) — scriptable via `set the textStyle … to group`.
        format.isGroup = tokens.contains("group")
    }

    // MARK: - Chunk (text-run) properties

    func textRunProperty(_ property: String, ofField reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, range: Range<Int>) throws -> String {
        let location = try locatePart(kind: "field", domain: domain, reference: reference, onCard: nil)
        guard case .field(let properties) = effectivePart(at: location, cardIndex: cardIndex).kind else {
            throw HostError("That part is not a field.")
        }
        // `the link of <chunk>` — the Markdown link target covering the
        // chunk, read from the field's source text.
        if property == "link" {
            return MarkdownLinks.link(in: properties.text, at: range)
        }
        return Self.runProperty(property, text: properties.text, base: properties.format,
                                runs: properties.styleRuns, range: range)
    }

    func setTextRunProperty(_ property: String, ofField reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, range: Range<Int>, to value: String) throws {
        let location = try locatePart(kind: "field", domain: domain, reference: reference, onCard: nil)
        guard case .field(var properties) = effectivePart(at: location, cardIndex: cardIndex).kind else {
            throw HostError("That part is not a field.")
        }
        // `set the link of <chunk> … to <url or card:…>` — rewrite the rich
        // field's Markdown around the chunk (wrap / retarget / unwrap if
        // empty). The write rides setFieldText so per-card background
        // content is honored. Plain fields keep the group/clickText idiom.
        if property == "link" {
            guard properties.kind == .rich else {
                throw HostError("Links live in rich text fields — make the field rich first (or use group text and the clickText).")
            }
            try setFieldText(reference, domain: domain, onCard: nil,
                             to: MarkdownLinks.settingLink(in: properties.text, range: range, to: value))
            return
        }
        let newRuns = try Self.settingRuns(property, to: value, text: properties.text,
                                           base: properties.format, runs: properties.styleRuns,
                                           range: range)
        if usesOverlay(location) {
            writeOverlay(runs: newRuns, partID: part(at: location).id, cardIndex: cardIndex)
            return
        }
        properties.styleRuns = newRuns
        setKind(.field(properties), at: location)
    }

    /// The write side of per-chunk styled text: applies `value` for `property`
    /// over the character range, splitting runs at the boundaries and merging
    /// identical neighbors. `set the textStyle … to bold` REPLACES the span's
    /// style set, as HyperCard does ("plain" clears it).
    static func settingRuns(_ property: String, to value: String, text: String,
                            base: TextFormat, runs: [StyleRun], range: Range<Int>) throws -> [StyleRun] {
        let count = text.count
        let lo = max(0, min(range.lowerBound, count))
        let hi = max(lo, min(range.upperBound, count))
        guard lo < hi else { return runs }

        func mutated(_ format: TextFormat) throws -> TextFormat {
            var f = format
            switch property {
            case "textsize":
                guard let size = Double(value.trimmingCharacters(in: .whitespaces)) else {
                    throw HostError("Expected a point size, like 12.")
                }
                f.size = min(max(size, 4), 256)
            case "textfont":
                // An unmappable font name leaves the design unchanged (we
                // can't load arbitrary classic fonts at run time).
                if let design = parseFontDesign(value) { f.fontDesign = design }
            case "textstyle":
                f.isBold = false; f.isItalic = false; f.isUnderline = false
                f.isOutline = false; f.isGroup = false
                for raw in value.lowercased().split(whereSeparator: { $0 == "," || $0 == " " }) {
                    switch raw.trimmingCharacters(in: .whitespaces) {
                    case "bold": f.isBold = true
                    case "italic": f.isItalic = true
                    case "underline": f.isUnderline = true
                    case "outline", "shadow": f.isOutline = true
                    case "group", "grp": f.isGroup = true
                    case "plain", "", "condense", "extend": break
                    default: break
                    }
                }
            default:
                throw HostError("There is no \(property) property of a chunk.")
            }
            return f
        }

        // The field as contiguous segments of uniform format.
        let sorted = runs.sorted { $0.start < $1.start }
        var boundaries: [Int] = [0, lo, hi, count]
        boundaries.append(contentsOf: sorted.map { min(max($0.start, 0), count) })
        let starts = Array(Set(boundaries)).sorted().filter { $0 < count }
        func formatInForce(at offset: Int) -> TextFormat {
            var f = base
            for run in sorted where run.start <= offset { f = run.format }
            return f
        }
        var segments: [(start: Int, format: TextFormat)] = []
        for start in starts {
            var format = formatInForce(at: start)
            if start >= lo, start < hi { format = try mutated(format) }
            segments.append((start, format))
        }
        // Reserialize: a run wherever the format changes; the base covers any
        // leading span that still matches it.
        var result: [StyleRun] = []
        var current = base
        for segment in segments where segment.format != current {
            result.append(StyleRun(start: segment.start, format: segment.format))
            current = segment.format
        }
        return result
    }

    /// Reads a text-run property over a character range: the value if uniform
    /// across the range, else "mixed" (textStyle) / "" (textFont, textSize).
    static func runProperty(_ property: String, text: String, base: TextFormat, runs: [StyleRun], range: Range<Int>) -> String {
        let runs = runs.sorted { $0.start < $1.start }
        func format(at offset: Int) -> TextFormat {
            var fmt = base
            for run in runs where run.start <= offset { fmt = run.format }
            return fmt
        }
        func value(_ f: TextFormat) -> String {
            switch property {
            case "textfont": return f.fontDesign.rawValue
            case "textsize": return f.size == f.size.rounded() ? String(Int(f.size)) : String(f.size)
            case "textstyle": return styleList(f)
            default: return ""
            }
        }
        let count = text.count
        let lo = max(0, range.lowerBound)
        let hi = min(count, range.upperBound)
        guard lo < hi else { return value(format(at: lo)) } // empty range → format at the edge
        var values = Set<String>()
        for i in lo..<hi { values.insert(value(format(at: i))) }
        if values.count == 1 { return values.first! }
        return property == "textstyle" ? "mixed" : ""
    }

    /// Classic Mac font names → the nearest modern design. HyperCard stacks
    /// name real fonts (Chicago, Geneva, Times, Monaco…); we don't carry those
    /// faces, so map each to its closest family. Unknown names fall back to the
    /// system font rather than erroring (HyperCard substitutes, never rejects).
    static let classicFontDesigns: [String: FontDesign] = [
        // Sans / UI faces
        "chicago": .standard, "geneva": .standard, "charcoal": .standard,
        "helvetica": .standard, "arial": .standard, "espy sans": .standard,
        "verdana": .standard, "tahoma": .standard,
        // Serif faces
        "times": .serif, "times new roman": .serif, "new york": .serif,
        "palatino": .serif, "georgia": .serif, "garamond": .serif,
        "book antiqua": .serif, "bookman": .serif,
        // Monospaced faces
        "monaco": .monospaced, "courier": .monospaced, "courier new": .monospaced,
        "pc monospace": .monospaced, "menlo": .monospaced,
    ]

    static func parseFontDesign(_ value: String) -> FontDesign? {
        let normalized = value.lowercased().trimmingCharacters(in: .whitespaces)
        if let design = FontDesign.allCases.first(where: { $0.rawValue == normalized || $0.label.lowercased() == normalized }) {
            return design
        }
        return classicFontDesigns[normalized]
    }

    /// Like `parseFontDesign` but never fails — an unrecognized font becomes
    /// the system font, so `set textFont to <anything>` can't error.
    static func fontDesign(for value: String) -> FontDesign {
        parseFontDesign(value) ?? .standard
    }

    private func cardProperty(_ property: String, cardAt index: Int) throws -> String {
        let card = stack.cards[index]
        switch property {
        case "name": return card.name
        case "longname": return "card \"\(card.name)\""
        case "longid": return "card id \(card.scriptID)"
        case "script": return card.script
        case "highlightcolor": return card.highlightColor ?? ""
        case "number": return String(index + 1)
        case "id": return String(card.scriptID)
        case "marked": return card.isMarked ? "true" : "false"
        case "cantdelete": return card.cantDelete ? "true" : "false"
        case "dontsearch": return card.dontSearch ? "true" : "false"
        case "showpict": return card.showPicture ? "true" : "false"
        case "showbgpict":
            // The showPict of this card's BACKGROUND (`hide bg picture of cd 3`).
            if let bg = stack.backgrounds.first(where: { $0.id == card.backgroundID }) {
                return bg.showPicture ? "true" : "false"
            }
            return "true"
        // Card geometry — the card occupies the whole card window, so these
        // derive from the stack's card size (the runtime sweep found 20+
        // reads: `the rect of this card`, `the width of card`…).
        case "rect", "rectangle":
            return "0,0,\(Int(stack.cardSize.width)),\(Int(stack.cardSize.height))"
        case "width": return String(Int(stack.cardSize.width))
        case "height": return String(Int(stack.cardSize.height))
        case "topleft": return "0,0"
        case "botright", "bottomright":
            return "\(Int(stack.cardSize.width)),\(Int(stack.cardSize.height))"
        case "loc", "location":
            return "\(Int(stack.cardSize.width) / 2),\(Int(stack.cardSize.height) / 2)"
        case "top", "left": return "0"
        case "right": return String(Int(stack.cardSize.width))
        case "bottom": return String(Int(stack.cardSize.height))
        // `the cantModify of this card` — a stack property authors scope to
        // the card; never modifiable-locked here.
        case "cantmodify": return "false"
        default: throw Self.noSuchProperty(property, of: "a card")
        }
    }

    private func setCardProperty(_ property: String, cardAt index: Int, to value: String) throws {
        func flag() throws -> Bool {
            switch value.lowercased() {
            case "true": return true
            case "false": return false
            default: throw HostError("The \(property) property must be true or false, not \"\(value)\".")
            }
        }
        switch property {
        case "name": stackBinding.wrappedValue.cards[index].name = value
        case "cantmodify": _ = try? flag() // stack-level in HC; accepted, no card state
        case "marked": stackBinding.wrappedValue.cards[index].isMarked = try flag()
        case "cantdelete": stackBinding.wrappedValue.cards[index].cantDelete = try flag()
        case "dontsearch": stackBinding.wrappedValue.cards[index].dontSearch = try flag()
        case "highlightcolor":
            // Empty clears it back to the app accent.
            stackBinding.wrappedValue.cards[index].highlightColor = value.isEmpty ? nil : value
        case "showpict": stackBinding.wrappedValue.cards[index].showPicture = try flag()
        case "showbgpict":
            let bgID = stack.cards[index].backgroundID
            if let bgIndex = stack.backgrounds.firstIndex(where: { $0.id == bgID }) {
                stackBinding.wrappedValue.backgrounds[bgIndex].showPicture = try flag()
            }
        default: throw Self.noSuchProperty(property, of: "a card")
        }
    }

    private func boolean(_ value: String, for property: String) throws -> Bool {
        switch value.lowercased() {
        case "true": return true
        case "false": return false
        default: throw HostError("The \(property) property must be true or false, not \"\(value)\".")
        }
    }

    private func number(_ value: String, for property: String) throws -> Double {
        guard let number = Double(value.trimmingCharacters(in: .whitespaces)), number.isFinite else {
            throw HostError("The \(property) property needs a number, not \"\(value)\".")
        }
        return number
    }

    /// A comma-separated list of exactly `count` numbers ("10,20,110,70").
    private func numberList(_ value: String, count: Int, for property: String) throws -> [Double] {
        let numbers = value.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == count, numbers.allSatisfy(\.isFinite) else {
            throw HostError("The \(property) property needs \(count) numbers separated by commas, not \"\(value)\".")
        }
        return numbers
    }

    private func numberText(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    private static func noSuchProperty(_ property: String, of what: String) -> HostError {
        HostError("There is no property \"\(property)\" of \(what == "this stack" || what == "this card" || what == "this background" || what == "a card" ? what : "a \(what)").")
    }

    // MARK: - Part lookup

    /// Card parts win over background parts, matching HyperCard's layering.
    private enum FieldLocation {
        case card(cardIndex: Int, partIndex: Int)
        case background(backgroundIndex: Int, partIndex: Int)
    }

    /// Finds a part of the given kind by name, ordinal, or permanent ID.
    /// Unqualified references search card parts first, then the
    /// background's; `card`/`background` qualifiers restrict the layer.
    private func locatePart(kind: String, domain: HyperTalkObject.PartDomain, reference: HyperTalkObject.Reference, onCard cardDestination: GoDestination? = nil) throws -> FieldLocation {
        let ci = try cardDestination.map { try resolveCardIndex($0) } ?? cardIndex
        let card = stack.cards[ci]
        let backgroundIndex = stack.backgrounds.firstIndex(where: { $0.id == card.backgroundID })
        func onCard() -> FieldLocation? {
            index(ofKind: kind, matching: reference, in: card.parts).map { .card(cardIndex: ci, partIndex: $0) }
        }
        func onBackground() -> FieldLocation? {
            guard let backgroundIndex,
                  let partIndex = index(ofKind: kind, matching: reference, in: stack.backgrounds[backgroundIndex].parts) else { return nil }
            return .background(backgroundIndex: backgroundIndex, partIndex: partIndex)
        }
        // Honor the requested layer, then fall back to the other: importing
        // moves buttons to the background and fields to the card, so a
        // `background field` / `card button` may live on the opposite layer.
        if domain != .background, let found = onCard() { return found }
        if domain != .card, let found = onBackground() { return found }
        if let found = onCard() ?? onBackground() { return found }
        let where_ = switch domain {
        case .any: "on this card"
        case .card: "on this card (card layer)"
        case .background: "on this background"
        }
        switch reference {
        case .named(let name):
            throw HostError("There is no \(kind) named \"\(name)\" \(where_).")
        case .number(let number):
            throw HostError("There is no \(kind) \(number) \(where_).")
        case .id(let id):
            throw HostError("There is no \(kind) with id \(id) \(where_).")
        }
    }

    /// Whether a part matches a referenced kind. The "part" pseudo-kind is a
    /// wildcard over buttons and fields (HyperCard's `cd part N` by z-order),
    /// matching the set `the number of parts` counts.
    private func matchesPartKind(_ part: Part, _ kind: String) -> Bool {
        if kind == "part" { return part.kind.word == "button" || part.kind.word == "field" }
        return part.kind.word == kind
    }

    private func index(ofKind kind: String, matching reference: HyperTalkObject.Reference, in parts: [Part]) -> Int? {
        switch reference {
        case .named(let name):
            return parts.firstIndex { part in
                matchesPartKind(part, kind) && part.name.caseInsensitiveCompare(name) == .orderedSame
            }
        case .number(let number):
            // Ordinal among parts of this kind, in part (z) order.
            guard number >= 1 else { return nil }
            var seen = 0
            for (index, part) in parts.enumerated() where matchesPartKind(part, kind) {
                seen += 1
                if seen == number { return index }
            }
            return nil
        case .id(let id):
            let wanted = id.trimmingCharacters(in: .whitespaces)
            return parts.firstIndex { part in
                matchesPartKind(part, kind) && String(part.scriptID) == wanted
            }
        }
    }

    /// A part's ordinal among its kind within its owning layer.
    private func ordinal(of location: FieldLocation, kind: String) -> Int {
        let parts: [Part]
        let partIndex: Int
        switch location {
        case .card(let ci, let index):
            parts = stack.cards[ci].parts
            partIndex = index
        case .background(let backgroundIndex, let index):
            parts = stack.backgrounds[backgroundIndex].parts
            partIndex = index
        }
        var seen = 0
        for (index, part) in parts.enumerated() where matchesPartKind(part, kind) {
            seen += 1
            if index == partIndex { return seen }
        }
        return seen
    }

    private func setPart(_ part: Part, at location: FieldLocation) {
        switch location {
        case .card(let ci, let partIndex):
            stackBinding.wrappedValue.cards[ci].parts[partIndex] = part
        case .background(let backgroundIndex, let partIndex):
            stackBinding.wrappedValue.backgrounds[backgroundIndex].parts[partIndex] = part
        }
    }

    /// Clears the hilite of every OTHER same-family button on `location`'s
    /// layer — HyperCard's family exclusivity when a member's hilite is SET
    /// true from script (the click path's twin lives in ContentView).
    private func clearFamilyHiliteSiblings(of part: Part, family: Int, at location: FieldLocation) {
        func clear(_ parts: inout [Part]) {
            for index in parts.indices where parts[index].id != part.id {
                guard case .button(var sibling) = parts[index].kind, sibling.family == family,
                      sibling.hilite else { continue }
                sibling.hilite = false
                parts[index].kind = .button(sibling)
            }
        }
        switch location {
        case .card(let ci, _):
            clear(&stackBinding.wrappedValue.cards[ci].parts)
        case .background(let backgroundIndex, _):
            clear(&stackBinding.wrappedValue.backgrounds[backgroundIndex].parts)
        }
    }

    private func part(at location: FieldLocation) -> Part {
        switch location {
        case .card(let ci, let partIndex):
            stack.cards[ci].parts[partIndex]
        case .background(let backgroundIndex, let partIndex):
            stack.backgrounds[backgroundIndex].parts[partIndex]
        }
    }

    /// The part as seen from a card: a non-sharedText background field carries
    /// that card's text and runs from the overlay (missing entry = empty).
    private func effectivePart(at location: FieldLocation, cardIndex ci: Int) -> Part {
        var found = part(at: location)
        guard case .background = location, case .field(var props) = found.kind, !props.sharedText else { return found }
        let content = stack.cards[ci].backgroundFieldContent[found.id.uuidString]
        props.text = content?.text ?? ""
        props.styleRuns = content?.styleRuns ?? []
        found.kind = .field(props)
        return found
    }

    /// Whether text/runs at this location live in the per-card overlay.
    private func usesOverlay(_ location: FieldLocation) -> Bool {
        guard case .background = location, case .field(let props) = part(at: location).kind else { return false }
        return !props.sharedText
    }

    private func writeOverlay(text: String? = nil, runs: [StyleRun]? = nil, partID: UUID, cardIndex ci: Int) {
        var content = stack.cards[ci].backgroundFieldContent[partID.uuidString] ?? BackgroundFieldContent()
        if let text { content.text = text }
        if let runs { content.styleRuns = runs }
        stackBinding.wrappedValue.cards[ci].backgroundFieldContent[partID.uuidString] = content
    }

    private func setKind(_ kind: PartKind, at location: FieldLocation) {
        switch location {
        case .card(let ci, let partIndex):
            stackBinding.wrappedValue.cards[ci].parts[partIndex].kind = kind
        case .background(let backgroundIndex, let partIndex):
            stackBinding.wrappedValue.backgrounds[backgroundIndex].parts[partIndex].kind = kind
        }
    }
}
