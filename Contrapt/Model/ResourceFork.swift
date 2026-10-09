//
//  ResourceFork.swift
//  Contrapt
//
//  A minimal classic Mac resource-fork reader, used by the legacy importer to
//  pull button ICON resources out of a user-supplied HyperCard application.
//  HyperCard's built-in button icons live in the app (not in stacks), so an
//  imported stack references them by id; we resolve those ids against the
//  app the user points us at and embed only the used icons into the imported
//  stack. Contrapt itself ships no Apple icons.
//
//  Pure Foundation + CoreGraphics/ImageIO — cross platform, in-sandbox.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

enum ResourceFork {
    /// The resource-fork bytes of a file: the `..namedfork/rsrc` fork if it has
    /// one (classic apps keep everything there), else the data fork if that
    /// looks like a resource map (some transfers flatten the fork into data).
    static func forkData(of url: URL) -> Data? {
        let rsrc = URL(fileURLWithPath: url.path + "/..namedfork/rsrc")
        if let data = try? Data(contentsOf: rsrc), data.count >= 16 { return data }
        if let data = try? Data(contentsOf: url), looksLikeResourceMap(data) { return data }
        return nil
    }

    /// Every `ICON` resource (id → 128-byte 1-bit 32×32 bitmap) in the fork.
    static func icons(from fork: Data) -> [Int: Data] {
        let d = [UInt8](fork)
        guard d.count >= 16 else { return [:] }
        func u32(_ o: Int) -> Int { o + 4 <= d.count ? Int((UInt32(d[o]) << 24) | (UInt32(d[o+1]) << 16) | (UInt32(d[o+2]) << 8) | UInt32(d[o+3])) : 0 }
        func u16(_ o: Int) -> Int { o + 2 <= d.count ? Int((UInt16(d[o]) << 8) | UInt16(d[o+1])) : 0 }
        func i16(_ o: Int) -> Int { Int(Int16(bitPattern: UInt16(u16(o)))) }

        let dataOffset = u32(0), mapOffset = u32(4)
        guard mapOffset + 28 <= d.count else { return [:] }
        let typeListStart = mapOffset + u16(mapOffset + 24)
        guard typeListStart + 2 <= d.count else { return [:] }
        let typeCount = u16(typeListStart) + 1

        var result: [Int: Data] = [:]
        var p = typeListStart + 2
        for _ in 0..<typeCount {
            guard p + 8 <= d.count else { break }
            let type = String(bytes: d[p..<p+4], encoding: .macOSRoman) ?? ""
            let refCount = u16(p + 4) + 1
            let refListStart = typeListStart + u16(p + 6)
            if type == "ICON" {
                var r = refListStart
                for _ in 0..<refCount {
                    guard r + 12 <= d.count else { break }
                    let id = i16(r)
                    let resourceOffset = (Int(d[r+5]) << 16) | (Int(d[r+6]) << 8) | Int(d[r+7])
                    let base = dataOffset + resourceOffset
                    let length = u32(base)
                    if length >= 128, base + 4 + 128 <= d.count {
                        result[id] = Data(d[(base + 4)..<(base + 4 + 128)])
                    }
                    r += 12
                }
            }
            p += 8
        }
        return result
    }

    /// The names of every XCMD/XFCN resource in the fork — the stack's
    /// external commands and functions. Contrapt can't run the compiled code,
    /// but the interpreter uses the names to no-op calls to them instead of
    /// raising "Can't understand" (Power Tools' `GeneralPalette`, `showList`).
    static func externalNames(from fork: Data) -> [String] {
        let d = [UInt8](fork)
        guard d.count >= 16 else { return [] }
        func u32(_ o: Int) -> Int { o + 4 <= d.count ? Int((UInt32(d[o]) << 24) | (UInt32(d[o+1]) << 16) | (UInt32(d[o+2]) << 8) | UInt32(d[o+3])) : 0 }
        func u16(_ o: Int) -> Int { o + 2 <= d.count ? Int((UInt16(d[o]) << 8) | UInt16(d[o+1])) : 0 }

        let mapOffset = u32(4)
        guard mapOffset + 28 <= d.count else { return [] }
        let typeListStart = mapOffset + u16(mapOffset + 24)
        let nameListStart = mapOffset + u16(mapOffset + 26)
        guard typeListStart + 2 <= d.count else { return [] }
        let typeCount = u16(typeListStart) + 1

        var names: [String] = []
        var p = typeListStart + 2
        for _ in 0..<typeCount {
            guard p + 8 <= d.count else { break }
            let type = String(bytes: d[p..<p+4], encoding: .macOSRoman) ?? ""
            let refCount = u16(p + 4) + 1
            let refListStart = typeListStart + u16(p + 6)
            if type == "XCMD" || type == "XFCN" {
                var r = refListStart
                for _ in 0..<refCount {
                    guard r + 12 <= d.count else { break }
                    let nameOffset = u16(r + 2)
                    if nameOffset != 0xFFFF {
                        // A Pascal string in the name list: length byte + text.
                        let start = nameListStart + nameOffset
                        if start < d.count {
                            let length = Int(d[start])
                            if start + 1 + length <= d.count, length > 0,
                               let name = String(bytes: d[(start + 1)..<(start + 1 + length)], encoding: .macOSRoman) {
                                names.append(name)
                            }
                        }
                    }
                    r += 12
                }
            }
            p += 8
        }
        return names
    }

    /// Every resource of `type`, with its id, name (empty when unnamed), and
    /// bytes — the general walker behind sound extraction (`snd `). Follows
    /// the same map layout as icons/externalNames.
    static func namedResources(ofType wanted: String, from fork: Data) -> [(id: Int, name: String, data: Data)] {
        let d = [UInt8](fork)
        guard d.count >= 16 else { return [] }
        func u32(_ o: Int) -> Int { o + 4 <= d.count ? Int((UInt32(d[o]) << 24) | (UInt32(d[o+1]) << 16) | (UInt32(d[o+2]) << 8) | UInt32(d[o+3])) : 0 }
        func u16(_ o: Int) -> Int { o + 2 <= d.count ? Int((UInt16(d[o]) << 8) | UInt16(d[o+1])) : 0 }
        func i16(_ o: Int) -> Int { Int(Int16(bitPattern: UInt16(u16(o)))) }

        let dataOffset = u32(0), mapOffset = u32(4)
        guard mapOffset + 28 <= d.count else { return [] }
        let typeListStart = mapOffset + u16(mapOffset + 24)
        let nameListStart = mapOffset + u16(mapOffset + 26)
        guard typeListStart + 2 <= d.count else { return [] }
        let typeCount = u16(typeListStart) + 1

        var result: [(id: Int, name: String, data: Data)] = []
        var p = typeListStart + 2
        for _ in 0..<typeCount {
            guard p + 8 <= d.count else { break }
            let type = String(bytes: d[p..<p+4], encoding: .macOSRoman) ?? ""
            let refCount = u16(p + 4) + 1
            let refListStart = typeListStart + u16(p + 6)
            if type == wanted {
                var r = refListStart
                for _ in 0..<refCount {
                    guard r + 12 <= d.count else { break }
                    let id = i16(r)
                    var name = ""
                    let nameOffset = u16(r + 2)
                    if nameOffset != 0xFFFF {
                        let start = nameListStart + nameOffset
                        if start < d.count {
                            let length = Int(d[start])
                            if start + 1 + length <= d.count, length > 0 {
                                name = String(bytes: d[(start + 1)..<(start + 1 + length)], encoding: .macOSRoman) ?? ""
                            }
                        }
                    }
                    let resourceOffset = (Int(d[r+5]) << 16) | (Int(d[r+6]) << 8) | Int(d[r+7])
                    let base = dataOffset + resourceOffset
                    let length = u32(base)
                    if length > 0, base + 4 + length <= d.count {
                        result.append((id, name, Data(d[(base + 4)..<(base + 4 + length)])))
                    }
                    r += 12
                }
            }
            p += 8
        }
        return result
    }

    /// Render a 128-byte ICON (32×32, 1bpp, MSB first) to a PNG: black where a
    /// bit is set, transparent elsewhere — so it sits on a button like paint.
    static func iconPNG(_ icon: Data) -> Data? {
        guard icon.count >= 128 else { return nil }
        let bytes = [UInt8](icon)
        let size = 32
        var pixels = [UInt8](repeating: 0, count: size * size * 4) // RGBA, transparent
        for y in 0..<size {
            for x in 0..<size {
                let bit = (bytes[y * 4 + x / 8] >> (7 - (x & 7))) & 1
                guard bit == 1 else { continue }
                let p = (y * size + x) * 4
                pixels[p] = 0; pixels[p+1] = 0; pixels[p+2] = 0; pixels[p+3] = 255
            }
        }
        guard let context = CGContext(data: &pixels, width: size, height: size,
                                      bitsPerComponent: 8, bytesPerRow: size * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cgImage = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// Every `ICN#` resource — a 32×32 1-bit icon + mask pair (256 bytes).
    static func iconLists(from fork: Data) -> [Int: Data] {
        Dictionary(namedResources(ofType: "ICN#", from: fork).map { ($0.id, $0.data) },
                   uniquingKeysWith: { a, _ in a })
    }

    /// Every `cicn` (color icon) resource, raw.
    static func colorIcons(from fork: Data) -> [Int: Data] {
        Dictionary(namedResources(ofType: "cicn", from: fork).map { ($0.id, $0.data) },
                   uniquingKeysWith: { a, _ in a })
    }

    /// Render an `ICN#` (128 icon bytes + 128 mask bytes): transparent outside
    /// the mask, black where the icon bit is set, white elsewhere inside the
    /// mask — so solid-silhouette icons keep their white interiors on buttons.
    static func icnPNG(_ data: Data) -> Data? {
        guard data.count >= 256 else { return nil }
        let bytes = [UInt8](data)
        let size = 32
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let iconBit = (bytes[y * 4 + x / 8] >> (7 - (x & 7))) & 1
                let maskBit = (bytes[128 + y * 4 + x / 8] >> (7 - (x & 7))) & 1
                guard maskBit == 1 else { continue }
                let v: UInt8 = iconBit == 1 ? 0 : 255
                let p = (y * size + x) * 4
                pixels[p] = v; pixels[p+1] = v; pixels[p+2] = v; pixels[p+3] = 255
            }
        }
        return pngFromRGBA(&pixels, width: size, height: size)
    }

    /// Render a `cicn` color icon: PixMap header, mask/icon bitmaps, color
    /// table, then indexed pixel data (1/2/4/8-bit). The mask supplies alpha.
    static func cicnPNG(_ data: Data) -> Data? {
        let d = [UInt8](data)
        guard d.count > 0x52 else { return nil }
        func u16(_ o: Int) -> Int { Int((UInt16(d[o]) << 8) | UInt16(d[o+1])) }
        func i16(_ o: Int) -> Int { Int(Int16(bitPattern: UInt16(u16(o)))) }

        // IconPMap (a PixMap, 50 bytes from 0).
        let pixRowBytes = u16(0x04) & 0x3FFF
        let top = i16(0x06), left = i16(0x08), bottom = i16(0x0A), right = i16(0x0C)
        let width = right - left, height = bottom - top
        guard width > 0, height > 0, width <= 256, height <= 256 else { return nil }
        let pixelSize = u16(0x20)
        guard [1, 2, 4, 8].contains(pixelSize) else { return nil }
        // IconMask (BitMap at 0x32) and IconBMap (BitMap at 0x40).
        let maskRowBytes = u16(0x36)
        let iconRowBytes = u16(0x44)
        // Data follows the 4-byte iconData handle placeholder at 0x4E.
        let maskStart = 0x52
        let bmapStart = maskStart + maskRowBytes * height
        let tableStart = bmapStart + iconRowBytes * height
        guard tableStart + 8 <= d.count else { return nil }
        let entryCount = u16(tableStart + 6) + 1
        var colors: [Int: (UInt8, UInt8, UInt8)] = [:]
        var o = tableStart + 8
        for _ in 0..<entryCount {
            guard o + 8 <= d.count else { return nil }
            colors[u16(o)] = (d[o + 2], d[o + 4], d[o + 6]) // high byte of each 16-bit component
            o += 8
        }
        let pixelStart = o
        guard pixelStart + pixRowBytes * height <= d.count else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let perByte = 8 / pixelSize
        let indexMask = (1 << pixelSize) - 1
        for y in 0..<height {
            for x in 0..<width {
                let maskByte = maskStart + y * maskRowBytes + x / 8
                guard maskByte < d.count, (d[maskByte] >> (7 - (x & 7))) & 1 == 1 else { continue }
                let pixByte = pixelStart + y * pixRowBytes + x / perByte
                guard pixByte < d.count else { continue }
                let shift = (perByte - 1 - (x % perByte)) * pixelSize
                let index = (Int(d[pixByte]) >> shift) & indexMask
                let (r, g, b) = colors[index] ?? (0, 0, 0)
                let p = (y * width + x) * 4
                pixels[p] = r; pixels[p+1] = g; pixels[p+2] = b; pixels[p+3] = 255
            }
        }
        return pngFromRGBA(&pixels, width: width, height: height)
    }

    private static func pngFromRGBA(_ pixels: inout [UInt8], width: Int, height: Int) -> Data? {
        guard let context = CGContext(data: &pixels, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cgImage = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// One palette button from a PLTE resource: its rect (card coordinates),
    /// the id of the ICON/cicn/ICN# resource that draws it, and the HyperTalk
    /// command/message sent when clicked. `iconID` is 0 when the button has no
    /// icon (a text-only button).
    struct PaletteButton {
        let top: Int, left: Int, bottom: Int, right: Int
        let iconID: Int
        let command: String
    }

    /// Every `PLTE` resource (Apple's Palette XCMD definition) in the fork,
    /// id+name → its buttons. Format: a 22-byte header, a u16 button count,
    /// then per button `[i16 top,left,bottom,right][i16 iconID][u8 cmdLen]
    /// [cmd]`. The `palette "name"` call looks these up to render the window.
    static func palettes(from fork: Data) -> [(id: Int, name: String, buttons: [PaletteButton])] {
        namedResources(ofType: "PLTE", from: fork).map { resource in
            (resource.id, resource.name, parsePalette(resource.data))
        }
    }

    private static func parsePalette(_ data: Data) -> [PaletteButton] {
        let d = [UInt8](data)
        guard d.count >= 24 else { return [] }
        func i16(_ o: Int) -> Int { Int(Int16(bitPattern: (UInt16(d[o]) << 8) | UInt16(d[o+1]))) }
        func u16(_ o: Int) -> Int { Int((UInt16(d[o]) << 8) | UInt16(d[o+1])) }
        let count = u16(22)
        var buttons: [PaletteButton] = []
        var p = 24
        for _ in 0..<count {
            guard p + 11 <= d.count else { break }
            let top = i16(p), left = i16(p + 2), bottom = i16(p + 4), right = i16(p + 6)
            let iconID = i16(p + 8) // the ICON/cicn/ICN# resource that draws the button
            let len = Int(d[p + 10])
            let start = p + 11
            guard start + len <= d.count else { break }
            let command = (String(bytes: d[start..<start+len], encoding: .macOSRoman) ?? "")
                .trimmingCharacters(in: .whitespaces)
            buttons.append(PaletteButton(top: top, left: left, bottom: bottom, right: right, iconID: iconID, command: command))
            p = start + len
        }
        return buttons
    }

    // MARK: - AddColor / Color Tools color layer

    /// One decoded element of an `HCcd`/`HCbg` color resource. `rect` is in card
    /// coordinates (used by `.rect`/`.picture`); `partNumber` names the part a
    /// `.button`/`.field` tint applies to; `rgb` is three 16-bit channels;
    /// `pictName` is the `PICT` resource a `.picture` references by name.
    struct ColorElement {
        enum Kind { case button, field, rect, picture }
        let kind: Kind
        let hidden: Bool
        let top: Int, left: Int, bottom: Int, right: Int
        let partNumber: Int
        let rgb: (r: Int, g: Int, b: Int)
        let transparent: Bool
        let pictName: String
    }

    /// Decode every `HCcd` (cards) or `HCbg` (backgrounds) resource into its
    /// color elements, keyed by the resource id — which is the HyperCard card
    /// or background object id (so the importer matches them to its preserved
    /// scriptIDs). Format reverse-engineered + validated against the corpus: a
    /// flat element stream, each `u8 type` (high bit = hidden) then payload —
    /// 1 button / 2 field: `u16 part, u16 flags, RGB(3×u16)`; 3 rect: `Rect
    /// (4×i16), u16 flags, RGB`; 4 picture: `Rect, u8 transparent, Pascal name`.
    static func colorResources(ofType type: String, from fork: Data) -> [(id: Int, elements: [ColorElement])] {
        namedResources(ofType: type, from: fork).map { ($0.id, parseColorElements($0.data)) }
    }

    private static func parseColorElements(_ data: Data) -> [ColorElement] {
        let d = [UInt8](data)
        func u16(_ o: Int) -> Int { Int((UInt16(d[o]) << 8) | UInt16(d[o+1])) }
        func i16(_ o: Int) -> Int { Int(Int16(bitPattern: UInt16((UInt16(d[o]) << 8) | UInt16(d[o+1])))) }
        var elements: [ColorElement] = []
        var o = 0
        while o < d.count {
            let raw = d[o]; o += 1
            let hidden = raw & 0x80 != 0
            switch raw & 0x7F {
            case 1, 2:
                guard o + 10 <= d.count else { return elements }
                let kind: ColorElement.Kind = (raw & 0x7F) == 1 ? .button : .field
                elements.append(ColorElement(kind: kind, hidden: hidden, top: 0, left: 0, bottom: 0, right: 0,
                                             partNumber: u16(o), rgb: (u16(o+4), u16(o+6), u16(o+8)),
                                             transparent: false, pictName: ""))
                o += 10
            case 3:
                guard o + 16 <= d.count else { return elements }
                elements.append(ColorElement(kind: .rect, hidden: hidden,
                                             top: i16(o), left: i16(o+2), bottom: i16(o+4), right: i16(o+6),
                                             partNumber: 0, rgb: (u16(o+10), u16(o+12), u16(o+14)),
                                             transparent: false, pictName: ""))
                o += 16
            case 4:
                guard o + 10 <= d.count else { return elements }
                let top = i16(o), left = i16(o+2), bottom = i16(o+4), right = i16(o+6)
                let transparent = d[o+8] != 0
                let len = Int(d[o+9])
                let start = o + 10
                guard start + len <= d.count else { return elements }
                let name = String(bytes: d[start..<start+len], encoding: .macOSRoman) ?? ""
                elements.append(ColorElement(kind: .picture, hidden: hidden, top: top, left: left, bottom: bottom, right: right,
                                             partNumber: 0, rgb: (0, 0, 0), transparent: transparent, pictName: name))
                o = start + len
            default:
                return elements // unknown type: stop (the stream is sequential)
            }
        }
        return elements
    }

    /// A `PICT` resource rendered to PNG, found by name (Color Tools references
    /// pictures by name — `"Dictionary.bg"`, `"•btn cover"`). nil if absent or
    /// undecodable. PICT decoding uses AppKit's QuickDraw interpreter, so it's
    /// macOS-only; iOS color cards show their rect/tint elements without picts.
    static func pictPNG(named name: String, from fork: Data) -> Data? {
        guard let resource = namedResources(ofType: "PICT", from: fork)
            .first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return nil }
        return pictPNG(resource.data)
    }

    static func pictPNG(_ pictData: Data) -> Data? {
        #if canImport(AppKit)
        // A PICT *resource* has no 512-byte file header; NSPICTImageRep expects
        // one, so prepend zeros. Render the rep into a bitmap and emit PNG.
        var framed = Data(count: 512)
        framed.append(pictData)
        guard let rep = NSPICTImageRep(data: framed) else { return nil }
        let box = rep.boundingBox
        let width = Int(box.width.rounded()), height = Int(box.height.rounded())
        guard width > 0, height > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        rep.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        // Modern macOS no longer draws most classic color-PICT bitmap ops, so
        // NSPICTImageRep often returns correct bounds but renders NOTHING — a
        // fully transparent bitmap. Treat an essentially-empty render as a
        // failure (nil) rather than embedding a blank asset; real PICT color
        // then needs a hand-written QuickDraw decoder (see backlog).
        guard bitmapHasContent(bitmap) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
        #else
        return nil
        #endif
    }

    #if canImport(AppKit)
    /// Whether a rendered bitmap holds a real image — sampled on a grid. A
    /// failed classic PICT render (modern macOS doesn't draw most color-PICT
    /// ops) comes back either fully transparent or a single flat fill color;
    /// both are rejected. A genuine image is mostly opaque AND has several
    /// distinct colors, which this requires.
    private static func bitmapHasContent(_ bitmap: NSBitmapImageRep) -> Bool {
        let w = bitmap.pixelsWide, h = bitmap.pixelsHigh
        guard w > 0, h > 0 else { return false }
        let stepX = max(1, w / 64), stepY = max(1, h / 64)
        var sampled = 0, opaque = 0
        var colors = Set<UInt32>()
        var y = 0
        while y < h {
            var x = 0
            while x < w {
                sampled += 1
                if let c = bitmap.colorAt(x: x, y: y), c.alphaComponent > 0.01 {
                    opaque += 1
                    let r = UInt32(c.redComponent * 255), g = UInt32(c.greenComponent * 255), b = UInt32(c.blueComponent * 255)
                    colors.insert((r << 16) | (g << 8) | b)
                }
                x += stepX
            }
            y += stepY
        }
        guard sampled > 0 else { return false }
        return Double(opaque) / Double(sampled) > 0.02 && colors.count >= 8
    }
    #endif

    /// A quick sanity check that data begins with a plausible resource-fork
    /// header (data offset and map offset within bounds).
    private static func looksLikeResourceMap(_ data: Data) -> Bool {
        guard data.count >= 16 else { return false }
        let d = [UInt8](data.prefix(16))
        let dataOffset = Int((UInt32(d[0]) << 24) | (UInt32(d[1]) << 16) | (UInt32(d[2]) << 8) | UInt32(d[3]))
        let mapOffset = Int((UInt32(d[4]) << 24) | (UInt32(d[5]) << 16) | (UInt32(d[6]) << 8) | UInt32(d[7]))
        return dataOffset >= 16 && dataOffset < data.count && mapOffset >= 16 && mapOffset < data.count
    }
}
