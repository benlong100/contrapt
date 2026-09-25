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
