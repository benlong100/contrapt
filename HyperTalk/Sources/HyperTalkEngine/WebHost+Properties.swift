//
//  WebHost+Properties.swift
//  HyperTalkEngine
//
//  Property get/set, part lookup, and date `convert` — ported from the app's
//  DocumentScriptHost so the exported runtime honors the same property
//  vocabulary (`the visible of button`, `the textStyle of field`, …).
//

import Foundation
import HyperTalk

extension WebHost {
    // MARK: - Property get/set

    func propertyValue(_ property: String, of object: HyperTalkObject) throws -> String {
        switch object {
        case .part(let kind, let domain, let reference, let onCard):
            let loc = try locatePart(kind: kind, domain: domain, reference: reference, onCard: onCard)
            if property == "number" { return String(ordinal(of: loc, kind: kind)) }
            let ci = try onCard.map { try resolveCardIndex($0) } ?? cardIndex
            return try partProperty(property, of: effectivePart(at: loc, cardIndex: ci), kind: kind)
        case .card(let destination):
            return try cardProperty(property, cardAt: try resolveCardIndex(destination))
        case .thisCard:
            return try cardProperty(property, cardAt: cardIndex)
        case .thisBackground:
            let card = stack.cards[cardIndex]
            guard let bg = stack.backgrounds.first(where: { $0.id == card.backgroundID }) else {
                throw HostError("This card has no background.")
            }
            switch property {
            case "name": return bg.name
            case "longname": return "bkgnd \"\(bg.name)\""
            case "longid": return "bkgnd id \(bg.scriptID)"
            case "id": return String(bg.scriptID)
            case "script": return bg.script
            case "cantdelete": return bg.cantDelete ? "true" : "false"
            case "dontsearch": return bg.dontSearch ? "true" : "false"
            case "showpict", "showbgpict": return bg.showPicture ? "true" : "false"
            default: throw Self.noSuchProperty(property, of: "this background")
            }
        case .thisStack:
            switch property {
            case "name": return stack.name
            case "longname", "longid": return "stack \"\(stack.name)\""
            case "script": return stack.script
            case "cards": return String(stack.cards.count)
            case "width": return numberText(stack.cardSize.width)
            case "height": return numberText(stack.cardSize.height)
            case "fullscreen": return stack.isFullScreen ? "true" : "false"
            case "paddingcolor": return stack.paddingColor
            // Unmodeled stack properties read benign defaults (the SET side
            // no-ops them too) so guards run.
            case "cantmodify", "cantabort", "cantpeek", "cantdelete", "usermodify": return "false"
            case "freesize", "size": return "0"
            default: throw Self.noSuchProperty(property, of: "this stack")
            }
        }
    }

    func setProperty(_ property: String, of object: HyperTalkObject, to value: String) throws {
        guard property != "id" else { throw HostError("The id of an object can't be changed.") }
        switch object {
        case .part(let kind, let domain, let reference, let onCard):
            let loc = try locatePart(kind: kind, domain: domain, reference: reference, onCard: onCard)
            if property == "text", usesOverlay(loc) {
                let ci = try onCard.map { try resolveCardIndex($0) } ?? cardIndex
                writeOverlay(text: value, partID: part(at: loc).id, cardIndex: ci)
                return
            }
            var updated = part(at: loc)
            try applyPartProperty(property, to: &updated, kind: kind, value: value)
            setPart(updated, at: loc)
        case .card(let destination):
            try setCardProperty(property, cardAt: try resolveCardIndex(destination), to: value)
        case .thisCard:
            try setCardProperty(property, cardAt: cardIndex, to: value)
        case .thisBackground:
            let card = stack.cards[cardIndex]
            guard let i = stack.backgrounds.firstIndex(where: { $0.id == card.backgroundID }) else {
                throw HostError("This card has no background.")
            }
            switch property {
            case "name": stack.backgrounds[i].name = value
            case "cantdelete": stack.backgrounds[i].cantDelete = try boolean(value, for: property)
            case "dontsearch": stack.backgrounds[i].dontSearch = try boolean(value, for: property)
            case "showpict", "showbgpict": stack.backgrounds[i].showPicture = try boolean(value, for: property)
            default: throw Self.noSuchProperty(property, of: "this background")
            }
        case .thisStack:
            switch property {
            case "name": stack.name = value
            case "width": stack.cardSize.width = try number(value, for: property)
            case "height": stack.cardSize.height = try number(value, for: property)
            case "fullscreen": stack.isFullScreen = try boolean(value, for: property)
            case "paddingcolor": stack.paddingColor = value
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
            guard case .button(let p) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return p.title
        case "showname":
            guard case .button(let p) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return p.showName ? "true" : "false"
        case "autohilite", "autohighlight":
            guard case .button(let p) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return p.autoHilite ? "true" : "false"
        case "style":
            switch part.kind {
            case .button(let p): return p.style.rawValue
            case .field(let p): return p.style.rawValue
            default: throw Self.noSuchProperty(property, of: kind)
            }
        case "hilite", "highlight":
            guard case .button(let p) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return p.hilite ? "true" : "false"
        case "text":
            switch part.kind {
            case .field(let p): return p.text
            case .label(let p): return p.text
            default: throw Self.noSuchProperty(property, of: kind)
            }
        case "placeholder":
            guard case .field(let p) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return p.placeholder
        case "textfont":
            guard let f = Self.format(of: part) else { throw Self.noSuchProperty(property, of: kind) }
            return f.fontDesign.rawValue
        case "textsize":
            guard let f = Self.format(of: part) else { throw Self.noSuchProperty(property, of: kind) }
            return numberText(f.size)
        case "textstyle":
            guard let f = Self.format(of: part) else { throw Self.noSuchProperty(property, of: kind) }
            return Self.styleList(f)
        case "textalign":
            guard let f = Self.format(of: part) else { throw Self.noSuchProperty(property, of: kind) }
            return f.align.rawValue
        case "locktext":
            guard case .field(let p) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return p.lockText ? "true" : "false"
        case "showlines":
            guard case .field(let p) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return p.showLines ? "true" : "false"
        case "widemargins":
            guard case .field(let p) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return p.wideMargins ? "true" : "false"
        case "dontwrap":
            guard case .field(let p) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return p.dontWrap ? "true" : "false"
        case "autotab":
            guard case .field(let p) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return p.autoTab ? "true" : "false"
        case "autoselect":
            guard case .field(let p) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return p.autoSelect ? "true" : "false"
        case "multiplelines":
            guard case .field(let p) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return p.multipleLines ? "true" : "false"
        case "fixedlineheight":
            guard case .field(let p) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return p.fixedLineHeight ? "true" : "false"
        case "enabled":
            return part.isEnabled ? "true" : "false"
        case "scroll":
            guard case .field(let p) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            return p.scroll == p.scroll.rounded() ? String(Int(p.scroll)) : String(p.scroll)
        default:
            throw Self.noSuchProperty(property, of: kind)
        }
    }

    private func applyPartProperty(_ property: String, to part: inout Part, kind: String, value: String) throws {
        switch property {
        case "name": part.name = value
        case "visible": part.isVisible = try boolean(value, for: property)
        case "enabled": part.isEnabled = try boolean(value, for: property)
        case "width": part.frame.width = max(16, try number(value, for: property))
        case "height": part.frame.height = max(16, try number(value, for: property))
        case "left": part.frame.x = try number(value, for: property)
        case "top": part.frame.y = try number(value, for: property)
        case "right": part.frame.x = try number(value, for: property) - part.frame.width
        case "bottom": part.frame.y = try number(value, for: property) - part.frame.height
        case "rect", "rectangle":
            let n = try numberList(value, count: 4, for: property)
            part.frame = PartFrame(x: n[0], y: n[1], width: max(16, n[2] - n[0]), height: max(16, n[3] - n[1]))
        case "loc", "location":
            let n = try numberList(value, count: 2, for: property)
            part.frame.x = n[0] - part.frame.width / 2
            part.frame.y = n[1] - part.frame.height / 2
        case "title":
            guard case .button(var p) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            p.title = value; part.kind = .button(p)
        case "showname":
            guard case .button(var p) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            p.showName = try boolean(value, for: property); part.kind = .button(p)
        case "autohilite", "autohighlight":
            guard case .button(var p) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            p.autoHilite = try boolean(value, for: property); part.kind = .button(p)
        case "style":
            switch part.kind {
            case .button(var p):
                guard let style = ButtonStyleKind.parse(value) else {
                    throw HostError("Unknown button style \"\(value)\". Try roundRect, rectangle, shadow, opaque, transparent, checkbox, or radio.")
                }
                p.style = style; part.kind = .button(p)
            case .field(var p):
                guard let style = FieldStyle(rawValue: value.lowercased().trimmingCharacters(in: .whitespaces)) else {
                    throw HostError("Unknown field style \"\(value)\". Try transparent, opaque, rectangle, or shadow.")
                }
                p.style = style; part.kind = .field(p)
            default: throw Self.noSuchProperty(property, of: kind)
            }
        case "hilite", "highlight":
            guard case .button(var p) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            p.hilite = try boolean(value, for: property); part.kind = .button(p)
        case "text":
            switch part.kind {
            case .field(var p): p.text = value; part.kind = .field(p)
            case .label(var p): p.text = value; part.kind = .label(p)
            default: throw Self.noSuchProperty(property, of: kind)
            }
        case "placeholder":
            guard case .field(var p) = part.kind else { throw Self.noSuchProperty(property, of: kind) }
            p.placeholder = value; part.kind = .field(p)
        case "textfont":
            try withFormat(&part, kind: kind) {
                guard let d = Self.parseFontDesign(value) else {
                    throw HostError("Unknown font \"\(value)\". Try system, serif, monospaced, or rounded.")
                }
                $0.fontDesign = d
            }
        case "textsize":
            let size = try number(value, for: property)
            try withFormat(&part, kind: kind) { $0.size = min(max(size, 4), 256) }
        case "textstyle":
            try withFormat(&part, kind: kind) { Self.applyStyleList(value, to: &$0) }
        case "textalign":
            guard let align = TextAlign(rawValue: value.lowercased().trimmingCharacters(in: .whitespaces)) else {
                throw HostError("Unknown alignment \"\(value)\". Try left, center, or right.")
            }
            try withFormat(&part, kind: kind) { $0.align = align }
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
            // Accepted and ignored — background fields inherently share text.
            _ = try boolean(value, for: property)
        case "scroll":
            let offset = max(0, try number(value, for: property))
            try withField(&part, kind: kind) { $0.scroll = offset }
        default:
            throw Self.noSuchProperty(property, of: kind)
        }
    }

    private func withField(_ part: inout Part, kind: String, _ body: (inout FieldPart) throws -> Void) throws {
        guard case .field(var p) = part.kind else { throw Self.noSuchProperty("field option", of: kind) }
        try body(&p); part.kind = .field(p)
    }

    private func withFormat(_ part: inout Part, kind: String, _ body: (inout TextFormat) throws -> Void) throws {
        switch part.kind {
        case .field(var p): try body(&p.format); part.kind = .field(p)
        case .button(var p): try body(&p.format); part.kind = .button(p)
        default: throw Self.noSuchProperty("text formatting", of: kind)
        }
    }

    static func format(of part: Part) -> TextFormat? {
        switch part.kind {
        case .field(let p): p.format
        case .button(let p): p.format
        default: nil
        }
    }

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
        // `group` makes the field's text click as a unit (see TextFormat.isGroup)
        // — scriptable via `set the textStyle … to group`.
        format.isGroup = tokens.contains("group")
    }

    static func parseFontDesign(_ value: String) -> FontDesign? {
        let normalized = value.lowercased().trimmingCharacters(in: .whitespaces)
        return FontDesign.allCases.first { $0.rawValue == normalized || $0.label.lowercased() == normalized }
    }

    // MARK: - Chunk (text-run) properties

    func textRunProperty(_ property: String, ofField reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, range: Range<Int>) throws -> String {
        let loc = try locatePart(kind: "field", domain: domain, reference: reference, onCard: nil)
        guard case .field(let f) = effectivePart(at: loc, cardIndex: cardIndex).kind else { throw HostError("That part is not a field.") }
        return Self.runProperty(property, text: f.text, base: f.format, runs: f.styleRuns, range: range)
    }

    func setTextRunProperty(_ property: String, ofField reference: HyperTalkObject.Reference, domain: HyperTalkObject.PartDomain, range: Range<Int>, to value: String) throws {
        let loc = try locatePart(kind: "field", domain: domain, reference: reference, onCard: nil)
        var mutable = effectivePart(at: loc, cardIndex: cardIndex)
        guard case .field(var f) = mutable.kind else { throw HostError("That part is not a field.") }
        let newRuns = try Self.settingRuns(property, to: value, text: f.text,
                                           base: f.format, runs: f.styleRuns, range: range)
        if usesOverlay(loc) {
            writeOverlay(runs: newRuns, partID: mutable.id, cardIndex: cardIndex)
            return
        }
        f.styleRuns = newRuns
        mutable.kind = .field(f)
        setPart(mutable, at: loc)
    }

    /// The write side of per-chunk styled text — mirror of the app host's
    /// splitter/merger (`set the textStyle … to bold` REPLACES the span's
    /// style set; "plain" clears it; an unmappable font leaves the design).
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
                if let design = Self.parseFontDesign(value) { f.fontDesign = design }
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
                    default: break
                    }
                }
            default:
                throw HostError("There is no \(property) property of a chunk.")
            }
            return f
        }
        let sorted = runs.sorted { $0.start < $1.start }
        var boundaries: [Int] = [0, lo, hi, count]
        boundaries.append(contentsOf: sorted.map { min(max($0.start, 0), count) })
        let starts = Array(Set(boundaries)).sorted().filter { $0 < count }
        func formatInForce(at offset: Int) -> TextFormat {
            var f = base
            for run in sorted where run.start <= offset { f = run.format }
            return f
        }
        var result: [StyleRun] = []
        var current = base
        for start in starts {
            var format = formatInForce(at: start)
            if start >= lo, start < hi { format = try mutated(format) }
            if format != current {
                result.append(StyleRun(start: start, format: format))
                current = format
            }
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

    // MARK: - Card properties

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
        case "showpict": return stack.cards[index].showPicture ? "true" : "false"
        default: throw Self.noSuchProperty(property, of: "a card")
        }
    }

    private func setCardProperty(_ property: String, cardAt index: Int, to value: String) throws {
        switch property {
        case "name": stack.cards[index].name = value
        case "marked": stack.cards[index].isMarked = try boolean(value, for: property)
        case "cantdelete": stack.cards[index].cantDelete = try boolean(value, for: property)
        case "dontsearch": stack.cards[index].dontSearch = try boolean(value, for: property)
        case "highlightcolor": stack.cards[index].highlightColor = value.isEmpty ? nil : value
        case "showpict": stack.cards[index].showPicture = try boolean(value, for: property)
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
        guard let n = Double(value.trimmingCharacters(in: .whitespaces)), n.isFinite else {
            throw HostError("The \(property) property needs a number, not \"\(value)\".")
        }
        return n
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

    static func noSuchProperty(_ property: String, of what: String) -> HostError {
        let article = (what == "this stack" || what == "this card" || what == "this background" || what == "a card") ? what : "a \(what)"
        return HostError("There is no property \"\(property)\" of \(article).")
    }

    // MARK: - Part lookup

    enum PartLocation {
        case card(cardIndex: Int, partIndex: Int)
        case background(backgroundIndex: Int, partIndex: Int)
    }

    /// `onCard` scopes the lookup to another card (`cd btn id 8 of cd "Stack
    /// Menus"`); nil searches the current card.
    func locatePart(kind: String, domain: HyperTalkObject.PartDomain, reference: HyperTalkObject.Reference, onCard cardDestination: GoDestination? = nil) throws -> PartLocation {
        let ci = try cardDestination.map { try resolveCardIndex($0) } ?? cardIndex
        let card = stack.cards[ci]
        let bgIndex = stack.backgrounds.firstIndex(where: { $0.id == card.backgroundID })
        func onCard() -> PartLocation? {
            index(ofKind: kind, matching: reference, in: card.parts).map { .card(cardIndex: ci, partIndex: $0) }
        }
        func onBackground() -> PartLocation? {
            guard let bgIndex,
                  let i = index(ofKind: kind, matching: reference, in: stack.backgrounds[bgIndex].parts) else { return nil }
            return .background(backgroundIndex: bgIndex, partIndex: i)
        }
        if domain != .background, let f = onCard() { return f }
        if domain != .card, let f = onBackground() { return f }
        if let f = onCard() ?? onBackground() { return f }
        let where_ = switch domain {
        case .any: "on this card"
        case .card: "on this card (card layer)"
        case .background: "on this background"
        }
        switch reference {
        case .named(let n): throw HostError("There is no \(kind) named \"\(n)\" \(where_).")
        case .number(let n): throw HostError("There is no \(kind) \(n) \(where_).")
        case .id(let id): throw HostError("There is no \(kind) with id \(id) \(where_).")
        }
    }

    /// Whether a part matches a referenced kind. The "part" pseudo-kind is a
    /// wildcard over buttons and fields (HyperCard's `cd part N` by z-order),
    /// matching the set `the number of parts` counts.
    func matchesPartKind(_ part: Part, _ kind: String) -> Bool {
        if kind == "part" { return part.kind.word == "button" || part.kind.word == "field" }
        return part.kind.word == kind
    }

    func index(ofKind kind: String, matching reference: HyperTalkObject.Reference, in parts: [Part]) -> Int? {
        switch reference {
        case .named(let name):
            return parts.firstIndex { matchesPartKind($0, kind) && $0.name.caseInsensitiveCompare(name) == .orderedSame }
        case .number(let number):
            guard number >= 1 else { return nil }
            var seen = 0
            for (i, part) in parts.enumerated() where matchesPartKind(part, kind) {
                seen += 1
                if seen == number { return i }
            }
            return nil
        case .id(let id):
            let wanted = id.trimmingCharacters(in: .whitespaces)
            return parts.firstIndex { matchesPartKind($0, kind) && String($0.scriptID) == wanted }
        }
    }

    private func ordinal(of location: PartLocation, kind: String) -> Int {
        let parts: [Part]
        let partIndex: Int
        switch location {
        case .card(let ci, let i): parts = stack.cards[ci].parts; partIndex = i
        case .background(let b, let i): parts = stack.backgrounds[b].parts; partIndex = i
        }
        var seen = 0
        for (i, part) in parts.enumerated() where matchesPartKind(part, kind) {
            seen += 1
            if i == partIndex { return seen }
        }
        return seen
    }

    func part(at location: PartLocation) -> Part {
        switch location {
        case .card(let ci, let i): stack.cards[ci].parts[i]
        case .background(let b, let i): stack.backgrounds[b].parts[i]
        }
    }

    /// The part as seen from a card: a non-sharedText background field carries
    /// that card's overlay text/runs (app-host parity).
    func effectivePart(at location: PartLocation, cardIndex ci: Int) -> Part {
        var found = part(at: location)
        guard case .background = location, case .field(var p) = found.kind, !p.sharedText else { return found }
        let content = stack.cards[ci].backgroundFieldContent[found.id.uuidString]
        p.text = content?.text ?? ""
        p.styleRuns = content?.styleRuns ?? []
        found.kind = .field(p)
        return found
    }

    /// Whether text/runs at this location live in the per-card overlay.
    func usesOverlay(_ location: PartLocation) -> Bool {
        guard case .background = location, case .field(let p) = part(at: location).kind else { return false }
        return !p.sharedText
    }

    func writeOverlay(text: String? = nil, runs: [StyleRun]? = nil, partID: UUID, cardIndex ci: Int) {
        var content = stack.cards[ci].backgroundFieldContent[partID.uuidString] ?? BackgroundFieldContent()
        if let text { content.text = text }
        if let runs { content.styleRuns = runs }
        stack.cards[ci].backgroundFieldContent[partID.uuidString] = content
    }

    private func setPart(_ part: Part, at location: PartLocation) {
        switch location {
        case .card(let ci, let i): stack.cards[ci].parts[i] = part
        case .background(let b, let i): stack.backgrounds[b].parts[i] = part
        }
    }

    // MARK: - Convert (date/time)

    private func convertFormatter(_ formats: [ConvertFormat]) -> DateFormatter? {
        let f = DateFormatter()
        for format in formats {
            switch format {
            case .shortDate: f.dateStyle = .short
            case .longDate: f.dateStyle = .full
            case .abbreviatedDate: f.dateStyle = .medium
            case .shortTime: f.timeStyle = .short
            case .longTime: f.timeStyle = .medium
            case .seconds, .dateItems: return nil
            }
        }
        return f
    }

    func convertParse(_ value: String, from: [ConvertFormat]) throws -> Date {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        // HyperCard fills components the value omits from the current date/time,
        // so an empty value converts as "now" rather than erroring (mirrors the
        // app host; see DocumentScriptHost.convertParse).
        if trimmed.isEmpty {
            return Date()
        }
        if from == [.seconds] || (from.isEmpty && Double(trimmed) != nil) {
            guard let seconds = Double(trimmed) else { throw HostError("Can't read \"\(value)\" as seconds.") }
            return HyperCardDate.date(fromSeconds: seconds) // 1904 epoch (oracle-verified)
        }
        if from == [.dateItems] || (from.isEmpty && trimmed.contains(",")) {
            // Missing/empty components inherit from the current date/time.
            let now = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
            let raw = trimmed.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            func part(_ index: Int, _ fallback: Int) -> Int {
                guard index < raw.count, !raw[index].isEmpty, let n = Int(raw[index]) else { return fallback }
                return n
            }
            var c = DateComponents()
            c.year = part(0, now.year!); c.month = part(1, now.month!); c.day = part(2, now.day!)
            c.hour = part(3, now.hour!); c.minute = part(4, now.minute!); c.second = part(5, now.second!)
            guard let date = Calendar.current.date(from: c) else { throw HostError("Can't read \"\(value)\" as dateItems.") }
            return date
        }
        if !from.isEmpty {
            guard let date = convertFormatter(from)?.date(from: trimmed) else {
                throw HostError("Can't read \"\(value)\" in that format.")
            }
            return date
        }
        let candidates: [[ConvertFormat]] = [
            [.shortDate, .shortTime], [.longDate, .longTime],
            [.longDate], [.abbreviatedDate], [.shortDate], [.longTime], [.shortTime],
        ]
        for candidate in candidates {
            if let date = convertFormatter(candidate)?.date(from: trimmed) { return date }
        }
        throw HostError("Can't read \"\(value)\" as a date or time.")
    }

    func convertRender(_ date: Date, to: [ConvertFormat]) throws -> String {
        if to == [.seconds] { return String(HyperCardDate.seconds(of: date)) } // 1904 epoch
        if to == [.dateItems] {
            let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
            return [c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!, c.weekday!].map(String.init).joined(separator: ",")
        }
        guard let f = convertFormatter(to) else { throw HostError("Can't convert to that combination of formats.") }
        return f.string(from: date)
    }
}
