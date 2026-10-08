//
//  PaintRasterizer.swift
//  Contrapt
//
//  Scripted painting's drawing engine: `choose line tool` + `drag from … to …`
//  rasterizes onto a card's paint PNG. Works at the pixel level (RGBA, same
//  conventions as the WOBA importer: black/white pixels are opaque, everything
//  else transparent) so strokes get the crisp 1-bit HyperCard look rather than
//  antialiased CG paths, and the eraser can restore true transparency.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

nonisolated enum PaintRasterizer {
    /// What a stroke lays down. Pattern 1 is white; the other classic patterns
    /// approximate to black (dithered patterns aren't modeled). The eraser
    /// writes transparency, exposing the layer beneath.
    enum Ink {
        case black, white, erase

        init(pattern: Int) {
            self = pattern == 1 ? .white : .black
        }
    }

    struct Canvas {
        var pixels: [UInt8] // RGBA rows, top-down
        let width: Int
        let height: Int

        subscript(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            let p = (y * width + x) * 4
            return (pixels[p], pixels[p + 1], pixels[p + 2], pixels[p + 3])
        }
    }

    // MARK: - PNG round trip

    /// Decodes existing paint into an RGBA canvas of the card's size, or a
    /// fully transparent canvas when the card has no paint yet.
    static func canvas(from png: Data?, width: Int, height: Int) -> Canvas {
        var canvas = Canvas(pixels: [UInt8](repeating: 0, count: width * height * 4), width: width, height: height)
        guard let png,
              let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return canvas }
        canvas.pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: height - image.height, width: image.width, height: image.height))
        }
        return canvas
    }

    static func png(from canvas: Canvas) -> Data? {
        var pixels = canvas.pixels
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: &pixels, width: canvas.width, height: canvas.height,
                                      bitsPerComponent: 8, bytesPerRow: canvas.width * 4,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    // MARK: - Pens

    private static func put(_ canvas: inout Canvas, _ x: Int, _ y: Int, _ ink: Ink) {
        guard x >= 0, x < canvas.width, y >= 0, y < canvas.height else { return }
        let p = (y * canvas.width + x) * 4
        switch ink {
        case .black:
            canvas.pixels[p] = 0; canvas.pixels[p+1] = 0; canvas.pixels[p+2] = 0; canvas.pixels[p+3] = 255
        case .white:
            canvas.pixels[p] = 255; canvas.pixels[p+1] = 255; canvas.pixels[p+2] = 255; canvas.pixels[p+3] = 255
        case .erase:
            canvas.pixels[p] = 0; canvas.pixels[p+1] = 0; canvas.pixels[p+2] = 0; canvas.pixels[p+3] = 0
        }
    }

    /// A square pen of `size` pixels, anchored top-left at the point like
    /// HyperCard's line pen.
    private static func stamp(_ canvas: inout Canvas, x: Int, y: Int, size: Int, ink: Ink) {
        for dy in 0..<max(1, size) {
            for dx in 0..<max(1, size) {
                put(&canvas, x + dx, y + dy, ink)
            }
        }
    }

    // MARK: - Primitives

    /// Bresenham line with the square pen — the line/pencil/eraser stroke.
    static func line(_ canvas: inout Canvas, from: (x: Int, y: Int), to: (x: Int, y: Int), size: Int, ink: Ink) {
        var x = from.x, y = from.y
        let dx = abs(to.x - from.x), dy = -abs(to.y - from.y)
        let sx = from.x < to.x ? 1 : -1, sy = from.y < to.y ? 1 : -1
        var err = dx + dy
        while true {
            stamp(&canvas, x: x, y: y, size: size, ink: ink)
            if x == to.x, y == to.y { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x += sx }
            if e2 <= dx { err += dx; y += sy }
        }
    }

    /// The drag rectangle: corner-to-corner, or centered on the start point
    /// when `centered` (HyperCard's Draw Centered).
    static func dragBounds(from: (x: Int, y: Int), to: (x: Int, y: Int), centered: Bool) -> (x0: Int, y0: Int, x1: Int, y1: Int) {
        if centered {
            let rx = abs(to.x - from.x), ry = abs(to.y - from.y)
            return (from.x - rx, from.y - ry, from.x + rx, from.y + ry)
        }
        return (min(from.x, to.x), min(from.y, to.y), max(from.x, to.x), max(from.y, to.y))
    }

    static func rect(_ canvas: inout Canvas, bounds: (x0: Int, y0: Int, x1: Int, y1: Int), size: Int, ink: Ink, filled: Bool) {
        let (x0, y0, x1, y1) = bounds
        if filled {
            for y in y0...max(y0, y1) { for x in x0...max(x0, x1) { put(&canvas, x, y, ink) } }
            return
        }
        for y in y0...max(y0, y1) {
            for x in x0...max(x0, x1) {
                let edge = x - x0 < size || x1 - x < size || y - y0 < size || y1 - y < size
                if edge { put(&canvas, x, y, ink) }
            }
        }
    }

    /// Oval (and round rect via `cornerRadius`): membership tests against the
    /// outer shape and, for outlines, a `size`-inset inner shape.
    static func oval(_ canvas: inout Canvas, bounds: (x0: Int, y0: Int, x1: Int, y1: Int), size: Int, ink: Ink, filled: Bool) {
        let (x0, y0, x1, y1) = bounds
        let a = Double(max(1, x1 - x0)) / 2, b = Double(max(1, y1 - y0)) / 2
        let cx = Double(x0) + a, cy = Double(y0) + b
        let ia = max(0.5, a - Double(size)), ib = max(0.5, b - Double(size))
        for y in y0...max(y0, y1) {
            for x in x0...max(x0, x1) {
                let nx = (Double(x) + 0.5 - cx), ny = (Double(y) + 0.5 - cy)
                let outer = (nx * nx) / (a * a) + (ny * ny) / (b * b) <= 1
                guard outer else { continue }
                if filled { put(&canvas, x, y, ink); continue }
                let inner = (nx * nx) / (ia * ia) + (ny * ny) / (ib * ib) <= 1
                if !inner { put(&canvas, x, y, ink) }
            }
        }
    }

    static func roundRect(_ canvas: inout Canvas, bounds: (x0: Int, y0: Int, x1: Int, y1: Int), size: Int, ink: Ink, filled: Bool, cornerRadius: Int = 16) {
        let (x0, y0, x1, y1) = bounds
        let r = Double(min(cornerRadius, (x1 - x0) / 2, (y1 - y0) / 2))
        func inside(_ x: Int, _ y: Int, inset: Double) -> Bool {
            let fx = Double(x) + 0.5, fy = Double(y) + 0.5
            let lx = Double(x0) + inset, rx = Double(x1) + 1 - inset
            let ty = Double(y0) + inset, by = Double(y1) + 1 - inset
            guard fx >= lx, fx < rx, fy >= ty, fy < by else { return false }
            let cr = max(0, r - inset)
            let ccx = min(max(fx, lx + cr), rx - cr)
            let ccy = min(max(fy, ty + cr), by - cr)
            let dx = fx - ccx, dy = fy - ccy
            return dx * dx + dy * dy <= cr * cr || (fx >= lx + cr && fx < rx - cr) || (fy >= ty + cr && fy < by - cr)
        }
        for y in y0...max(y0, y1) {
            for x in x0...max(x0, x1) {
                guard inside(x, y, inset: 0) else { continue }
                if filled { put(&canvas, x, y, ink); continue }
                if !inside(x, y, inset: Double(size)) { put(&canvas, x, y, ink) }
            }
        }
    }

    /// Bucket fill: flood the contiguous region of the clicked pixel's class
    /// (black vs not-black; white and transparent read as one "paper" class,
    /// as in a 1-bit world).
    static func floodFill(_ canvas: inout Canvas, at start: (x: Int, y: Int), ink: Ink) {
        guard start.x >= 0, start.x < canvas.width, start.y >= 0, start.y < canvas.height else { return }
        func isBlack(_ x: Int, _ y: Int) -> Bool {
            let px = canvas[x, y]
            return px.a == 255 && px.r == 0 && px.g == 0 && px.b == 0
        }
        let targetBlack = isBlack(start.x, start.y)
        // The ink would repaint the same class — nothing to do (guards runaway
        // no-op fills; a black fill into black, or white/erase into paper).
        if targetBlack == (ink == .black) { return }
        var stack = [start]
        var visited = Set<Int>()
        while let (x, y) = stack.popLast() {
            let key = y * canvas.width + x
            if visited.contains(key) { continue }
            visited.insert(key)
            guard x >= 0, x < canvas.width, y >= 0, y < canvas.height, isBlack(x, y) == targetBlack else { continue }
            put(&canvas, x, y, ink)
            stack.append((x + 1, y)); stack.append((x - 1, y))
            stack.append((x, y + 1)); stack.append((x, y - 1))
        }
    }
}
