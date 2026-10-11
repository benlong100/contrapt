//
//  PICTBitmap.swift
//  HyperTalk
//
//  A focused classic QuickDraw PICT (v2) decoder — enough of the opcode stream
//  to reach and render the bitmap ops HyperCard AddColor backgrounds use:
//  PackBitsRect (0x98, indexed/paletted) and DirectBitsRect (0x9A, direct RGB).
//  Modern macOS no longer draws these via NSPICTImageRep, so Contrapt decodes
//  them itself. Pure (bytes → RGBA8), so it's unit-tested here and the native
//  app just wraps the result in a CGImage. Vector / v1 PICTs return nil (the
//  app falls back to the system renderer).
//

import Foundation

public enum PICTBitmap {
    /// Decodes a PICT resource's bytes into an RGBA8 buffer the size of the
    /// picture frame. Returns nil when there's no bitmap op it understands.
    public static func decode(_ data: [UInt8]) -> (width: Int, height: Int, rgba: [UInt8])? {
        var r = Reader(data)
        guard r.remaining > 10 else { return nil }
        _ = r.u16()                       // picSize (unreliable)
        let frame = r.rect()
        let w = max(1, frame.width), h = max(1, frame.height)
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        var drew = false

        func put(_ x: Int, _ y: Int, _ cr: UInt8, _ cg: UInt8, _ cb: UInt8) {
            guard x >= 0, x < w, y >= 0, y < h else { return }
            let i = (y * w + x) * 4
            rgba[i] = cr; rgba[i+1] = cg; rgba[i+2] = cb; rgba[i+3] = 255
        }

        func blit(direct: Bool, hasColorTable: Bool) {
            let rowBytes = r.u16() & 0x7FFF
            let bounds = r.rect()
            _ = r.u16()                   // pmVersion
            let packType = r.u16()
            _ = r.u32()                   // packSize
            _ = r.u32(); _ = r.u32()      // hRes, vRes
            _ = r.u16()                   // pixelType
            let pixelSize = r.u16()
            let cmpCount = r.u16()
            _ = r.u16()                   // cmpSize
            _ = r.u32()                   // planeBytes
            _ = r.u32()                   // pmTable
            _ = r.u32()                   // pmReserved

            var palette: [(UInt8, UInt8, UInt8)] = []
            if hasColorTable {
                _ = r.u32()               // ctSeed
                _ = r.u16()               // ctFlags
                let ctSize = r.u16()      // count - 1
                if ctSize >= 0 {
                    for _ in 0...ctSize {
                        _ = r.u16()       // index/value
                        let rr = r.u16(), gg = r.u16(), bb = r.u16()
                        palette.append((UInt8(rr >> 8), UInt8(gg >> 8), UInt8(bb >> 8)))
                    }
                }
            }

            _ = r.rect()                  // srcRect
            let dst = r.rect()
            _ = r.u16()                   // mode

            let dx = dst.left - frame.left, dy = dst.top - frame.top
            for y in 0..<bounds.height {
                let row: [UInt8]
                if rowBytes < 8 || packType == 1 {
                    row = r.take(rowBytes)
                } else {
                    let count = rowBytes > 250 ? r.u16() : r.u8()
                    var rr = Reader(r.take(count))
                    row = Reader.unpackBits(&rr, outCount: rowBytes)
                }
                let px = min(dst.width, bounds.width)
                if direct {
                    for x in 0..<px {
                        let rp: Int, gp: Int, bp: Int
                        if cmpCount == 3 { rp = x; gp = bounds.width + x; bp = 2*bounds.width + x }
                        else { rp = bounds.width + x; gp = 2*bounds.width + x; bp = 3*bounds.width + x }
                        if bp < row.count { put(dx + x, dy + y, row[rp], row[gp], row[bp]) }
                    }
                } else {
                    for x in 0..<px {
                        let index: Int
                        switch pixelSize {
                        case 8: index = x < row.count ? Int(row[x]) : 0
                        case 4: index = (x/2) < row.count ? Int((row[x/2] >> (x%2 == 0 ? 4 : 0)) & 0xF) : 0
                        case 2: index = (x/4) < row.count ? Int((row[x/4] >> (6 - 2*(x%4))) & 0x3) : 0
                        case 1: index = (x/8) < row.count ? Int((row[x/8] >> (7 - (x%8))) & 0x1) : 0
                        default: index = 0
                        }
                        if index < palette.count {
                            let c = palette[index]; put(dx + x, dy + y, c.0, c.1, c.2)
                        } else if pixelSize == 1 {
                            let v: UInt8 = index == 0 ? 255 : 0; put(dx + x, dy + y, v, v, v)
                        }
                    }
                }
            }
            drew = true
        }

        var steps = 0
        while r.remaining >= 2 {
            steps += 1; if steps > 200_000 { break }
            r.align()
            guard r.remaining >= 2 else { break }
            switch r.u16() {
            case 0x0000: break                                   // NOP
            case 0x0011: r.skip(2)                               // versionOp
            case 0x001E: break                                   // defHilite
            case 0x0001: let n = r.u16(); r.skip(max(0, n - 2))  // clipRgn
            case 0x0003, 0x0004, 0x0005, 0x0008, 0x000D,
                 0x0015, 0x0016, 0x0018, 0x0019, 0x001A,
                 0x001B, 0x001C, 0x001D: r.skip(2)               // assorted short state ops
            case 0x00A0: r.skip(2)                               // shortComment
            case 0x00A1: _ = r.u16(); r.skip(r.u16())            // longComment
            case 0x0C00: r.skip(24)                              // headerOp
            case 0x0098, 0x0099: blit(direct: false, hasColorTable: true)
            case 0x009A, 0x009B: _ = r.u32(); blit(direct: true, hasColorTable: false)
            default: r.end()                                     // opEndPic / unknown — stop
            }
        }
        return drew ? (w, h, rgba) : nil
    }
}

private struct Reader {
    let b: [UInt8]
    var p = 0
    init(_ data: [UInt8]) { b = data }
    var remaining: Int { b.count - p }
    mutating func u8() -> Int { guard p < b.count else { return 0 }; let v = Int(b[p]); p += 1; return v }
    mutating func u16() -> Int { (u8() << 8) | u8() }
    mutating func s16() -> Int { let v = u16(); return v >= 0x8000 ? v - 0x10000 : v }
    mutating func u32() -> Int { (u16() << 16) | u16() }
    mutating func skip(_ n: Int) { p += n }
    mutating func end() { p = b.count }
    mutating func align() { if p % 2 == 1 { p += 1 } }
    mutating func take(_ n: Int) -> [UInt8] {
        let hi = min(max(p, 0) + max(n, 0), b.count)
        let lo = min(max(p, 0), b.count)
        let out = Array(b[lo..<hi]); p += n; return out
    }
    mutating func rect() -> PRect { PRect(top: s16(), left: s16(), bottom: s16(), right: s16()) }

    static func unpackBits(_ r: inout Reader, outCount: Int) -> [UInt8] {
        var out = [UInt8](); out.reserveCapacity(outCount)
        while out.count < outCount && r.remaining > 0 {
            let flag = r.u8()
            if flag < 128 {
                for _ in 0...(flag) where r.remaining > 0 { out.append(UInt8(r.u8())) }
            } else if flag > 128 {
                let n = 257 - flag
                let v = UInt8(r.u8())
                for _ in 0..<n { out.append(v) }
            }
        }
        return out
    }
}

private struct PRect {
    var top = 0, left = 0, bottom = 0, right = 0
    var width: Int { right - left }
    var height: Int { bottom - top }
}
