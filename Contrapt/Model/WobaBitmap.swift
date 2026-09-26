//
//  WobaBitmap.swift
//  Contrapt
//
//  Decoder for HyperCard's WOBA ("Wrath Of Bill Atkinson") 1-bit paint
//  bitmaps, used by the legacy importer (see LegacyStackImporter) to bring
//  card/background art across. Ported from Rebecca Bettencourt's reverse-
//  engineered format (kreativekorp.com) and validated against Apple's 1.2.5
//  sample stacks. Pure Foundation + CoreGraphics/ImageIO, so it's cross
//  platform and stays in the sandbox.
//
//  A BMAP block holds an image plane and a mask plane, each WOBA-compressed
//  within a bounding rectangle. For paint overlays we only need the image
//  (black where a bit is set, transparent elsewhere), which matches how the
//  card renders a paint layer over the surface.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum WobaBitmap {
    /// Decodes a BMAP block into a card-sized PNG (black paint on transparent),
    /// or nil if there's no image data. `cardSize` is the whole card; the
    /// bitmap is composited at its bounding-rect offset.
    /// `headerDelta` shifts every header field: HyperCard 2.x (STAK format
    /// version ≥ 9) inserts 4 bytes into block headers, so the whole BMAP
    /// header — rects and data lengths alike — moves by +4. 1.x passes 0.
    static func paintPNG(block: [UInt8], at blockOffset: Int, cardWidth: Int, cardHeight: Int, headerDelta: Int = 0) -> Data? {
        func u32(_ o: Int) -> Int { Int((UInt32(block[o]) << 24) | (UInt32(block[o+1]) << 16) | (UInt32(block[o+2]) << 8) | UInt32(block[o+3])) }
        func i16(_ o: Int) -> Int { Int(Int16(bitPattern: UInt16((UInt16(block[o]) << 8) | UInt16(block[o+1])))) }
        let base = blockOffset + headerDelta
        guard base + 0x3C <= block.count else { return nil }
        let imageLen = u32(base + 0x38)
        guard imageLen > 0 else { return nil }
        // Image bounding rect at +0x24; mask 0x1C; card rect 0x14.
        let top = i16(base + 0x24), left = i16(base + 0x26)
        let bottom = i16(base + 0x28), right = i16(base + 0x2A)
        let maskLen = u32(base + 0x34)
        let dataStart = base + 0x3C + maskLen
        guard dataStart + imageLen <= block.count else { return nil }
        let plane = decode(Array(block[dataStart..<dataStart + imageLen]), top: top, left: left, bottom: bottom, right: right)
        guard plane.rowBytes > 0, plane.height > 0 else { return nil }
        return renderPNG(plane: plane, offsetX: left & ~31, offsetY: top, cardWidth: cardWidth, cardHeight: cardHeight)
    }

    struct Plane { var buffer: [UInt8]; var rowBytes: Int; var height: Int }

    /// Decompress one WOBA plane into `rowBytes * height` bytes (1bpp, MSB
    /// first), the bounding rect's left/right widened to 32-bit boundaries.
    static func decode(_ a: [UInt8], top: Int, left: Int, bottom: Int, right: Int) -> Plane {
        let alignedLeft = left & ~31, alignedRight = (right + 31) & ~31
        let rowBytes = max(0, alignedRight - alignedLeft) / 8
        let height = max(0, bottom - top)
        var buf = [UInt8](repeating: 0, count: rowBytes * height)
        guard rowBytes > 0, height > 0 else { return Plane(buffer: buf, rowBytes: rowBytes, height: height) }

        var i = 0, y = 0
        var patterns = [UInt8](repeating: 0, count: 8)
        var dx = 0, dy = 0
        var rowBuf = [UInt8](repeating: 0, count: rowBytes)
        var x = 0

        // Store a finished full row (0x80-0x87 opcodes: no delta transform).
        func storeAt(_ row: [UInt8]) {
            guard y < height else { return }
            for k in 0..<rowBytes { buf[y * rowBytes + k] = row[k] }
            y += 1
        }
        // Finish a row built from multiple ops: apply the dh/dv delta transform.
        func finishMulti() {
            var r = rowBuf
            if dx > 0 {
                var bits = [Bool](repeating: false, count: rowBytes * 8)
                for k in 0..<rowBytes { for b in 0..<8 { bits[k * 8 + b] = (r[k] >> (7 - b)) & 1 == 1 } }
                for p in dx..<bits.count where bits[p - dx] { bits[p].toggle() } // prefix-XOR, step dx
                for k in 0..<rowBytes { var v: UInt8 = 0; for b in 0..<8 where bits[k * 8 + b] { v |= UInt8(1 << (7 - b)) }; r[k] = v }
            }
            if dy > 0, y - dy >= 0 { for k in 0..<rowBytes { r[k] ^= buf[(y - dy) * rowBytes + k] } }
            storeAt(r)
            rowBuf = [UInt8](repeating: 0, count: rowBytes); x = 0
        }
        func push(_ b: UInt8) {
            if x < rowBytes { rowBuf[x] = b; x += 1 }
            if x >= rowBytes { finishMulti() }
        }

        while y < height, i < a.count {
            var repeatN = 1
            var op = a[i]; i += 1
            if op & 0xE0 == 0xA0 { repeatN = Int(op & 0x1F); if i >= a.count { break }; op = a[i]; i += 1 }
            for _ in 0..<max(1, repeatN) {
                switch op {
                case 0x00...0x7F:
                    let nd = Int(op >> 4), nz = Int(op & 0x0F)
                    for _ in 0..<nz { push(0) }
                    for _ in 0..<nd { push(i < a.count ? a[i] : 0); i += 1 }
                case 0x80:
                    for _ in 0..<rowBytes { push(i < a.count ? a[i] : 0); i += 1 }
                case 0x81: storeAt([UInt8](repeating: 0, count: rowBytes))
                case 0x82: storeAt([UInt8](repeating: 0xFF, count: rowBytes))
                case 0x83:
                    let p = i < a.count ? a[i] : 0; i += 1
                    patterns[y & 7] = p
                    storeAt([UInt8](repeating: p, count: rowBytes))
                case 0x84: storeAt([UInt8](repeating: patterns[y & 7], count: rowBytes))
                case 0x85, 0x86, 0x87:
                    let back = Int(op - 0x84)
                    if y - back >= 0 { storeAt(Array(buf[(y - back) * rowBytes..<(y - back + 1) * rowBytes])) }
                case 0x88: dx = 16; dy = 0
                case 0x89: dx = 0; dy = 0
                case 0x8A: dx = 0; dy = 1
                case 0x8B: dx = 0; dy = 2
                case 0x8C: dx = 1; dy = 0
                case 0x8D: dx = 1; dy = 1
                case 0x8E: dx = 2; dy = 2
                case 0x8F: dx = 8; dy = 0
                case 0xC0...0xDF:
                    let count = Int(op & 0x1F) * 8
                    for _ in 0..<count { push(i < a.count ? a[i] : 0); i += 1 }
                case 0xE0...0xFF:
                    let count = Int(op & 0x1F) * 16
                    for _ in 0..<count { push(0) }
                default: break // 0x90-0x9F unused
                }
                if y >= height { break }
            }
        }
        return Plane(buffer: buf, rowBytes: rowBytes, height: height)
    }

    /// Composite a decoded plane into a card-sized RGBA PNG: black+opaque
    /// where a bit is set, transparent elsewhere, at the given offset.
    private static func renderPNG(plane: Plane, offsetX: Int, offsetY: Int, cardWidth: Int, cardHeight: Int) -> Data? {
        guard cardWidth > 0, cardHeight > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: cardWidth * cardHeight * 4) // RGBA, all transparent
        let planeWidth = plane.rowBytes * 8
        for yy in 0..<plane.height {
            let cardY = offsetY + yy
            guard cardY >= 0, cardY < cardHeight else { continue }
            for xx in 0..<planeWidth {
                let bit = (plane.buffer[yy * plane.rowBytes + xx / 8] >> (7 - (xx & 7))) & 1
                guard bit == 1 else { continue }
                let cardX = offsetX + xx
                guard cardX >= 0, cardX < cardWidth else { continue }
                let p = (cardY * cardWidth + cardX) * 4
                pixels[p] = 0; pixels[p+1] = 0; pixels[p+2] = 0; pixels[p+3] = 255
            }
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: &pixels, width: cardWidth, height: cardHeight,
                                      bitsPerComponent: 8, bytesPerRow: cardWidth * 4,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cgImage = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
