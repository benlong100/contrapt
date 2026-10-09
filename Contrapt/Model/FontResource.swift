//
//  FontResource.swift
//  Contrapt
//
//  Reader for classic Mac font resources embedded in a stack's resource fork:
//  FOND (a family — its name, ID, and which strike resources hold each size)
//  and FONT/NFNT (a bitmap strike — the glyphs plus per-character widths).
//
//  Contrapt renders text with modern fonts, so embedded fonts are never
//  installed; instead the importer resolves each family to the closest of its
//  four designs, calibrated so line breaks hold:
//   1. by NAME — an embedded "Palatino"/"Times"/"Courier" maps exactly like
//      the built-in system font of that name;
//   2. by METRICS — an unknown family classifies as monospaced when its strike
//      widths are uniform (else sans), and its width calibration is computed:
//      the strike's average advance versus the substitute's, measured with the
//      same platform font the app renders with — the same ratio previously
//      hand-tuned per family (see LegacyStackImporter.classicFontMap).
//
//  The resolution lands in Stack.fonts (name/design/scale per classic ID) —
//  provenance for a future user-editable mapping — and in each part's baked
//  TextFormat. Parsing is pure Foundation; only the substitute measurement
//  touches CoreText.
//

import Foundation
import CoreText
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

enum FontResource {
    /// One embedded family: its classic ID (what part records reference), its
    /// name, and the metrics of its best strike (nil when no strike decodes).
    struct Family {
        var id: Int
        var name: String
        var strike: StrikeMetrics?
    }

    /// A bitmap strike's layout-relevant numbers.
    struct StrikeMetrics {
        /// The strike's point size (from the FOND association entry).
        var pointSize: Int
        /// Mean advance of the printable ASCII characters present.
        var averageWidth: Double
        /// True when every present character has the same advance.
        var isFixedWidth: Bool
    }

    /// A real outline font embedded in the stack (a classic `sfnt` resource,
    /// which is a TrueType font verbatim). `familyID` is the matching FOND's id
    /// — the id a part's text references — and `postScriptName` is the name to
    /// register and render with. Decorative stack fonts (a Klingon or Star Trek
    /// face) only mean anything as their real glyphs, so these are rendered
    /// directly rather than mapped to a system design.
    struct EmbeddedFont {
        var familyID: Int
        var postScriptName: String
        var ttf: Data
    }

    /// Every embedded TrueType font in the fork: each `sfnt` matched to its
    /// same-named FOND (for the family id parts reference) with its PostScript
    /// name read from the font itself. `sfnt`-less stacks return nothing.
    static func embeddedTrueTypeFonts(from fork: Data) -> [EmbeddedFont] {
        let sfnts = ResourceFork.namedResources(ofType: "sfnt", from: fork)
        guard !sfnts.isEmpty else { return [] }
        let fonds = ResourceFork.namedResources(ofType: "FOND", from: fork)
        var result: [EmbeddedFont] = []
        for fond in fonds where !fond.name.isEmpty {
            guard let sfnt = sfnts.first(where: { $0.name.caseInsensitiveCompare(fond.name) == .orderedSame }),
                  let provider = CGDataProvider(data: sfnt.data as CFData),
                  let cgFont = CGFont(provider),
                  let postScriptName = cgFont.postScriptName as String? else { continue }
            result.append(EmbeddedFont(familyID: fond.id, postScriptName: postScriptName, ttf: sfnt.data))
        }
        return result
    }

    /// Every font family in the fork, via its FONDs. A family's metrics come
    /// from its largest plain-style strike (better width resolution than the
    /// small sizes).
    static func families(from fork: Data) -> [Family] {
        // Strikes are FONT or NFNT resources, referenced by ID from the FOND's
        // association table.
        var strikesByID: [Int: Data] = [:]
        for type in ["FONT", "NFNT"] {
            for resource in ResourceFork.namedResources(ofType: type, from: fork) {
                strikesByID[resource.id] = resource.data
            }
        }
        return ResourceFork.namedResources(ofType: "FOND", from: fork).map { fond in
            var best: (size: Int, metrics: StrikeMetrics)?
            for entry in associations(in: fond.data) where entry.style == 0 {
                guard entry.size > (best?.size ?? 0),
                      let strike = strikesByID[entry.strikeID],
                      let metrics = strikeMetrics(strike, pointSize: entry.size) else { continue }
                best = (entry.size, metrics)
            }
            return Family(id: fond.id, name: fond.name, strike: best?.metrics)
        }
    }

    /// The FOND's font association table: which FONT/NFNT resource holds each
    /// (pointSize, style) strike. At offset 52: count-1, then 6-byte entries.
    private static func associations(in fond: Data) -> [(size: Int, style: Int, strikeID: Int)] {
        let d = [UInt8](fond)
        func u16(_ o: Int) -> Int { o + 2 <= d.count ? Int((UInt16(d[o]) << 8) | UInt16(d[o+1])) : 0 }
        guard d.count >= 54 else { return [] }
        let count = u16(52) + 1
        var entries: [(Int, Int, Int)] = []
        for index in 0..<count {
            let base = 54 + index * 6
            guard base + 6 <= d.count else { break }
            entries.append((u16(base), u16(base + 2), u16(base + 4)))
        }
        return entries
    }

    /// Reads a FONT/NFNT strike's width table. Header (big-endian words):
    /// fontType, firstChar, lastChar, widMax, kernMax, nDescent, fRectWidth,
    /// fRectHeight, owTLoc, ascent, descent, leading, rowWords, … The
    /// offset/width table sits owTLoc *words* after the owTLoc field itself
    /// (offset 16); each entry's low byte is the character's advance, 0xFFFF
    /// meaning "missing".
    static func strikeMetrics(_ data: Data, pointSize: Int) -> StrikeMetrics? {
        let d = [UInt8](data)
        func u16(_ o: Int) -> Int { o + 2 <= d.count ? Int((UInt16(d[o]) << 8) | UInt16(d[o+1])) : 0 }
        guard d.count >= 26, pointSize > 0 else { return nil }
        let firstChar = u16(2), lastChar = u16(4)
        guard lastChar >= firstChar, lastChar <= 255 else { return nil }
        let tableStart = 16 + u16(16) * 2
        var widths: [Int] = []
        // Printable ASCII only — the range line-break layout depends on.
        for character in max(32, firstChar)...min(126, lastChar) {
            let entry = tableStart + (character - firstChar) * 2
            guard entry + 2 <= d.count else { return nil }
            let value = u16(entry)
            guard value != 0xFFFF else { continue }
            widths.append(value & 0xFF)
        }
        guard !widths.isEmpty else { return nil }
        let average = Double(widths.reduce(0, +)) / Double(widths.count)
        // "Fixed" tolerates the odd 1px outlier some strikes carry.
        let isFixed = widths.allSatisfy { abs($0 - widths[0]) <= 1 }
        return StrikeMetrics(pointSize: pointSize, averageWidth: average, isFixedWidth: isFixed)
    }

    // MARK: - Resolution

    /// How an embedded family renders in Contrapt: one of the four designs
    /// plus a point-size calibration (see LegacyStackImporter.classicFontMap
    /// for the hand-tuned equivalents this generalizes).
    struct Resolution {
        var name: String
        var design: FontDesign
        var scale: Double
        /// Set when the family is embedded as a real outline font — the
        /// PostScript name to render with (its glyphs), bypassing the design
        /// substitute. Nil for the bitmap-metrics / substitute case.
        var postScriptName: String? = nil
    }

    /// Families whose names identify them, mapped like their built-in classic
    /// IDs: serifs render as real Palatino at 1:1 (see TextFormat.font), mono
    /// grids already match, and classic sans bitmaps need the 0.85 the
    /// hand-tuned table uses.
    private static let serifNames = ["times", "palatino", "new york", "bookman", "schoolbook", "garamond"]
    private static let monoNames = ["courier", "monaco"]
    private static let sansNames = ["geneva", "chicago", "helvetica", "avant garde"]

    /// Resolves an embedded family: by name when recognized, else by strike
    /// metrics (uniform widths → monospaced, otherwise sans) with a measured
    /// width calibration. Returns nil for a nameless family with no readable
    /// strike — there's nothing to go on, so the importer's default applies.
    static func resolve(_ family: Family, proportionalScale: Double) -> Resolution? {
        let name = family.name.lowercased()
        if !name.isEmpty {
            if serifNames.contains(where: { name.contains($0) }) {
                return Resolution(name: family.name, design: .serif, scale: 1.0)
            }
            if monoNames.contains(where: { name.contains($0) }) {
                return Resolution(name: family.name, design: .monospaced, scale: 1.0)
            }
            if sansNames.contains(where: { name.contains($0) }) {
                return Resolution(name: family.name, design: .standard, scale: proportionalScale)
            }
        }
        guard let strike = family.strike else {
            return name.isEmpty ? nil : Resolution(name: family.name, design: .standard, scale: proportionalScale)
        }
        let design: FontDesign = strike.isFixedWidth ? .monospaced : .standard
        // Calibrate: the strike's average advance per point against the
        // substitute's, measured with the font the app really renders. Clamped
        // — a decorative strike's extremes shouldn't make text unreadable.
        var scale = proportionalScale
        if let substitute = measuredAverageWidth(design: design, size: Double(strike.pointSize)), substitute > 0 {
            scale = min(1.25, max(0.6, strike.averageWidth / substitute))
        } else if strike.isFixedWidth {
            scale = 1.0
        }
        return Resolution(name: family.name, design: design, scale: scale)
    }

    /// Registers a stack's embedded outline fonts with the process font
    /// manager so `Font.custom(postScriptName)` and `NSFont/UIFont(name:)`
    /// resolve them. Idempotent per PostScript name — safe to call on every
    /// open. Writes each `.ttf` to a caches file and registers its URL (the
    /// non-deprecated, synchronous API). Call on the main actor as the stack
    /// opens, before its text first renders.
    @MainActor
    static func registerEmbeddedFonts(_ fonts: [String: StackFont], assets: [String: Data]) {
        for font in fonts.values {
            guard let name = font.postScriptName, let assetName = font.fontAsset,
                  !registeredFontNames.contains(name), let data = assets[assetName] else { continue }
            if registerFontData(data, named: name) { registeredFontNames.insert(name) }
        }
    }

    @MainActor private static var registeredFontNames = Set<String>()

    @MainActor
    private static func registerFontData(_ data: Data, named name: String) -> Bool {
        guard let dir = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
            .appendingPathComponent("EmbeddedFonts", isDirectory: true) else { return false }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = name.components(separatedBy: CharacterSet(charactersIn: "/:")).joined(separator: "-")
        let url = dir.appendingPathComponent(safe).appendingPathExtension("ttf")
        guard (try? data.write(to: url)) != nil else { return false }
        var error: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        error?.release()
        return ok
    }

    /// The substitute font's mean advance over printable ASCII at `size` —
    /// the same platform font the app's fields render with.
    static func measuredAverageWidth(design: FontDesign, size: Double) -> Double? {
        var format = TextFormat()
        format.fontDesign = design
        format.size = size
        let platformFont = FieldClickHitTest.platformFont(for: format)
        // Bridge through the descriptor, not the name — CoreText refuses
        // system-font names (".SFNS-…") by name and substitutes Times.
        let font = CTFontCreateWithFontDescriptor(platformFont.fontDescriptor as CTFontDescriptor, size, nil)
        let characters = Array(UnicodeScalar(32)!.value...UnicodeScalar(126)!.value)
            .compactMap { UnicodeScalar($0).map(Character.init) }
        var chars = characters.map { $0.utf16.first! }
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        guard CTFontGetGlyphsForCharacters(font, &chars, &glyphs, chars.count) else { return nil }
        var advances = [CGSize](repeating: .zero, count: glyphs.count)
        CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, glyphs.count)
        let total = advances.reduce(0.0) { $0 + Double($1.width) }
        return total / Double(advances.count)
    }
}
