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

    /// One palette button from a PLTE resource: its rect (card coordinates)
    /// and the HyperTalk command/message sent when clicked.
    struct PaletteButton {
        let top: Int, left: Int, bottom: Int, right: Int
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
            // p+8..p+9 = icon id (unused — icons live in a separate PICT/ICON).
            let len = Int(d[p + 10])
            let start = p + 11
            guard start + len <= d.count else { break }
            let command = (String(bytes: d[start..<start+len], encoding: .macOSRoman) ?? "")
                .trimmingCharacters(in: .whitespaces)
            buttons.append(PaletteButton(top: top, left: left, bottom: bottom, right: right, command: command))
            p = start + len
        }
        return buttons
    }

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
