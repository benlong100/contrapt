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

    /// Reads `data` (a classic stack's data fork) into a Contrapt `Stack`.
    static func stack(from data: Data, name: String) throws -> Stack {
        let reader = Reader(data)
        guard reader.tag(at: 0) == "STAK" else {
            throw ImportError(message: "This doesn't look like a HyperCard stack (no STAK header). If it came as a .hqx or .sit, unpack it first.")
        }
        let blocks = reader.walkBlocks()

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
                          cardSize: CardSize(width: 512, height: 342), // HC 1.x screen
                          script: "", backgrounds: [], cards: [])

        var bgInfoByID: [Int: ParsedObject] = [:]
        var bgUUIDByID: [Int: UUID] = [:]
        var fieldIDs = Set<Int>()
        for block in blocks where block.type == "BKGD" {
            let parsed = reader.parseObject(block, knownFieldIDs: [])
            bgInfoByID[block.id] = parsed
            fieldIDs.formUnion(parsed.parts.filter { $0.type == .field }.map(\.id))
            var background = Background(id: UUID(), name: parsed.name.isEmpty ? "Background \(stack.backgrounds.count + 1)" : parsed.name,
                                        script: parsed.script, parts: [])
            background.scriptID = stack.claimScriptID()
            background.parts = parsed.parts.filter { $0.type == .button }.map { part(from: $0, in: &stack) }
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
            let parsed = reader.parseObject(block, knownFieldIDs: fieldIDs)
            let bgID = parsed.ownerBackgroundID
            let backgroundUUID = bgUUIDByID[bgID] ?? stack.backgrounds[0].id
            let templateFields = (bgInfoByID[bgID]?.parts ?? []).filter { $0.type == .field }

            var card = Card(id: UUID(),
                            name: parsed.name.isEmpty ? "Card \(stack.cards.count + 1)" : parsed.name,
                            backgroundID: backgroundUUID, script: parsed.script, parts: [])
            card.scriptID = stack.claimScriptID()

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
                var cardPart = part(from: raw, in: &stack)
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
        return stack.sanitized()
    }

    /// Imports the classic stack at `source` and writes it as a `.contrapt`
    /// file in the temporary directory, returning that URL to open. Artwork is
    /// deferred (Phase 1), so no assets are written.
    static func importedContraptFile(from source: URL) throws -> URL {
        let didAccess = source.startAccessingSecurityScopedResource()
        defer { if didAccess { source.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: source)
        let name = source.deletingPathExtension().lastPathComponent
        let imported = try stack(from: data, name: name.isEmpty ? "Imported Stack" : name)
        let archive = ZipArchive.archive(["stack.json": try imported.fileData()])
        // A unique subdirectory per import keeps the friendly filename while
        // ensuring the path is new — otherwise NSDocumentController dedupes by
        // URL and refocuses a previously-imported (stale) window.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory
            .appendingPathComponent(imported.name)
            .appendingPathExtension("contrapt")
        try archive.write(to: url)
        return url
    }

    // MARK: - Raw → Contrapt part

    private static func part(from raw: RawPart, in stack: inout Stack) -> Part {
        let frame = PartFrame(x: Double(raw.left), y: Double(raw.top),
                              width: Double(max(8, raw.right - raw.left)),
                              height: Double(max(8, raw.bottom - raw.top)))
        let kind: PartKind
        switch raw.type {
        case .button:
            var button = ButtonPart(title: raw.name)
            button.style = raw.buttonStyle
            // Icon buttons (name hidden in HyperCard) would otherwise show
            // truncated text; keep them nameless until icons arrive (Phase 2).
            button.showName = raw.showName
            kind = .button(button)
        case .field:
            var field = FieldPart(text: "", placeholder: "", isMultiline: true)
            field.style = raw.fieldStyle
            // Imported fields are display-only (a read-only reproduction):
            // locked text renders as static text — no editor scrollbar — and
            // still dispatches taps to scripts. Unlock per-field in the
            // inspector to edit. Style 4 is HyperCard's scrolling field.
            field.lockText = true
            kind = .field(field)
        }
        var part = Part(id: UUID(), name: raw.name, frame: frame,
                        script: raw.script, kind: kind)
        part.isVisible = raw.visible
        part.scriptID = stack.claimScriptID()
        return part
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
        var hasIcon: Bool
        var visible: Bool
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
        var parts: [RawPart]
        /// Field text keyed by the field's HyperCard part id — how card
        /// contents are stored, so mapping is exact rather than positional.
        var contents: [Int: String]
    }

    struct BlockInfo { let type: String; let offset: Int; let size: Int; let id: Int }

    struct Reader {
        let d: [UInt8]
        init(_ data: Data) { d = [UInt8](data) }

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

        /// Parse a CARD or BKGD block into parts, contents, and script.
        /// `knownFieldIDs` anchors the content-entry scan (card contents are
        /// keyed by the background's field ids).
        func parseObject(_ block: BlockInfo, knownFieldIDs: Set<Int>) -> ParsedObject {
            let base = block.offset, end = block.offset + block.size
            let ownerBackground = block.type == "CARD" ? u32(base + 0x20) : block.id
            let parts = parseParts(base: base, end: end)
            let afterParts = parts.last?.recordEnd ?? (base + 0x24)
            let ownFieldIDs = Set(parts.map(\.part).filter { $0.type == .field }.map(\.id))

            let contents = parseContents(from: afterParts, end: end, fieldIDs: knownFieldIDs.union(ownFieldIDs))
            // The object's own script is a handler-looking run in the block.
            var script = ""
            for run in textRuns(from: afterParts, end: end) where looksLikeScript(run) {
                script = run; break
            }
            return ParsedObject(name: "", script: script,
                                ownerBackgroundID: ownerBackground,
                                parts: parts.map(\.part), contents: contents)
        }

        /// Parse the field-content section: `[u16 sectionSize]` followed by a
        /// run of `[i16 partID][NUL-terminated text]` entries. Anchors on the
        /// first offset whose size is sane and whose first entry names a known
        /// field, then reads entries until the section is consumed.
        private func parseContents(from afterParts: Int, end: Int, fieldIDs: Set<Int>) -> [Int: String] {
            var result: [Int: String] = [:]
            var sectionStart = -1
            for o in stride(from: afterParts, to: min(afterParts + 0x24, end - 4), by: 2) where isContentSection(o, end: end, fieldIDs: fieldIDs) {
                sectionStart = o; break
            }
            guard sectionStart >= 0 else { return result }
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
            return result
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

        /// Find and parse the part-record chain. Scans for the first offset
        /// that begins a run of ≥1 plausible part records (avoids depending on
        /// per-block-type header sizes, which differ between CARD and BKGD).
        private func parseParts(base: Int, end: Int) -> [PlacedPart] {
            for start in stride(from: base + 0x20, to: base + 0x60, by: 2) where start + 0x20 < end {
                if isPart(start, end: end) {
                    var parts: [PlacedPart] = []
                    var o = start
                    while o + 0x1E < end, isPart(o, end: end) {
                        let size = u16(o)
                        parts.append(PlacedPart(part: readPart(o), recordEnd: o + size))
                        o += size
                    }
                    if !parts.isEmpty { return parts }
                }
            }
            return []
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
                           hasIcon: i16(o + 0x12) != 0,
                           visible: (d[o + 5] & 0x80) == 0)
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
