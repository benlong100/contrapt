//
//  EngineModel.swift
//  HyperTalkEngine
//
//  A lean, Foundation-only mirror of the exported `stack.json` — just the
//  fields scripts read and write. It decodes the same JSON the app's `Stack`
//  produces (the on-disk exchange format, treated as public API), ignoring the
//  parts the runtime doesn't need (paint assets, geometry it never renders).
//
//  It is deliberately a SEPARATE model from the app's `Stack`: this target must
//  stay platform-agnostic (Wasm-portable), and the app model pulls in editing
//  concerns. The seam between them is the JSON. If the app adds a field scripts
//  can touch, mirror it here too.
//

import Foundation
import HyperTalk

// MARK: - Geometry

struct CardSize: Codable, Hashable {
    var width: Double
    var height: Double
}

struct PartFrame: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

// MARK: - Text formatting

enum FontDesign: String, Codable, CaseIterable { case standard, serif, monospaced, rounded
    var label: String {
        switch self {
        case .standard: "System"
        case .serif: "Serif"
        case .monospaced: "Monospaced"
        case .rounded: "Rounded"
        }
    }
}

enum TextAlign: String, Codable, CaseIterable { case left, center, right }

struct TextFormat: Codable, Hashable {
    var fontDesign: FontDesign = .standard
    var size: Double = 17
    var isBold = false
    var isItalic = false
    var isUnderline = false
    var isOutline = false
    /// HyperCard's "group" text style — no glyph effect, but a click in a
    /// grouped run makes `the clickText` return the whole run. The web player
    /// reads this (and the per-run styleRuns) to compute clickText in-browser.
    var isGroup = false
    var align: TextAlign = .left

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fontDesign = try c.decodeIfPresent(FontDesign.self, forKey: .fontDesign) ?? .standard
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? 17
        isBold = try c.decodeIfPresent(Bool.self, forKey: .isBold) ?? false
        isItalic = try c.decodeIfPresent(Bool.self, forKey: .isItalic) ?? false
        isUnderline = try c.decodeIfPresent(Bool.self, forKey: .isUnderline) ?? false
        isOutline = try c.decodeIfPresent(Bool.self, forKey: .isOutline) ?? false
        isGroup = try c.decodeIfPresent(Bool.self, forKey: .isGroup) ?? false
        align = try c.decodeIfPresent(TextAlign.self, forKey: .align) ?? .left
    }
}

// MARK: - Part kinds

enum ButtonStyleKind: String, Codable, CaseIterable {
    case roundRect, rectangle, shadow, opaque, transparent, checkbox, radio

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

    var isToggle: Bool { self == .checkbox || self == .radio }

    static func parse(_ text: String) -> ButtonStyleKind? {
        let normalized = text.lowercased().replacingOccurrences(of: " ", with: "")
        return allCases.first {
            $0.rawValue.lowercased() == normalized
                || $0.label.lowercased().replacingOccurrences(of: " ", with: "") == normalized
        }
    }
}

enum FieldKind: String, Codable { case plain, rich }

enum FieldStyle: String, Codable, CaseIterable { case transparent, opaque, rectangle, shadow, scrolling }

struct ButtonPart: Codable, Hashable {
    var title: String
    var showName: Bool
    var autoHilite: Bool
    var style: ButtonStyleKind
    var hilite: Bool
    var format: TextFormat
    var iconAsset: String?
    /// The button wants an icon the import couldn't find — the player shows a
    /// placeholder instead of nothing.
    var iconMissing: Bool
    /// Custom fill/edge/title colors (a color name or #RRGGBB) — `the
    /// fillColor` / `the borderColor` / `the textColor of button`. Nil keeps
    /// the themed default look.
    var fillColor: String?
    var borderColor: String?
    var textColor: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        showName = try c.decodeIfPresent(Bool.self, forKey: .showName) ?? true
        autoHilite = try c.decodeIfPresent(Bool.self, forKey: .autoHilite) ?? true
        style = try c.decodeIfPresent(ButtonStyleKind.self, forKey: .style) ?? .roundRect
        hilite = try c.decodeIfPresent(Bool.self, forKey: .hilite) ?? false
        format = try c.decodeIfPresent(TextFormat.self, forKey: .format) ?? TextFormat()
        iconAsset = try c.decodeIfPresent(String.self, forKey: .iconAsset)
        iconMissing = try c.decodeIfPresent(Bool.self, forKey: .iconMissing) ?? false
        fillColor = try c.decodeIfPresent(String.self, forKey: .fillColor)
        borderColor = try c.decodeIfPresent(String.self, forKey: .borderColor)
        textColor = try c.decodeIfPresent(String.self, forKey: .textColor)
    }
}

struct FieldPart: Codable, Hashable {
    var text: String
    var placeholder: String
    var isMultiline: Bool
    var format: TextFormat
    var kind: FieldKind
    var lockText: Bool
    var showLines: Bool
    var wideMargins: Bool
    var style: FieldStyle
    var dontWrap: Bool
    var autoTab: Bool
    var autoSelect: Bool
    var multipleLines: Bool
    var fixedLineHeight: Bool
    var styleRuns: [StyleRun]
    /// HyperCard's sharedText — one text on every card; false means the text
    /// lives per card in Card.backgroundFieldContent.
    var sharedText: Bool
    /// `the scroll of field` — scrolling fields' offset in points.
    var scroll: Double
    /// `the textHeight of field` — line height in points (nil = natural).
    var textHeight: Double?
    /// Custom whole-field text/border colors — `the textColor` / `the
    /// borderColor of field`. Nil keeps the themed default.
    var textColor: String?
    var borderColor: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        placeholder = try c.decodeIfPresent(String.self, forKey: .placeholder) ?? ""
        isMultiline = try c.decodeIfPresent(Bool.self, forKey: .isMultiline) ?? false
        format = try c.decodeIfPresent(TextFormat.self, forKey: .format) ?? TextFormat()
        kind = try c.decodeIfPresent(FieldKind.self, forKey: .kind) ?? .plain
        lockText = try c.decodeIfPresent(Bool.self, forKey: .lockText) ?? false
        showLines = try c.decodeIfPresent(Bool.self, forKey: .showLines) ?? false
        wideMargins = try c.decodeIfPresent(Bool.self, forKey: .wideMargins) ?? false
        style = try c.decodeIfPresent(FieldStyle.self, forKey: .style) ?? .rectangle
        dontWrap = try c.decodeIfPresent(Bool.self, forKey: .dontWrap) ?? false
        autoTab = try c.decodeIfPresent(Bool.self, forKey: .autoTab) ?? false
        autoSelect = try c.decodeIfPresent(Bool.self, forKey: .autoSelect) ?? false
        multipleLines = try c.decodeIfPresent(Bool.self, forKey: .multipleLines) ?? false
        fixedLineHeight = try c.decodeIfPresent(Bool.self, forKey: .fixedLineHeight) ?? false
        styleRuns = try c.decodeIfPresent([StyleRun].self, forKey: .styleRuns) ?? []
        sharedText = try c.decodeIfPresent(Bool.self, forKey: .sharedText) ?? false
        scroll = try c.decodeIfPresent(Double.self, forKey: .scroll) ?? 0
        textHeight = try c.decodeIfPresent(Double.self, forKey: .textHeight)
        textColor = try c.decodeIfPresent(String.self, forKey: .textColor)
        borderColor = try c.decodeIfPresent(String.self, forKey: .borderColor)
    }
}

/// The per-card content of a non-sharedText background field, keyed in
/// Card.backgroundFieldContent by the part's UUID string (app-model parity).
struct BackgroundFieldContent: Codable, Hashable {
    var text: String
    var styleRuns: [StyleRun]

    init(text: String = "", styleRuns: [StyleRun] = []) {
        self.text = text
        self.styleRuns = styleRuns
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        styleRuns = try c.decodeIfPresent([StyleRun].self, forKey: .styleRuns) ?? []
    }

    private enum CodingKeys: String, CodingKey { case text, styleRuns }
}

/// Per-run styled text — a Character offset into the field's text plus the
/// format from there. Carried for parity with the app model; the web player's
/// CSS rendering of runs is not built yet.
struct StyleRun: Codable, Hashable {
    var start: Int
    var format: TextFormat
}

struct LabelPart: Codable, Hashable { var text: String }

struct ImagePart: Codable, Hashable { var assetName: String }

enum PartKind: Hashable {
    case button(ButtonPart)
    case field(FieldPart)
    case label(LabelPart)
    case image(ImagePart)

    var word: String {
        switch self {
        case .button: "button"
        case .field: "field"
        case .label: "label"
        case .image: "image"
        }
    }
}

struct Part: Hashable {
    var id: UUID
    var name: String
    var frame: PartFrame
    var script: String
    var kind: PartKind
    var isVisible: Bool = true
    var isEnabled: Bool = true
    var scriptID: Int = 0
}

extension Part: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, frame, script, type, button, field, label, image, visible, scriptID, enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        frame = try c.decode(PartFrame.self, forKey: .frame)
        script = try c.decodeIfPresent(String.self, forKey: .script) ?? ""
        isVisible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? true
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        scriptID = try c.decodeIfPresent(Int.self, forKey: .scriptID) ?? 0
        switch try c.decode(String.self, forKey: .type) {
        case "button": kind = .button(try c.decode(ButtonPart.self, forKey: .button))
        case "field": kind = .field(try c.decode(FieldPart.self, forKey: .field))
        case "label": kind = .label(try c.decode(LabelPart.self, forKey: .label))
        case "image": kind = .image(try c.decode(ImagePart.self, forKey: .image))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c,
                                                    debugDescription: "Unknown part type '\(other)'")
        }
    }

    // The engine never re-encodes stacks (the app owns saving), so no encode().
    func encode(to encoder: Encoder) throws {
        throw EngineError("The web engine does not encode stacks.")
    }
}

// MARK: - Hierarchy

struct Background: Codable, Hashable {
    var id: UUID
    var name: String
    var script: String
    var parts: [Part]
    var scriptID: Int = 0
    var cantDelete: Bool = false
    var dontSearch: Bool = false
    /// `show/hide background picture` — whether the paint layer draws.
    var showPicture: Bool = true

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        script = try c.decodeIfPresent(String.self, forKey: .script) ?? ""
        parts = try c.decodeIfPresent([Part].self, forKey: .parts) ?? []
        scriptID = try c.decodeIfPresent(Int.self, forKey: .scriptID) ?? 0
        cantDelete = try c.decodeIfPresent(Bool.self, forKey: .cantDelete) ?? false
        dontSearch = try c.decodeIfPresent(Bool.self, forKey: .dontSearch) ?? false
        showPicture = try c.decodeIfPresent(Bool.self, forKey: .showPicture) ?? true
    }

    private enum CodingKeys: String, CodingKey { case id, name, script, parts, scriptID, cantDelete, dontSearch, showPicture }
    func encode(to encoder: Encoder) throws { throw EngineError("read-only") }

    init(id: UUID, name: String, script: String, parts: [Part]) {
        self.id = id; self.name = name; self.script = script; self.parts = parts
    }
}

struct Card: Codable, Hashable {
    var id: UUID
    var name: String
    var backgroundID: UUID
    var script: String
    var parts: [Part]
    var scriptID: Int = 0
    var isMarked: Bool = false
    var cantDelete: Bool = false
    var dontSearch: Bool = false
    var highlightColor: String? = nil
    /// `show/hide [card] picture` — whether the paint layer draws.
    var showPicture: Bool = true
    /// This card's text for each non-sharedText background field (part UUID →
    /// content) — the HyperCard storage model, mirrored from the app.
    var backgroundFieldContent: [String: BackgroundFieldContent] = [:]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        backgroundID = try c.decode(UUID.self, forKey: .backgroundID)
        script = try c.decodeIfPresent(String.self, forKey: .script) ?? ""
        parts = try c.decodeIfPresent([Part].self, forKey: .parts) ?? []
        scriptID = try c.decodeIfPresent(Int.self, forKey: .scriptID) ?? 0
        isMarked = try c.decodeIfPresent(Bool.self, forKey: .isMarked) ?? false
        cantDelete = try c.decodeIfPresent(Bool.self, forKey: .cantDelete) ?? false
        dontSearch = try c.decodeIfPresent(Bool.self, forKey: .dontSearch) ?? false
        highlightColor = try c.decodeIfPresent(String.self, forKey: .highlightColor)
        showPicture = try c.decodeIfPresent(Bool.self, forKey: .showPicture) ?? true
        backgroundFieldContent = try c.decodeIfPresent([String: BackgroundFieldContent].self, forKey: .backgroundFieldContent) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, backgroundID, script, parts, scriptID, isMarked, cantDelete, dontSearch, highlightColor
        case backgroundFieldContent, showPicture
    }
    func encode(to encoder: Encoder) throws { throw EngineError("read-only") }

    init(id: UUID, name: String, backgroundID: UUID, script: String, parts: [Part]) {
        self.id = id; self.name = name; self.backgroundID = backgroundID; self.script = script; self.parts = parts
    }
}

struct Stack: Hashable {
    var name: String
    var cardSize: CardSize
    var script: String
    var backgrounds: [Background]
    var cards: [Card]
    var nextID: Int
    var isFullScreen: Bool
    var paddingColor: String
    var presentAtActualSize: Bool
    /// The stack's built-in visual theme (`the theme of this stack`): "classic"
    /// (default), "light", or "dark". See ThemeSpec.
    var theme: String

    mutating func claimScriptID() -> Int {
        let id = max(nextID, 1)
        nextID = id + 1
        return id
    }
}

extension Stack: Codable {
    private enum CodingKeys: String, CodingKey {
        case name, cardSize, script, backgrounds, cards, nextID
        case isFullScreen, paddingColor, presentAtActualSize, theme
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        cardSize = try c.decode(CardSize.self, forKey: .cardSize)
        script = try c.decodeIfPresent(String.self, forKey: .script) ?? ""
        backgrounds = try c.decode([Background].self, forKey: .backgrounds)
        cards = try c.decode([Card].self, forKey: .cards)
        nextID = try c.decodeIfPresent(Int.self, forKey: .nextID) ?? 1
        isFullScreen = try c.decodeIfPresent(Bool.self, forKey: .isFullScreen) ?? false
        paddingColor = try c.decodeIfPresent(String.self, forKey: .paddingColor) ?? "black"
        presentAtActualSize = try c.decodeIfPresent(Bool.self, forKey: .presentAtActualSize) ?? false
        theme = ThemeSpec.canonicalName(try c.decodeIfPresent(String.self, forKey: .theme))
    }
    func encode(to encoder: Encoder) throws { throw EngineError("read-only") }
}

/// An engine-side failure (bad stack JSON, an unsupported operation).
struct EngineError: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
