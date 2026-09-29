//
//  Stack.swift
//  Contrapt
//

import Foundation

/// The stack document model: Stack → Background/Card → Part.
///
/// These types define the on-disk exchange format (DECISIONS.md D4), so the
/// JSON they produce is treated as public API: stable named fields, a
/// discriminated-union encoding for parts, and a format version gate.

nonisolated enum StackFormat {
    /// Version of the stack file format this build reads and writes.
    static let currentVersion = 1
}

// MARK: - Geometry

/// Logical card dimensions in points (D3: fixed card size, scaled to fit).
/// A distinct type rather than CGSize so the JSON encodes stable named fields.
nonisolated struct CardSize: Codable, Hashable {
    var width: Double
    var height: Double
}

/// A named card-size choice for the Stack inspector — HyperCard's classic
/// sizes (Classic 9″ is the original compact-Mac screen) plus modern ones.
nonisolated struct CardSizePreset: Identifiable, Hashable {
    let name: String
    let size: CardSize
    var id: String { name }

    static let all: [CardSizePreset] = [
        CardSizePreset(name: "Classic (9″)", size: CardSize(width: 512, height: 342)),
        CardSizePreset(name: "Small", size: CardSize(width: 416, height: 240)),
        CardSizePreset(name: "PowerBook", size: CardSize(width: 640, height: 400)),
        CardSizePreset(name: "Large", size: CardSize(width: 640, height: 480)),
        CardSizePreset(name: "iPad Landscape", size: CardSize(width: 1024, height: 768)),
        CardSizePreset(name: "iPad Portrait", size: CardSize(width: 768, height: 1024)),
        CardSizePreset(name: "Widescreen", size: CardSize(width: 1280, height: 720)),
        CardSizePreset(name: "Square", size: CardSize(width: 768, height: 768)),
    ]
}

/// A part's position and size in logical card coordinates.
nonisolated struct PartFrame: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

// MARK: - Stack hierarchy

nonisolated struct Stack: Identifiable, Hashable {
    var formatVersion: Int
    var id: UUID
    var name: String
    var cardSize: CardSize
    var script: String
    var backgrounds: [Background]
    var cards: [Card]
    /// Allocator for scriptIDs — the short permanent numbers scripts use
    /// (`button id 6`). Never decremented; IDs are never reused.
    var nextID: Int = 1
    /// Opens the stack full-screen, filling the space around the card with
    /// `paddingColor` and hiding the app chrome — like classic HyperCard
    /// taking over the screen. Scriptable as `the fullScreen of this stack`.
    var isFullScreen: Bool = false
    /// The fill behind the card in full-screen mode: a color name (black,
    /// white, gray, …) or #RRGGBB hex. `the paddingColor of this stack`.
    var paddingColor: String = "black"
    /// Present the card at its true point size (1:1) rather than scaled to
    /// fill the window — the classic small HyperCard card on a desktop.
    /// Imported stacks set this for an "original size" import.
    var presentAtActualSize: Bool = false
    /// The names of the stack's XCMD/XFCN externals, recorded at import from
    /// the legacy stack's resource fork. Contrapt can't run the compiled
    /// code; the interpreter no-ops calls to these names (functions return
    /// empty) instead of raising "Can't understand".
    var externalCommands: [String] = []

    /// Claims the next permanent scriptID.
    mutating func claimScriptID() -> Int {
        let id = max(nextID, 1)
        nextID = id + 1
        return id
    }
}

extension Stack: Codable {
    private enum CodingKeys: String, CodingKey {
        case formatVersion, id, name, cardSize, script, backgrounds, cards, nextID
        case isFullScreen, paddingColor, presentAtActualSize, externalCommands
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        cardSize = try container.decode(CardSize.self, forKey: .cardSize)
        script = try container.decode(String.self, forKey: .script)
        backgrounds = try container.decode([Background].self, forKey: .backgrounds)
        cards = try container.decode([Card].self, forKey: .cards)
        nextID = try container.decodeIfPresent(Int.self, forKey: .nextID) ?? 1
        isFullScreen = try container.decodeIfPresent(Bool.self, forKey: .isFullScreen) ?? false
        paddingColor = try container.decodeIfPresent(String.self, forKey: .paddingColor) ?? "black"
        presentAtActualSize = try container.decodeIfPresent(Bool.self, forKey: .presentAtActualSize) ?? false
        externalCommands = try container.decodeIfPresent([String].self, forKey: .externalCommands) ?? []
    }
}

nonisolated struct Background: Identifiable, Hashable {
    var id: UUID
    var name: String
    var script: String
    var parts: [Part]
    /// The background's paint layer, beneath everything on every card
    /// sharing this background (same pair as Card's).
    var paintDrawingAsset: String? = nil
    var paintImageAsset: String? = nil
    /// Permanent short ID for scripts; assigned by the stack's allocator.
    var scriptID: Int = 0
    /// HyperCard's Background Info checkboxes, also script properties.
    var cantDelete: Bool = false
    var dontSearch: Bool = false
}

extension Background: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, script, parts, paintDrawingAsset, paintImageAsset, scriptID
        case cantDelete, dontSearch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        script = try container.decode(String.self, forKey: .script)
        parts = try container.decode([Part].self, forKey: .parts)
        paintDrawingAsset = try container.decodeIfPresent(String.self, forKey: .paintDrawingAsset)
        paintImageAsset = try container.decodeIfPresent(String.self, forKey: .paintImageAsset)
        scriptID = try container.decodeIfPresent(Int.self, forKey: .scriptID) ?? 0
        cantDelete = try container.decodeIfPresent(Bool.self, forKey: .cantDelete) ?? false
        dontSearch = try container.decodeIfPresent(Bool.self, forKey: .dontSearch) ?? false
    }
}

nonisolated struct Card: Identifiable, Hashable {
    var id: UUID
    var name: String
    var backgroundID: UUID
    var script: String
    var parts: [Part]
    /// The card's paint layer (Phase 6): the editable PencilKit drawing,
    /// and its rendered PNG for display and for viewing unzipped stacks
    /// anywhere. Both live in the archive's assets.
    var paintDrawingAsset: String? = nil
    var paintImageAsset: String? = nil
    /// Permanent short ID for scripts; assigned by the stack's allocator.
    var scriptID: Int = 0
    /// HyperCard's Card Info checkboxes, also script properties.
    var isMarked: Bool = false
    var cantDelete: Bool = false
    var dontSearch: Bool = false
    /// A per-card accent: the color of rich-field links and button icon/label
    /// text on this card. A color name or #RRGGBB hex; nil follows the app
    /// accent. Scriptable as `the highlightColor of this card`.
    var highlightColor: String? = nil
}

extension Card: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, backgroundID, script, parts, paintDrawingAsset, paintImageAsset, scriptID
        case isMarked, cantDelete, dontSearch, highlightColor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        backgroundID = try container.decode(UUID.self, forKey: .backgroundID)
        script = try container.decode(String.self, forKey: .script)
        parts = try container.decode([Part].self, forKey: .parts)
        paintDrawingAsset = try container.decodeIfPresent(String.self, forKey: .paintDrawingAsset)
        paintImageAsset = try container.decodeIfPresent(String.self, forKey: .paintImageAsset)
        scriptID = try container.decodeIfPresent(Int.self, forKey: .scriptID) ?? 0
        isMarked = try container.decodeIfPresent(Bool.self, forKey: .isMarked) ?? false
        cantDelete = try container.decodeIfPresent(Bool.self, forKey: .cantDelete) ?? false
        dontSearch = try container.decodeIfPresent(Bool.self, forKey: .dontSearch) ?? false
        highlightColor = try container.decodeIfPresent(String.self, forKey: .highlightColor)
    }
}

// MARK: - Parts

/// A widget placed on a card or background, rendered as a native SwiftUI
/// control at runtime (D5). Style properties are added per-kind later, with
/// nil meaning "native default" — mirroring the skin philosophy (D8).
nonisolated struct Part: Identifiable, Hashable {
    var id: UUID
    var name: String
    var frame: PartFrame
    var script: String
    var kind: PartKind
    /// Hidden parts don't render or take taps in browse mode (scriptable
    /// via `set the visible of … to false`); edit mode shows them ghosted.
    var isVisible: Bool = true
    /// Permanent short ID for scripts (`button id 6`); assigned by the
    /// stack's allocator, stable across renames, never reused.
    var scriptID: Int = 0
    /// Locked parts can't be selected, moved, or resized in edit mode — a
    /// guard against nudging finished art. It only affects editing (browse
    /// mode is unchanged); the Reveal menu's "Select Locked Objects" lets you
    /// pick one to unlock.
    var isLocked: Bool = false
}

nonisolated enum PartKind: Hashable {
    case button(ButtonPart)
    case field(FieldPart)
    case label(LabelPart)
    case image(ImagePart)

    /// The word scripts and the UI use for this kind.
    var word: String {
        switch self {
        case .button: "button"
        case .field: "field"
        case .label: "label"
        case .image: "image"
        }
    }
}

/// HyperCard's button styles.
nonisolated enum ButtonStyleKind: String, Codable, CaseIterable, Hashable {
    case roundRect
    case rectangle
    case shadow
    case opaque
    case transparent
    case checkbox
    case radio

    var label: String {
        switch self {
        case .roundRect: "Round Rect"
        case .rectangle: "Rectangle"
        case .shadow: "Shadow"
        case .opaque: "Opaque"
        case .transparent: "Transparent"
        case .checkbox: "Check Box"
        case .radio: "Radio Button"
        }
    }

    /// Check box and radio carry a persistent on/off (hilite) state and
    /// toggle it when tapped, rather than highlighting momentarily.
    var isToggle: Bool { self == .checkbox || self == .radio }

    /// Lenient parse for scripts: accepts the raw case, the display label,
    /// with or without spaces ("check box", "checkBox", "roundRect").
    static func parse(_ text: String) -> ButtonStyleKind? {
        let normalized = text.lowercased().replacingOccurrences(of: " ", with: "")
        return allCases.first {
            $0.rawValue.lowercased() == normalized
                || $0.label.lowercased().replacingOccurrences(of: " ", with: "") == normalized
        }
    }
}

nonisolated struct ButtonPart: Hashable {
    var title: String
    /// Whether the title draws (off = a nameless button / hot-zone).
    var showName: Bool
    /// Whether the button highlights while pressed.
    var autoHilite: Bool
    var style: ButtonStyleKind
    /// The persistent on/off state — the check/selection for check-box and
    /// radio styles; scriptable as `the hilite of button`.
    var hilite: Bool
    /// The title's text formatting (font design/size/style), like a field's.
    var format: TextFormat
    /// An icon image drawn on the button (asset name), e.g. an imported
    /// HyperCard button icon. Nil for a plain text button.
    var iconAsset: String?
    /// An SF Symbol name drawn on the button — the authoring icon library, an
    /// alternative to a bundled bitmap. `iconAsset` (an imported PNG) wins when
    /// both are set. Nil for no symbol.
    var iconSymbol: String?

    init(title: String, showName: Bool = true, autoHilite: Bool = true,
         style: ButtonStyleKind = .roundRect, hilite: Bool = false, format: TextFormat = TextFormat(),
         iconAsset: String? = nil, iconSymbol: String? = nil) {
        self.title = title
        self.showName = showName
        self.autoHilite = autoHilite
        self.style = style
        self.hilite = hilite
        self.format = format
        self.iconAsset = iconAsset
        self.iconSymbol = iconSymbol
    }
}

/// Manual Codable so older manifests without the new fields still decode.
extension ButtonPart: Codable {
    private enum CodingKeys: String, CodingKey { case title, showName, autoHilite, style, hilite, format, iconAsset, iconSymbol }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        showName = try container.decodeIfPresent(Bool.self, forKey: .showName) ?? true
        autoHilite = try container.decodeIfPresent(Bool.self, forKey: .autoHilite) ?? true
        style = try container.decodeIfPresent(ButtonStyleKind.self, forKey: .style) ?? .roundRect
        hilite = try container.decodeIfPresent(Bool.self, forKey: .hilite) ?? false
        format = try container.decodeIfPresent(TextFormat.self, forKey: .format) ?? TextFormat()
        iconAsset = try container.decodeIfPresent(String.self, forKey: .iconAsset)
        iconSymbol = try container.decodeIfPresent(String.self, forKey: .iconSymbol)
    }
}

/// A typeface family, mapped to a SwiftUI Font.Design (guaranteed on every
/// platform without bundling fonts).
nonisolated enum FontDesign: String, Codable, CaseIterable, Hashable {
    case standard, serif, monospaced, rounded

    var label: String {
        switch self {
        case .standard: "System"
        case .serif: "Serif"
        case .monospaced: "Monospaced"
        case .rounded: "Rounded"
        }
    }
}

nonisolated enum TextAlign: String, Codable, CaseIterable, Hashable {
    case left, center, right
    var label: String { rawValue.capitalized }
}

/// Whole-object text formatting — HyperCard's field-level textFont/Size/
/// Style/Align. Shared so labels can adopt it later.
nonisolated struct TextFormat: Hashable {
    var fontDesign: FontDesign = .standard
    var size: Double = 17
    var isBold = false
    var isItalic = false
    var isUnderline = false
    /// HyperCard's outline text style: white glyph interiors with a black
    /// stroke — the classic trick for white titles over black paint bars.
    var isOutline = false
    var align: TextAlign = .left
}

extension TextFormat: Codable {
    private enum CodingKeys: String, CodingKey {
        case fontDesign, size, isBold, isItalic, isUnderline, isOutline, align
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontDesign = try container.decodeIfPresent(FontDesign.self, forKey: .fontDesign) ?? .standard
        size = try container.decodeIfPresent(Double.self, forKey: .size) ?? 17
        isBold = try container.decodeIfPresent(Bool.self, forKey: .isBold) ?? false
        isItalic = try container.decodeIfPresent(Bool.self, forKey: .isItalic) ?? false
        isUnderline = try container.decodeIfPresent(Bool.self, forKey: .isUnderline) ?? false
        isOutline = try container.decodeIfPresent(Bool.self, forKey: .isOutline) ?? false
        align = try container.decodeIfPresent(TextAlign.self, forKey: .align) ?? .left
    }
}

/// A field's mode. `plain` is the lightweight TextField/TextEditor — the
/// back-compat default, best for entry and unstyled text. `rich` renders
/// its text as Markdown (styling + trappable links) in a web view — heavier,
/// display-only, local content only.
nonisolated enum FieldKind: String, Codable {
    case plain
    case rich
}

/// A field's border/background, HyperCard's field style. `transparent` has
/// neither (text floats over the card); `opaque` fills but has no border;
/// `rectangle` fills with a border; `shadow` adds a drop shadow.
nonisolated enum FieldStyle: String, Codable, CaseIterable, Hashable {
    case transparent
    case opaque
    case rectangle
    case shadow

    var label: String { rawValue.capitalized }
}

nonisolated struct FieldPart: Hashable {
    /// For plain fields this is the entered text; for rich fields it's the
    /// Markdown source, rendered for display.
    var text: String
    var placeholder: String
    /// Multi-line fields render as a text area filling their frame, like
    /// HyperCard fields; single-line fields are compact entry boxes.
    var isMultiline: Bool
    var format: TextFormat
    var kind: FieldKind
    /// HyperCard Field Info options (plain fields). `lockText` makes the
    /// field non-editable — a tap sends mouseUp to its script, like a button.
    /// `showLines` draws baseline rules; `wideMargins` adds inner padding.
    var lockText: Bool
    var showLines: Bool
    var wideMargins: Bool
    /// The field's border/background style.
    var style: FieldStyle
    /// Imported HyperCard line height in points (nil = the font's natural
    /// height). Lets tightly-set stacks (the Tour packs 12 lines of 18pt
    /// Palatino into 250px at textHeight 20) keep their vertical layout.
    var textHeight: Double?

    init(text: String, placeholder: String, isMultiline: Bool = false, format: TextFormat = TextFormat(), kind: FieldKind = .plain, lockText: Bool = false, showLines: Bool = false, wideMargins: Bool = false, style: FieldStyle = .rectangle) {
        self.text = text
        self.placeholder = placeholder
        self.isMultiline = isMultiline
        self.format = format
        self.kind = kind
        self.lockText = lockText
        self.showLines = showLines
        self.wideMargins = wideMargins
        self.style = style
    }
}

/// Manual Codable so older manifests without the newer fields still decode.
extension FieldPart: Codable {
    private enum CodingKeys: String, CodingKey {
        case text, placeholder, isMultiline, format, kind, lockText, showLines, wideMargins, style, textHeight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        placeholder = try container.decode(String.self, forKey: .placeholder)
        isMultiline = try container.decodeIfPresent(Bool.self, forKey: .isMultiline) ?? false
        format = try container.decodeIfPresent(TextFormat.self, forKey: .format) ?? TextFormat()
        kind = try container.decodeIfPresent(FieldKind.self, forKey: .kind) ?? .plain
        lockText = try container.decodeIfPresent(Bool.self, forKey: .lockText) ?? false
        showLines = try container.decodeIfPresent(Bool.self, forKey: .showLines) ?? false
        wideMargins = try container.decodeIfPresent(Bool.self, forKey: .wideMargins) ?? false
        style = try container.decodeIfPresent(FieldStyle.self, forKey: .style) ?? .rectangle
        textHeight = try container.decodeIfPresent(Double.self, forKey: .textHeight)
    }
}

nonisolated struct LabelPart: Codable, Hashable {
    var text: String
}

/// References an image stored in the stack archive's assets (D4).
nonisolated struct ImagePart: Codable, Hashable {
    var assetName: String
}

// MARK: - Part coding

/// Custom Codable so a part encodes as `"type": "button"` plus a per-kind
/// payload object, rather than Swift's synthesized enum nesting — this JSON
/// is the exchange format and should read cleanly.
///
/// Adding a new part kind is a format change: bump `StackFormat.currentVersion`
/// so older builds refuse newer stacks instead of failing mid-decode.
extension Part: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, frame, script, type, button, field, label, image, visible, scriptID, locked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        frame = try container.decode(PartFrame.self, forKey: .frame)
        script = try container.decode(String.self, forKey: .script)
        isVisible = try container.decodeIfPresent(Bool.self, forKey: .visible) ?? true
        scriptID = try container.decodeIfPresent(Int.self, forKey: .scriptID) ?? 0
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "button":
            kind = .button(try container.decode(ButtonPart.self, forKey: .button))
        case "field":
            kind = .field(try container.decode(FieldPart.self, forKey: .field))
        case "label":
            kind = .label(try container.decode(LabelPart.self, forKey: .label))
        case "image":
            kind = .image(try container.decode(ImagePart.self, forKey: .image))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown part type '\(type)'"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(frame, forKey: .frame)
        try container.encode(script, forKey: .script)
        try container.encode(isVisible, forKey: .visible)
        try container.encode(scriptID, forKey: .scriptID)
        if isLocked { try container.encode(true, forKey: .locked) }
        switch kind {
        case .button(let properties):
            try container.encode("button", forKey: .type)
            try container.encode(properties, forKey: .button)
        case .field(let properties):
            try container.encode("field", forKey: .type)
            try container.encode(properties, forKey: .field)
        case .label(let properties):
            try container.encode("label", forKey: .type)
            try container.encode(properties, forKey: .label)
        case .image(let properties):
            try container.encode("image", forKey: .type)
            try container.encode(properties, forKey: .image)
        }
    }
}

// MARK: - Sanitizing untrusted stacks

nonisolated extension Stack {
    /// Repairs a decoded stack so that hostile or damaged files can't
    /// break the app (D7): geometry is clamped to finite, sane bounds;
    /// structural invariants (at least one background and one card, no
    /// dangling background references, unique IDs) are restored; and
    /// scripts are capped. Applied to every loaded document.
    func sanitized() -> Stack {
        var stack = self

        // Card size: finite and within reason.
        if !stack.cardSize.width.isFinite || !stack.cardSize.height.isFinite {
            stack.cardSize = CardSize(width: 1024, height: 768)
        }
        stack.cardSize.width = min(max(stack.cardSize.width, 200), 8192)
        stack.cardSize.height = min(max(stack.cardSize.height, 200), 8192)

        // Structural invariants.
        if stack.backgrounds.isEmpty {
            stack.backgrounds = [Background(id: UUID(), name: "Background 1", script: "", parts: [])]
        }
        if stack.cards.isEmpty {
            stack.cards = [Card(id: UUID(), name: "Card 1", backgroundID: stack.backgrounds[0].id, script: "", parts: [])]
        }
        // Unique IDs — duplicates make ForEach behavior undefined. When a
        // background is re-identified, references to it are remapped.
        var seen: Set<UUID> = []
        func uniqued(_ id: UUID) -> UUID {
            if seen.contains(id) { return UUID() }
            seen.insert(id)
            return id
        }
        stack.id = uniqued(stack.id)
        var backgroundRemap: [UUID: UUID] = [:]
        for index in stack.backgrounds.indices {
            let original = stack.backgrounds[index].id
            let unique = uniqued(original)
            if unique != original { backgroundRemap[original] = unique }
            stack.backgrounds[index].id = unique
            stack.backgrounds[index].parts = sanitizedParts(stack.backgrounds[index].parts, cardSize: stack.cardSize, uniqued: uniqued)
        }
        for index in stack.cards.indices {
            stack.cards[index].id = uniqued(stack.cards[index].id)
            if let mapped = backgroundRemap[stack.cards[index].backgroundID] {
                stack.cards[index].backgroundID = mapped
            }
            stack.cards[index].parts = sanitizedParts(stack.cards[index].parts, cardSize: stack.cardSize, uniqued: uniqued)
            stack.cards[index].script = Self.cappedScript(stack.cards[index].script)
        }

        // Dangling background references — repaired after re-identification.
        let backgroundIDs = Set(stack.backgrounds.map(\.id))
        for index in stack.cards.indices where !backgroundIDs.contains(stack.cards[index].backgroundID) {
            stack.cards[index].backgroundID = stack.backgrounds[0].id
        }
        stack.script = Self.cappedScript(stack.script)
        for index in stack.backgrounds.indices {
            stack.backgrounds[index].script = Self.cappedScript(stack.backgrounds[index].script)
        }

        // Permanent scriptIDs: keep valid unique ones, then assign the
        // missing or duplicated from above the maximum. This also migrates
        // stacks from before scriptIDs existed.
        var usedScriptIDs = Set<Int>()
        var maxScriptID = 0
        func validated(_ id: Int) -> Int {
            guard id > 0, !usedScriptIDs.contains(id) else { return 0 }
            usedScriptIDs.insert(id)
            maxScriptID = max(maxScriptID, id)
            return id
        }
        for index in stack.backgrounds.indices {
            stack.backgrounds[index].scriptID = validated(stack.backgrounds[index].scriptID)
            for partIndex in stack.backgrounds[index].parts.indices {
                stack.backgrounds[index].parts[partIndex].scriptID = validated(stack.backgrounds[index].parts[partIndex].scriptID)
            }
        }
        for index in stack.cards.indices {
            stack.cards[index].scriptID = validated(stack.cards[index].scriptID)
            for partIndex in stack.cards[index].parts.indices {
                stack.cards[index].parts[partIndex].scriptID = validated(stack.cards[index].parts[partIndex].scriptID)
            }
        }
        var nextAssignable = maxScriptID + 1
        func assigned() -> Int {
            defer { nextAssignable += 1 }
            return nextAssignable
        }
        for index in stack.backgrounds.indices {
            if stack.backgrounds[index].scriptID == 0 { stack.backgrounds[index].scriptID = assigned() }
            for partIndex in stack.backgrounds[index].parts.indices where stack.backgrounds[index].parts[partIndex].scriptID == 0 {
                stack.backgrounds[index].parts[partIndex].scriptID = assigned()
            }
        }
        for index in stack.cards.indices {
            if stack.cards[index].scriptID == 0 { stack.cards[index].scriptID = assigned() }
            for partIndex in stack.cards[index].parts.indices where stack.cards[index].parts[partIndex].scriptID == 0 {
                stack.cards[index].parts[partIndex].scriptID = assigned()
            }
        }
        stack.nextID = max(stack.nextID, nextAssignable)

        return stack
    }

    private func sanitizedParts(_ parts: [Part], cardSize: CardSize, uniqued: (UUID) -> UUID) -> [Part] {
        parts.map { part in
            var part = part
            part.id = uniqued(part.id)
            part.script = Self.cappedScript(part.script)
            var frame = part.frame
            if !frame.x.isFinite { frame.x = 0 }
            if !frame.y.isFinite { frame.y = 0 }
            if !frame.width.isFinite { frame.width = 100 }
            if !frame.height.isFinite { frame.height = 44 }
            frame.width = min(max(frame.width, 16), cardSize.width)
            frame.height = min(max(frame.height, 16), cardSize.height)
            frame.x = min(max(frame.x, 0), cardSize.width - 16)
            frame.y = min(max(frame.y, 0), cardSize.height - 16)
            part.frame = frame
            return part
        }
    }

    /// A script longer than any plausible hand-written one is truncated
    /// rather than fed to the tokenizer wholesale.
    private static func cappedScript(_ script: String) -> String {
        script.count > 1_000_000 ? String(script.prefix(1_000_000)) : script
    }
}

// MARK: - Assets

nonisolated extension Stack {
    /// Every asset name the stack still references; unreferenced assets
    /// are dropped at save time.
    func referencedAssetNames() -> Set<String> {
        var names: Set<String> = []
        func collect(_ part: Part) {
            switch part.kind {
            case .image(let image): names.insert(image.assetName)
            case .button(let button): if let icon = button.iconAsset { names.insert(icon) }
            default: break
            }
        }
        for card in cards {
            if let paint = card.paintDrawingAsset { names.insert(paint) }
            if let paint = card.paintImageAsset { names.insert(paint) }
            card.parts.forEach(collect)
        }
        for background in backgrounds {
            if let paint = background.paintDrawingAsset { names.insert(paint) }
            if let paint = background.paintImageAsset { names.insert(paint) }
            background.parts.forEach(collect)
        }
        return names
    }
}
