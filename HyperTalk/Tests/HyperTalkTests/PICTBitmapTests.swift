//
//  PICTBitmapTests.swift
//  HyperTalk
//
//  The QuickDraw PICT v2 decoder (PackBitsRect). A hand-built 2×2 indexed PICT
//  exercises the whole path — opcode stream, PixMap, color table, uncompressed
//  rows (rowBytes < 8) — and asserts the exact pixels. (Real stack PICTs are
//  verified separately via CLI probes; this is the durable regression test.)
//

import Testing
@testable import HyperTalk

private struct Builder {
    var bytes: [UInt8] = []
    mutating func u8(_ v: Int) { bytes.append(UInt8(v & 0xFF)) }
    mutating func u16(_ v: Int) { u8(v >> 8); u8(v) }
    mutating func u32(_ v: Int) { u16(v >> 16); u16(v) }
    mutating func zeros(_ n: Int) { bytes.append(contentsOf: [UInt8](repeating: 0, count: n)) }
}

private func twoByTwoPICT() -> [UInt8] {
    var b = Builder()
    b.u16(0)                 // picSize
    b.u16(0); b.u16(0); b.u16(2); b.u16(2)   // frame 0,0,2,2
    b.u16(0x0011); b.u16(0x02FF)             // versionOp v2
    b.u16(0x0C00); b.zeros(24)               // headerOp
    b.u16(0x0098)            // PackBitsRect
    b.u16(0x8002)            // rowBytes (PixMap bit + 2)
    b.u16(0); b.u16(0); b.u16(2); b.u16(2)   // bounds 0,0,2,2
    b.u16(0)                 // pmVersion
    b.u16(0)                 // packType (0 = default; rowBytes<8 → uncompressed)
    b.u32(0)                 // packSize
    b.u32(0); b.u32(0)       // hRes, vRes
    b.u16(0)                 // pixelType
    b.u16(8)                 // pixelSize
    b.u16(1)                 // cmpCount
    b.u16(8)                 // cmpSize
    b.u32(0); b.u32(0); b.u32(0)   // planeBytes, pmTable, pmReserved
    // color table: 2 entries (index 0 = red, 1 = green)
    b.u32(0); b.u16(0); b.u16(1)   // ctSeed, ctFlags, ctSize (count-1)
    b.u16(0); b.u16(0xFFFF); b.u16(0x0000); b.u16(0x0000)  // #0 red
    b.u16(1); b.u16(0x0000); b.u16(0xFFFF); b.u16(0x0000)  // #1 green
    b.u16(0); b.u16(0); b.u16(2); b.u16(2)   // srcRect
    b.u16(0); b.u16(0); b.u16(2); b.u16(2)   // dstRect
    b.u16(0)                 // mode
    b.u8(0); b.u8(1)         // row 0: red, green
    b.u8(1); b.u8(0)         // row 1: green, red
    b.u16(0x00FF)            // opEndPic
    return b.bytes
}

@Test func decodesTwoByTwoPackBitsRect() throws {
    let decoded = try #require(PICTBitmap.decode(twoByTwoPICT()))
    #expect(decoded.width == 2)
    #expect(decoded.height == 2)
    func pixel(_ x: Int, _ y: Int) -> [UInt8] {
        let i = (y * decoded.width + x) * 4
        return Array(decoded.rgba[i..<i+4])
    }
    let red: [UInt8] = [255, 0, 0, 255]
    let green: [UInt8] = [0, 255, 0, 255]
    #expect(pixel(0, 0) == red)
    #expect(pixel(1, 0) == green)
    #expect(pixel(0, 1) == green)
    #expect(pixel(1, 1) == red)
}

@Test func nonBitmapPICTReturnsNil() {
    // A header-only PICT (no bitmap op) has nothing to render.
    var b = Builder()
    b.u16(0); b.u16(0); b.u16(0); b.u16(10); b.u16(10)  // picSize + frame
    b.u16(0x0011); b.u16(0x02FF)
    b.u16(0x00FF)                                       // straight to opEndPic
    #expect(PICTBitmap.decode(b.bytes) == nil)
}
