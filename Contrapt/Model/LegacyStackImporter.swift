//
//  LegacyStackImporter.swift
//  Contrapt
//
//  Reads classic HyperCard 1.x/2.x stacks (the single-file, data-fork binary
//  format) into Contrapt's Stack model. Pure Foundation, so it runs the same
//  on iOS and Mac and stays inside the sandbox (no shelling out to old tools).
//
//  Phase 1 (this pass): stack structure, cards in PAGE order, buttons and
//  fields (geometry, style, name), field text per card, and HyperTalk scripts
//  — which our interpreter runs. Card/background PAINT (WOBA bitmaps) is
//  deferred to a second pass; see `hasArtwork`.
//
//  Format references pinned empirically against Apple's HyperCard 1.2.5 sample
//  stacks: block chain of {u32 size, 4-char type, i32 id, …}; STAK holds card
//  counts/ids; part records are {u16 size, i16 id, u8 type(1=button,2=field),
//  u8 flags, i16 top/left/bottom/right, …, name\0, script\0}.
//

import Foundation

enum LegacyStackImporter {
    struct ImportError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// The result of an import: the stack plus the paint-art assets it
    /// references (card/background WOBA bitmaps rendered to PNG).
    struct Imported {
        let stack: Stack
        let assets: [String: Data]
    }

    /// Reads `data` (a classic stack's data fork) into a Contrapt stack.
    /// `iconFork`, when given (a HyperCard app's resource fork), supplies the
    /// button ICON bitmaps the stack references — embedded per-use as assets.
    /// `presentAtActualSize` opens the card at its true point size (1:1, small,
    /// like classic HyperCard) rather than scaled to fill the window.
    static func stack(from data: Data, name: String, iconFork: Data? = nil, stackFork: Data? = nil, presentAtActualSize: Bool = false) throws -> Imported {
        var reader = Reader(data)
        guard reader.tag(at: 0) == "STAK" else {
            throw ImportError(message: "This doesn't look like a HyperCard stack (no STAK header). If it came as a .hqx or .sit, unpack it first.")
        }
        // HyperCard 2.x block headers carry 4 extra bytes; shift the fixed
        // offsets so bitmap ids, owner-background ids, and WOBA art all read.
        reader.headerDelta = reader.formatVersion >= 9 ? 4 : 0
        let blocks = reader.walkBlocks()
        let cardWidth = 512, cardHeight = 342 // HC 1.x screen
        var assets: [String: Data] = [:]
        let bmapByID = Dictionary(blocks.filter { $0.type == "BMAP" }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // Icons come from the HyperCard app's fork plus the stack's own
        // resource fork — custom icons (QuickTime, AppleScript…) that Apple
        // ships inside the stack, not the app. Stack icons win on any id clash.
        var iconLibrary = iconFork.map { ResourceFork.icons(from: $0) } ?? [:]
        if let stackFork { iconLibrary.merge(ResourceFork.icons(from: stackFork)) { _, stackIcon in stackIcon } }
        var iconAssetByID: [Int: String] = [:] // dedupe: one asset per icon id used

        // Render a BMAP block to a stored paint asset, returning its name.
        func paintAsset(bitmapID: Int) -> String? {
            guard bitmapID != 0, let bmap = bmapByID[bitmapID],
                  let png = reader.bmapPaintPNG(bmap, cardWidth: cardWidth, cardHeight: cardHeight) else { return nil }
            let assetName = UUID().uuidString.lowercased() + ".png"
            assets[assetName] = png
            return assetName
        }

        // Render (once) a button's ICON to a stored asset, returning its name.
        func iconAsset(iconID: Int) -> String? {
            guard iconID != 0 else { return nil }
            if let existing = iconAssetByID[iconID] { return existing }
            guard let icon = iconLibrary[iconID], let png = ResourceFork.iconPNG(icon) else { return nil }
            let assetName = UUID().uuidString.lowercased() + ".png"
            assets[assetName] = png
            iconAssetByID[iconID] = assetName
            return assetName
        }

        // Card order comes from the PAGE block(s); fall back to file order.
        let cardBlocks = blocks.filter { $0.type == "CARD" }
        let cardByID = Dictionary(uniqueKeysWithValues: cardBlocks.map { ($0.id, $0) })
        let order = reader.cardOrder(pageBlocks: blocks.filter { $0.type == "PAGE" },
                                     knownIDs: Set(cardBlocks.map(\.id)))
        let orderedCardBlocks = order.isEmpty ? cardBlocks : order.compactMap { cardByID[$0] }

        // Backgrounds → Contrapt backgrounds (buttons only; fields become
        // per-card, since HyperCard background fields hold per-card text).
        var stack = Stack(formatVersion: StackFormat.currentVersion,
                          id: UUID(), name: name,
                          cardSize: CardSize(width: Double(cardWidth), height: Double(cardHeight)),
                          script: "", backgrounds: [], cards: [])
        stack.presentAtActualSize = presentAtActualSize
        // The stack script (handlers like `on goAddress`) lives in the STAK
        // block. Without it, buttons that call stack-level commands fail.
        if let stakBlock = blocks.first(where: { $0.type == "STAK" }) {
            stack.script = reader.stackScript(stakBlock)
        }

        var bgInfoByID: [Int: ParsedObject] = [:]
        var bgUUIDByID: [Int: UUID] = [:]
        var fieldIDs = Set<Int>()
        var partIDs = Set<Int>() // all background parts (fields + buttons) — 2.x card contents key on buttons too
        for block in blocks where block.type == "BKGD" {
            let parsed = reader.parseObject(block, knownFieldIDs: [])
            bgInfoByID[block.id] = parsed
            fieldIDs.formUnion(parsed.parts.filter { $0.type == .field }.map(\.id))
            partIDs.formUnion(parsed.parts.map(\.id))
            var background = Background(id: UUID(), name: parsed.name.isEmpty ? "Background \(stack.backgrounds.count + 1)" : parsed.name,
                                        script: parsed.script, parts: [])
            background.scriptID = stack.claimScriptID()
            // Buttons live on the background, as do shared-text fields —
            // background labels (copyright, "Home") whose one value is stored
            // in the background block. Other fields become per-card copies.
            background.parts = parsed.parts.compactMap { raw -> Part? in
                if raw.type == .button {
                    return part(from: raw, in: &stack, iconAsset: iconAsset(iconID: raw.iconID))
                }
                guard raw.sharedText else { return nil }
                var fieldPart = part(from: raw, in: &stack)
                if case .field(var props) = fieldPart.kind {
                    props.text = parsed.contents[raw.id] ?? ""
                    fieldPart.kind = .field(props)
                }
                return fieldPart
            }
            background.paintImageAsset = paintAsset(bitmapID: parsed.bitmapID)
            bgUUIDByID[block.id] = background.id
            stack.backgrounds.append(background)
        }
        // A stack with no background block still needs one to hang cards on.
        if stack.backgrounds.isEmpty {
            var background = Background(id: UUID(), name: "Background 1", script: "", parts: [])
            background.scriptID = stack.claimScriptID()
            stack.backgrounds.append(background)
        }

        for block in orderedCardBlocks {
            let parsed = reader.parseObject(block, knownFieldIDs: fieldIDs, knownPartIDs: partIDs)
            let bgID = parsed.ownerBackgroundID
            let backgroundUUID = bgUUIDByID[bgID] ?? stack.backgrounds[0].id
            // Shared-text fields already live on the background; only per-card
            // fields are copied onto the card and filled with this card's text.
            let templateFields = (bgInfoByID[bgID]?.parts ?? []).filter { $0.type == .field && !$0.sharedText }

            var card = Card(id: UUID(),
                            name: parsed.name.isEmpty ? "Card \(stack.cards.count + 1)" : parsed.name,
                            backgroundID: backgroundUUID, script: parsed.script, parts: [])
            card.scriptID = stack.claimScriptID()
            card.paintImageAsset = paintAsset(bitmapID: parsed.bitmapID)

            // Background fields, copied onto the card and filled with this
            // card's text (mapped by HyperCard part id).
            for template in templateFields {
                var fieldPart = part(from: template, in: &stack)
                if case .field(var props) = fieldPart.kind {
                    props.text = parsed.contents[template.id] ?? ""
                    fieldPart.kind = .field(props)
                }
                card.parts.append(fieldPart)
            }
            // Any card-layer parts (rare in these samples) come across too,
            // with their own content.
            for raw in parsed.parts {
                var cardPart = part(from: raw, in: &stack, iconAsset: iconAsset(iconID: raw.iconID))
                if case .field(var props) = cardPart.kind, let text = parsed.contents[raw.id] {
                    props.text = text
                    cardPart.kind = .field(props)
                }
                card.parts.append(cardPart)
            }
            stack.cards.append(card)
        }

        if stack.cards.isEmpty {
            var card = Card(id: UUID(), name: "Card 1", backgroundID: stack.backgrounds[0].id, script: "", parts: [])
            card.scriptID = stack.claimScriptID()
            stack.cards.append(card)
        }
        return Imported(stack: stack.sanitized(), assets: assets)
    }

    /// Imports the classic stack at `source` and writes it as a `.contrapt`
    /// file in the temporary directory, returning that URL to open. `iconApp`,
    /// if given, is a HyperCard application whose ICON resources resolve the
    /// stack's button icons (embedded per-use; nothing Apple ships in Contrapt).
    static func importedContraptFile(from source: URL, iconApp: URL? = nil, presentAtActualSize: Bool = false) throws -> URL {
        let didAccess = source.startAccessingSecurityScopedResource()
        defer { if didAccess { source.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: source)
        let name = source.deletingPathExtension().lastPathComponent
        // The stack's own resource fork carries any custom button icons.
        let stackFork = ResourceFork.forkData(of: source)
        var iconFork: Data?
        if let iconApp {
            let iconAccess = iconApp.startAccessingSecurityScopedResource()
            defer { if iconAccess { iconApp.stopAccessingSecurityScopedResource() } }
            iconFork = ResourceFork.forkData(of: iconApp)
        }
        let imported = try stack(from: data, name: name.isEmpty ? "Imported Stack" : name, iconFork: iconFork, stackFork: stackFork, presentAtActualSize: presentAtActualSize)
        var entries: [String: Data] = ["stack.json": try imported.stack.fileData()]
        for (assetName, bytes) in imported.assets { entries["assets/\(assetName)"] = bytes }
        let archive = ZipArchive.archive(entries)
        // A unique subdirectory per import keeps the friendly filename while
        // ensuring the path is new — otherwise NSDocumentController dedupes by
        // URL and refocuses a previously-imported (stale) window.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory
            .appendingPathComponent(imported.stack.name)
            .appendingPathExtension("contrapt")
        try archive.write(to: url)
        return url
    }

    // MARK: - Raw → Contrapt part

    private static func part(from raw: RawPart, in stack: inout Stack, iconAsset: String? = nil) -> Part {
        let frame = PartFrame(x: Double(raw.left), y: Double(raw.top),
                              width: Double(max(8, raw.right - raw.left)),
                              height: Double(max(8, raw.bottom - raw.top)))
        let format = textFormat(from: raw)
        let kind: PartKind
        switch raw.type {
        case .button:
            var button = ButtonPart(title: raw.name)
            button.style = raw.buttonStyle
            button.showName = raw.showName
            button.autoHilite = raw.autoHilite
            button.hilite = raw.hilite
            button.format = format
            button.iconAsset = iconAsset
            kind = .button(button)
        case .field:
            var field = FieldPart(text: "", placeholder: "", isMultiline: true, format: format)
            field.style = raw.fieldStyle
            field.showLines = raw.showLines
            // Honor the field's real Lock Text flag: display/label fields import
            // locked (static text that still dispatches taps to scripts), while
            // input fields import editable — as the stack author intended.
            // Shared-text fields are background labels (copyright, "Home"), so
            // they're locked too — static text, no editable caret in browse.
            field.lockText = raw.lockText || raw.sharedText
            kind = .field(field)
        }
        var part = Part(id: UUID(), name: raw.name, frame: frame,
                        script: raw.script, kind: kind)
        part.isVisible = raw.visible
        part.scriptID = stack.claimScriptID()
        return part
    }

    /// Classic bitmap fonts re-render a little large in SwiftUI's system
    /// fonts at the same point size, so proportional imported text (Times,
    /// Geneva, Helvetica…) is scaled by this factor to match the original.
    /// Monospaced text (Courier/Monaco grids) already matches, so it's left
    /// 1:1. TUNABLE: 1.0 = no change; lower = smaller. Re-import to apply.
    static let proportionalFontScale = 0.85

    /// Map a part's HyperCard font/size/style/alignment to a TextFormat, so
    /// imported text matches the original rather than Contrapt's defaults.
    private static func textFormat(from raw: RawPart) -> TextFormat {
        var format = TextFormat()
        if raw.textSize > 0 { format.size = Double(min(max(raw.textSize, 6), 96)) }
        format.align = raw.textAlign == 1 ? .center : (raw.textAlign < 0 ? .right : .left)
        // Classic Mac font ids → Contrapt's font families (best effort).
        switch raw.fontID {
        case 4, 22: format.fontDesign = .monospaced  // Monaco, Courier
        case 2, 14, 16, 20, 34:
            // New York, Bookman, Palatino, Times, New Century Schoolbook.
            format.fontDesign = .serif
        default: format.fontDesign = .standard       // Geneva, Chicago, Helvetica, Avant Garde…
        }
        if format.fontDesign != .monospaced {
            format.size *= proportionalFontScale
        }
        format.isBold = raw.textStyleBits & 0x01 != 0
        format.isItalic = raw.textStyleBits & 0x02 != 0
        format.isUnderline = raw.textStyleBits & 0x04 != 0
        return format
    }
}

// MARK: - Binary reader

private extension LegacyStackImporter {
    enum PartType { case button, field }

    struct RawPart {
        var id: Int
        var type: PartType
        var top: Int, left: Int, bottom: Int, right: Int
        var name: String
        var script: String
        var styleByte: Int
        var showName: Bool
        /// Field "Show Lines" — baseline writing rules (flag byte +0x0E, 0x40).
        var showLines: Bool
        /// Button hilite (+0x0E, 0x40 — same bit as a field's showLines) and
        /// Auto Hilite (+0x0E, 0x20). A hilited opaque button is the classic
        /// inverted (black) bar, e.g. the Tour's "BlackStripe".
        var hilite: Bool
        var autoHilite: Bool
        /// Field "Lock Text" — display-only, dispatches clicks (flag +0x05, 0x01).
        var lockText: Bool
        /// Field "Shared Text" — the same text on every card, stored once in
        /// the background block (flag +0x05, 0x08). Background labels like a
        /// copyright notice. Imported onto the background, not per-card.
        var sharedText: Bool
        var iconID: Int
        var visible: Bool
        var textAlign: Int
        var fontID: Int
        var textSize: Int
        var textStyleBits: Int
        /// HyperCard button style (low nibble of the style byte) → Contrapt.
        var buttonStyle: ButtonStyleKind {
            switch styleByte {
            case 0: return .transparent
            case 1: return .opaque
            case 2: return .rectangle
            case 3: return .roundRect
            case 4: return .shadow
            case 8: return .checkbox
            case 9: return .radio
            default: return .roundRect
            }
        }
        /// HyperCard field style (low nibble) → Contrapt field style
        /// (scrolling/other fall back to rectangle).
        var fieldStyle: FieldStyle {
            switch styleByte {
            case 0: return .transparent
            case 1: return .opaque
            case 3: return .shadow
            default: return .rectangle
            }
        }
    }

    struct ParsedObject {
        var name: String
        var script: String
        var ownerBackgroundID: Int
        var bitmapID: Int
        var parts: [RawPart]
        /// Field text keyed by the field's HyperCard part id — how card
        /// contents are stored, so mapping is exact rather than positional.
        var contents: [Int: String]
    }

    struct BlockInfo { let type: String; let offset: Int; let size: Int; let id: Int }

    struct Reader {
        let d: [UInt8]
        /// HyperCard 2.x (STAK format version ≥ 9) inserts 4 bytes into every
        /// CARD/BKGD/BMAP block header, shifting the bitmap id, owner-background
        /// id, and all WOBA header fields by +4. 1.x leaves this 0.
        var headerDelta = 0
        init(_ data: Data) { d = [UInt8](data) }

        /// STAK block sits at offset 0; +0x10 is the format version (8 = 1.2.x,
        /// 9 = 2.0, 10 = 2.2+). Version ≥ 9 uses the shifted block layout.
        var formatVersion: Int { u32(0x10) }

        func u32(_ o: Int) -> Int { Int((UInt32(d[o]) << 24) | (UInt32(d[o+1]) << 16) | (UInt32(d[o+2]) << 8) | UInt32(d[o+3])) }
        func u16(_ o: Int) -> Int { Int((UInt16(d[o]) << 8) | UInt16(d[o+1])) }
        func i16(_ o: Int) -> Int { Int(Int16(bitPattern: UInt16((UInt16(d[o]) << 8) | UInt16(d[o+1])))) }
        func i32(_ o: Int) -> Int { Int(Int32(bitPattern: UInt32(u32(o)))) }
        func tag(at o: Int) -> String { o + 8 <= d.count ? (String(bytes: d[(o+4)..<(o+8)], encoding: .ascii) ?? "") : "" }

        /// Walk the contiguous block chain from offset 0.
        func walkBlocks() -> [BlockInfo] {
            var blocks: [BlockInfo] = []
            var o = 0
            while o + 12 <= d.count {
                let size = u32(o)
                if size < 12 || o + size > d.count { break }
                blocks.append(BlockInfo(type: tag(at: o), offset: o, size: size, id: i32(o + 8)))
                o += size
            }
            return blocks
        }

        /// Ordered card IDs from the PAGE block(s): the known card IDs in the
        /// order they appear (as big-endian u32) in the page data.
        func cardOrder(pageBlocks: [BlockInfo], knownIDs: Set<Int>) -> [Int] {
            var order: [Int] = []
            var seen = Set<Int>()
            for page in pageBlocks {
                var o = page.offset + 12
                while o + 4 <= page.offset + page.size {
                    let value = u32(o)
                    if knownIDs.contains(value), !seen.contains(value) {
                        order.append(value); seen.insert(value)
                    }
                    o += 2 // step by 2: page entries are short; catches all ids
                }
            }
            return order
        }

        /// The stack's own script: a handler-looking run in the STAK block,
        /// after its fixed header. Scanned like CARD/BKGD scripts.
        func stackScript(_ block: BlockInfo) -> String {
            for run in textRuns(from: block.offset + 0x30, end: block.offset + block.size)
                where looksLikeScript(run) {
                return trimToCompleteHandlers(run)
            }
            return ""
        }

        /// Keep a script only through its last complete top-level handler
        /// (`on X`/`function X` … matching `end X`), dropping trailing truncated
        /// handlers and leading orphan fragments. Legacy blocks can hold
        /// stale/half-overwritten script bytes that bleed into the next block —
        /// e.g. an unterminated `doMenu "` — which would otherwise fail to
        /// tokenize. A clean script (banner + whole handlers) is returned as-is.
        private func trimToCompleteHandlers(_ script: String) -> String {
            let lines = script.components(separatedBy: "\n")
            func headWord(_ line: String, _ keyword: String) -> String? {
                let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
                guard trimmed == keyword || trimmed.hasPrefix(keyword + " ") else { return nil }
                return trimmed.dropFirst(keyword.count).drop(while: { $0 == " " })
                    .split(separator: " ").first.map(String.init)
            }
            var open: String?
            var lastCompleteEnd: Int?
            for (i, line) in lines.enumerated() {
                if let name = headWord(line, "on") ?? headWord(line, "function") {
                    open = name // a new handler; any unclosed one is abandoned
                } else if let endName = headWord(line, "end"), let o = open, endName == o {
                    lastCompleteEnd = i; open = nil // matching end closes the handler
                    // (end if / end repeat / orphan end don't match and are ignored)
                }
            }
            guard let last = lastCompleteEnd else { return "" }
            return lines[0...last].joined(separator: "\n")
        }

        /// Parse a CARD or BKGD block into parts, contents, and script.
        /// `knownFieldIDs` anchors the 1.x content-entry scan (card contents are
        /// keyed by the background's field ids). `knownPartIDs` (all background
        /// parts, buttons included) bounds the 2.x scan, whose entries also
        /// cover buttons and must be walked to reach the name.
        func parseObject(_ block: BlockInfo, knownFieldIDs: Set<Int>, knownPartIDs: Set<Int> = []) -> ParsedObject {
            let base = block.offset, end = block.offset + block.size
            let ownerBackground = block.type == "CARD" ? u32(base + 0x20 + headerDelta) : block.id
            let bitmapID = u32(base + 0x0C + headerDelta) // CARD/BKGD both store their BMAP id here
            let parts = parseParts(base: base, end: end)
            let afterParts = parts.last?.recordEnd ?? (base + 0x24)
            let ownFieldIDs = Set(parts.map(\.part).filter { $0.type == .field }.map(\.id))

            let (contents, contentsEnd): ([Int: String], Int)
            if headerDelta > 0 {
                let known = knownPartIDs.union(parts.map(\.part.id))
                (contents, contentsEnd) = parseContentsV2(from: afterParts, end: end, knownIDs: known)
            } else {
                (contents, contentsEnd) = parseContents(from: afterParts, end: end, fieldIDs: knownFieldIDs.union(ownFieldIDs))
            }
            // After the content section come the object's name and script as
            // C-strings (name first). Scan there for both.
            let (name, script) = nameAndScript(from: contentsEnd, end: end)
            return ParsedObject(name: name, script: script,
                                ownerBackgroundID: ownerBackground, bitmapID: bitmapID,
                                parts: parts.map(\.part), contents: contents)
        }

        /// After the content section, a CARD/BKGD block holds its name then
        /// its script as C-strings. The name is the first clean run; the
        /// script is the first handler-looking run.
        private func nameAndScript(from start: Int, end: Int) -> (name: String, script: String) {
            var name = "", script = ""
            for run in textRuns(from: start, end: end) {
                if looksLikeScript(run) { script = trimToCompleteHandlers(run); break }
                if name.isEmpty { name = run }
            }
            return (name, script)
        }

        /// The card-sized paint PNG for a BMAP block, or nil if it has no image.
        func bmapPaintPNG(_ block: BlockInfo, cardWidth: Int, cardHeight: Int) -> Data? {
            WobaBitmap.paintPNG(block: d, at: block.offset, cardWidth: cardWidth, cardHeight: cardHeight, headerDelta: headerDelta)
        }

        /// Parse the field-content section: `[u16 sectionSize]` followed by a
        /// run of `[i16 partID][NUL-terminated text]` entries. Anchors on the
        /// first offset whose size is sane and whose first entry names a known
        /// field, then reads entries until the section is consumed.
        private func parseContents(from afterParts: Int, end: Int, fieldIDs: Set<Int>) -> (contents: [Int: String], sectionEnd: Int) {
            var result: [Int: String] = [:]
            var sectionStart = -1
            for o in stride(from: afterParts, to: min(afterParts + 0x24, end - 4), by: 2) where isContentSection(o, end: end, fieldIDs: fieldIDs) {
                sectionStart = o; break
            }
            // No content section: name/script follow the parts directly.
            guard sectionStart >= 0 else { return (result, afterParts) }
            let sectionEnd = min(sectionStart + 2 + u16(sectionStart), end)
            var p = sectionStart + 2
            while p + 2 <= sectionEnd {
                let partID = i16(p)
                p += 2
                let textStart = p
                while p < sectionEnd, d[p] != 0 { p += 1 }
                let text = contentText(from: textStart, to: p)
                if result[partID] == nil, !text.isEmpty { result[partID] = text }
                p += 1 // skip the NUL terminator
            }
            return (result, sectionEnd)
        }

        /// HyperCard 2.x part-content section: a run of entries, each
        /// `[s16 partID][u16 length][length bytes]`, padded to an even total.
        /// A positive partID is a background field, negative a card field
        /// (keyed here by absolute id, matching how parts are filled). Each
        /// content begins with a style header: a `0x00` byte (plain text
        /// follows) or a `u16` with the high bit set (`0x8000 | styleRunBytes`,
        /// then that many style-run bytes, then the text). Skipping it exactly
        /// avoids leaking a style byte into the text as a stray leading return.
        /// Entries run until the next word isn't a known field id — that's
        /// where the object's name and script C-strings begin.
        private func parseContentsV2(from start: Int, end: Int, knownIDs: Set<Int>) -> (contents: [Int: String], sectionEnd: Int) {
            var result: [Int: String] = [:]
            var o = start
            while o + 4 <= end {
                let absID = abs(i16(o))
                guard absID != 0, knownIDs.contains(absID) else { break }
                let length = u16(o + 2)
                guard length >= 1, o + 4 + length <= end else { break }
                let contentStart = o + 4, contentEnd = o + 4 + length
                var textStart = contentStart
                if length >= 2, d[contentStart] & 0x80 != 0 {
                    let styleBytes = u16(contentStart) & 0x7FFF
                    textStart = min(contentStart + 2 + styleBytes, contentEnd)
                } else if d[contentStart] == 0 {
                    textStart = contentStart + 1 // a lone 0 style flag
                }
                let text = contentText(from: textStart, to: contentEnd)
                if result[absID] == nil, !text.isEmpty { result[absID] = text }
                o += 4 + length
                if o & 1 != 0 { o += 1 } // entries pad to an even boundary
            }
            return (result, o)
        }

        /// Whether `o` begins a content section: a plausible size word, then a
        /// first entry whose partID is a known field with printable text.
        private func isContentSection(_ o: Int, end: Int, fieldIDs: Set<Int>) -> Bool {
            guard o + 4 <= end else { return false }
            let size = u16(o)
            guard size >= 4, o + 2 + size <= end else { return false }
            let partID = i16(o + 2)
            guard fieldIDs.isEmpty ? (1...8192).contains(abs(partID)) : fieldIDs.contains(partID) else { return false }
            for i in (o + 4)..<min(o + 2 + size, end) where d[i] >= 0x20 { return true }
            return false
        }

        /// Field text for one entry: skip a leading style prefix (styled fields
        /// prepend high/control bytes), then keep printable text and carriage
        /// returns, dropping interior style/control bytes.
        private func contentText(from start: Int, to textEnd: Int) -> String {
            var i = start
            while i < textEnd, d[i] >= 0x80 || (d[i] < 0x20 && d[i] != 0x0D) { i += 1 }
            var bytes: [UInt8] = []
            while i < textEnd {
                let b = d[i]
                if b == 0x0D || b >= 0x20 { bytes.append(b) }
                i += 1
            }
            return roman(bytes)
        }

        private struct PlacedPart { let part: RawPart; let recordEnd: Int }

        /// Find and parse the part-record chain, avoiding a dependency on
        /// per-block-type header sizes (which differ between CARD and BKGD).
        /// A naive "first plausible record" scan can latch onto a false
        /// positive in the header (e.g. a bogus id-0 record) and stop after one
        /// part; the real chain then reads as content/name garbage. So measure
        /// the chain length from every candidate start and keep the longest —
        /// false starts and mid-chain starts are always shorter than the true
        /// beginning.
        private func parseParts(base: Int, end: Int) -> [PlacedPart] {
            func chainLength(from start: Int) -> Int {
                var o = start, count = 0
                while o + 0x1E < end, isPart(o, end: end) { count += 1; o += u16(o) }
                return count
            }
            var bestStart = -1, bestCount = 0
            for start in stride(from: base + 0x20, to: base + 0x60, by: 2) where start + 0x20 < end {
                guard isPart(start, end: end) else { continue }
                let count = chainLength(from: start)
                if count > bestCount { bestCount = count; bestStart = start }
            }
            guard bestStart >= 0 else { return [] }
            var parts: [PlacedPart] = []
            var o = bestStart
            while o + 0x1E < end, isPart(o, end: end) {
                let size = u16(o)
                parts.append(PlacedPart(part: readPart(o), recordEnd: o + size))
                o += size
            }
            return parts
        }

        /// A plausible part record: sane size, a button/field type byte, and a
        /// rectangle that isn't degenerate.
        private func isPart(_ o: Int, end: Int) -> Bool {
            guard o + 0x1E <= end else { return false }
            let size = u16(o)
            guard size >= 0x1E, o + size <= end else { return false }
            let type = d[o + 4]
            guard type == 1 || type == 2 else { return false }
            let top = i16(o + 6), left = i16(o + 8), bottom = i16(o + 10), right = i16(o + 12)
            return bottom > top && right > left
                && (-64...2048).contains(top) && (-64...2048).contains(left)
                && (top...2048).contains(bottom) && (left...2048).contains(right)
        }

        private func readPart(_ o: Int) -> RawPart {
            let size = u16(o)
            let type: PartType = d[o + 4] == 1 ? .button : .field
            let nameBytes = bytesUntilNUL(o + 0x1E, limit: o + size)
            // The script follows the name, but is padded to an even boundary,
            // so odd-length names leave an extra NUL before it — skip any run.
            var scriptStart = o + 0x1E + nameBytes.count + 1
            while scriptStart < o + size, d[scriptStart] == 0 { scriptStart += 1 }
            let scriptBytes = scriptStart < o + size ? bytesUntilNUL(scriptStart, limit: o + size) : []
            return RawPart(id: i16(o + 2), type: type, top: i16(o + 6), left: i16(o + 8),
                           bottom: i16(o + 10), right: i16(o + 12),
                           name: roman(nameBytes), script: roman(scriptBytes),
                           styleByte: Int(d[o + 0x0F]) & 0x0F,
                           showName: (d[o + 0x0E] & 0x80) != 0,
                           showLines: (d[o + 0x0E] & 0x40) != 0,
                           hilite: (d[o + 0x0E] & 0x40) != 0,
                           autoHilite: (d[o + 0x0E] & 0x20) != 0,
                           lockText: (d[o + 5] & 0x01) != 0,
                           sharedText: (d[o + 5] & 0x08) != 0,
                           iconID: i16(o + 0x12),
                           visible: (d[o + 5] & 0x80) == 0,
                           textAlign: i16(o + 0x14), fontID: i16(o + 0x16),
                           textSize: i16(o + 0x18), textStyleBits: Int(d[o + 0x1A]))
        }

        // MARK: string helpers

        /// Raw bytes up to the next NUL (or limit).
        private func bytesUntilNUL(_ o: Int, limit: Int) -> [UInt8] {
            var bytes: [UInt8] = []
            var i = o
            while i < min(limit, d.count), d[i] != 0 { bytes.append(d[i]); i += 1 }
            return bytes
        }

        /// Decode Mac Roman and normalize HyperCard's CR line endings to LF.
        private func roman(_ bytes: [UInt8]) -> String {
            let s = String(bytes: bytes, encoding: .macOSRoman) ?? String(decoding: bytes, as: UTF8.self)
            return s.replacingOccurrences(of: "\r", with: "\n")
        }

        /// Extract cleaned Mac Roman runs (text + carriage returns) between NUL
        /// separators — how card field contents and scripts sit in the block.
        /// Each run is trimmed of a leading style/binary prefix, and runs that
        /// are mostly non-text (bitmap bleed, block tags) are dropped.
        func textRuns(from start: Int, end: Int) -> [String] {
            var runs: [String] = []
            var bytes: [UInt8] = []
            func flush() {
                if let run = clean(bytes) { runs.append(run) }
                bytes.removeAll(keepingCapacity: true)
            }
            var i = max(start, 0)
            while i < min(end, d.count) {
                let b = d[i]
                if b == 0 { flush() }
                else if b == 0x0D || b >= 0x20 { bytes.append(b) }   // text or CR
                else { flush() }                                     // other control: break run
                i += 1
            }
            flush()
            return runs
        }

        /// Turn a raw run into clean field text, or nil if it's noise. Strips a
        /// leading style prefix (styled fields prepend high/■ bytes) and rejects
        /// runs that are too short, too binary, or a stray block tag.
        private func clean(_ raw: [UInt8]) -> String? {
            var bytes = raw
            // Drop a short leading style/binary prefix (non-ASCII, non-CR).
            var lead = 0
            while lead < bytes.count, lead < 8, bytes[lead] >= 0x80 || (bytes[lead] < 0x20 && bytes[lead] != 0x0D) {
                lead += 1
            }
            bytes.removeFirst(lead)
            guard bytes.count >= 2 else { return nil }
            // Reject mostly-binary runs (bitmap bleed).
            let highBytes = bytes.filter { $0 >= 0x80 || ($0 < 0x20 && $0 != 0x0D) }.count
            if highBytes * 3 > bytes.count { return nil }
            let text = roman(bytes)
            // Reject stray block tags that can abut the content region.
            for tag in ["BMAP", "CARD", "BKGD", "PAGE", "LIST", "STAK", "TAIL", "FREE", "MAST"] where text.hasPrefix(tag) {
                return nil
            }
            return text
        }

        func looksLikeScript(_ run: String) -> Bool {
            let lower = run.lowercased()
            return (lower.hasPrefix("on ") || lower.contains("\non ") || lower.hasPrefix("function "))
                && lower.contains("end ")
        }
    }
}
