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
            return try partProperty(property, of: part(at: loc), kind: kind)
        case .card(let reference):
            return try cardProperty(property, cardAt: try cardIndexFor(reference))
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
            case "cantdelete": return bg.cantDelete ? "true" : "false"
            case "dontsearch": return bg.dontSearch ? "true" : "false"
            default: throw Self.noSuchProperty(property, of: "this background")
            }
        case .thisStack:
            switch property {
            case "name": return stack.name
            case "longname", "longid": return "stack \"\(stack.name)\""
            case "cards": return String(stack.cards.count)
            case "width": return numberText(stack.cardSize.width)
            case "height": return numberText(stack.cardSize.height)
            case "fullscreen": return stack.isFullScreen ? "true" : "false"
            case "paddingcolor": return stack.paddingColor
            default: throw Self.noSuchProperty(property, of: "this stack")
            }
        }
    }

    func setProperty(_ property: String, of object: HyperTalkObject, to value: String) throws {
        guard property != "id" else { throw HostError("The id of an object can't be changed.") }
        switch object {
        case .part(let kind, let domain, let reference, let onCard):
            let loc = try locatePart(kind: kind, domain: domain, reference: reference, onCard: onCard)
            var updated = part(at: loc)
            try applyPartProperty(property, to: &updated, kind: kind, value: value)
            setPart(updated, at: loc)
        case .card(let reference):
            try setCardProperty(property, cardAt: try cardIndexFor(reference), to: value)
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
        default:
            throw Self.noSuchProperty(property, of: kind)
        }
    }

    private func applyPartProperty(_ property: String, to part: inout Part, kind: String, value: String) throws {
        switch property {
        case "name": part.name = value
        case "visible": part.isVisible = try boolean(value, for: property)
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
        return parts.isEmpty ? "plain" : parts.joined(separator: ",")
    }

    static func applyStyleList(_ value: String, to format: inout TextFormat) {
        let tokens = value.lowercased().split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
        format.isBold = tokens.contains("bold")
        format.isItalic = tokens.contains("italic")
        format.isUnderline = tokens.contains("underline")
    }

    static func parseFontDesign(_ value: String) -> FontDesign? {
        let normalized = value.lowercased().trimmingCharacters(in: .whitespaces)
        return FontDesign.allCases.first { $0.rawValue == normalized || $0.label.lowercased() == normalized }
    }

    // MARK: - Card properties

    private func cardProperty(_ property: String, cardAt index: Int) throws -> String {
        let card = stack.cards[index]
        switch property {
        case "name": return card.name
        case "longname": return "card \"\(card.name)\""
        case "longid": return "card id \(card.scriptID)"
        case "highlightcolor": return card.highlightColor ?? ""
        case "number": return String(index + 1)
        case "id": return String(card.scriptID)
        case "marked": return card.isMarked ? "true" : "false"
        case "cantdelete": return card.cantDelete ? "true" : "false"
        case "dontsearch": return card.dontSearch ? "true" : "false"
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
        default: throw Self.noSuchProperty(property, of: "a card")
        }
    }

    func cardIndexFor(_ reference: HyperTalkObject.Reference) throws -> Int {
        switch reference {
        case .number(let n):
            guard (1...stack.cards.count).contains(n) else {
                throw HostError("There is no card \(n) — this stack has \(stack.cards.count) card\(stack.cards.count == 1 ? "" : "s").")
            }
            return n - 1
        case .named(let which):
            guard let i = stack.cards.firstIndex(where: { $0.name.caseInsensitiveCompare(which) == .orderedSame }) else {
                throw HostError("There is no card named \"\(which)\".")
            }
            return i
        case .id(let id):
            let wanted = id.trimmingCharacters(in: .whitespaces)
            guard let i = stack.cards.firstIndex(where: { String($0.scriptID) == wanted }) else {
                throw HostError("There is no card with id \(id).")
            }
            return i
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

    func index(ofKind kind: String, matching reference: HyperTalkObject.Reference, in parts: [Part]) -> Int? {
        switch reference {
        case .named(let name):
            return parts.firstIndex { $0.kind.word == kind && $0.name.caseInsensitiveCompare(name) == .orderedSame }
        case .number(let number):
            guard number >= 1 else { return nil }
            var seen = 0
            for (i, part) in parts.enumerated() where part.kind.word == kind {
                seen += 1
                if seen == number { return i }
            }
            return nil
        case .id(let id):
            let wanted = id.trimmingCharacters(in: .whitespaces)
            return parts.firstIndex { $0.kind.word == kind && String($0.scriptID) == wanted }
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
        for (i, part) in parts.enumerated() where part.kind.word == kind {
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
        if from == [.seconds] || (from.isEmpty && Double(trimmed) != nil) {
            guard let seconds = Double(trimmed) else { throw HostError("Can't read \"\(value)\" as seconds.") }
            return Date(timeIntervalSince1970: seconds)
        }
        if from == [.dateItems] || (from.isEmpty && trimmed.contains(",")) {
            let parts = trimmed.split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            guard parts.count >= 3 else { throw HostError("Expected at least year, month, and day in dateItems.") }
            var c = DateComponents()
            c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
            if parts.count > 3 { c.hour = parts[3] }
            if parts.count > 4 { c.minute = parts[4] }
            if parts.count > 5 { c.second = parts[5] }
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
        if to == [.seconds] { return String(Int(date.timeIntervalSince1970)) }
        if to == [.dateItems] {
            let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
            return [c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!, c.weekday!].map(String.init).joined(separator: ",")
        }
        guard let f = convertFormatter(to) else { throw HostError("Can't convert to that combination of formats.") }
        return f.string(from: date)
    }
}
