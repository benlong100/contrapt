//
//  CorpusAuditTests.swift
//  HyperTalk
//
//  Tool #1 from the compatibility strategy: a batch parse-compile pass over the
//  on-disk classic-stack corpus. Extracts every handler-looking script from
//  each stack (stack + background + card + button/field scripts all live as
//  NUL-terminated Mac-Roman runs inside the STAK blocks), parses each with the
//  real HyperTalk `Parser`, and writes a ranked report of the parse errors —
//  the gaps that block real stacks, aggregated instead of found one at a time.
//
//  Opt-in (it reads files and is slow), so it's inert in normal `swift test`:
//      CONTRAPT_AUDIT=1 swift test --filter corpusParseAudit
//  Override the corpus root / report path with CONTRAPT_CORPUS / CONTRAPT_AUDIT_OUT.
//
//  Script EXTRACTION here is a faithful-enough port of LegacyStackImporter.Reader
//  (block walk + text runs + looksLikeScript + trimToCompleteHandlers); it finds
//  the same handler text the importer feeds the parser. It does NOT reproduce the
//  importer's per-part object labelling — scripts are attributed to their block
//  (STAK / BKGD id / CARD id), which is enough to drive fixes. Line numbers are
//  the parser's (see the known editor-mismatch note in the backlog).
//

import Foundation
import Testing
@testable import HyperTalk

// MARK: - Minimal STAK reader (ported from LegacyStackImporter.Reader)

private struct StakReader {
    let d: [UInt8]
    init?(_ data: Data) {
        d = [UInt8](data)
        // A classic stack's first block is the STAK block.
        guard d.count >= 8, tag(at: 0) == "STAK" else { return nil }
    }
    func u32(_ o: Int) -> Int { o + 4 <= d.count ? Int(UInt32(d[o]) << 24 | UInt32(d[o+1]) << 16 | UInt32(d[o+2]) << 8 | UInt32(d[o+3])) : 0 }
    func i32(_ o: Int) -> Int { Int(Int32(bitPattern: UInt32(u32(o)))) }
    func tag(at o: Int) -> String { o + 8 <= d.count ? (String(bytes: d[(o+4)..<(o+8)], encoding: .ascii) ?? "") : "" }

    struct Block { let type: String; let offset: Int; let size: Int; let id: Int }
    func walkBlocks() -> [Block] {
        var blocks: [Block] = []
        var o = 0
        while o + 12 <= d.count {
            let size = u32(o)
            if size < 12 || o + size > d.count { break }
            blocks.append(Block(type: tag(at: o), offset: o, size: size, id: i32(o + 8)))
            o += size
        }
        return blocks
    }

    private func roman(_ bytes: [UInt8]) -> String {
        (String(bytes: bytes, encoding: .macOSRoman) ?? String(decoding: bytes, as: UTF8.self))
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// Cleaned Mac-Roman runs (text + CR) between NUL/control separators.
    private func textRuns(from start: Int, end: Int) -> [String] {
        var runs: [String] = []
        var bytes: [UInt8] = []
        func flush() { if let r = clean(bytes) { runs.append(r) }; bytes.removeAll(keepingCapacity: true) }
        var i = max(start, 0)
        while i < min(end, d.count) {
            let b = d[i]
            if b == 0 { flush() }
            else if b == 0x0D || b >= 0x20 { bytes.append(b) }
            else { flush() }
            i += 1
        }
        flush()
        return runs
    }

    private func clean(_ raw: [UInt8]) -> String? {
        var bytes = raw
        var lead = 0
        while lead < bytes.count, lead < 8, bytes[lead] >= 0x80 || (bytes[lead] < 0x20 && bytes[lead] != 0x0D) { lead += 1 }
        bytes.removeFirst(lead)
        guard bytes.count >= 2 else { return nil }
        let highBytes = bytes.filter { $0 >= 0x80 || ($0 < 0x20 && $0 != 0x0D) }.count
        if highBytes * 3 > bytes.count { return nil }
        let text = roman(bytes)
        for t in ["BMAP", "CARD", "BKGD", "PAGE", "LIST", "STAK", "TAIL", "FREE", "MAST"] where text.hasPrefix(t) { return nil }
        return text
    }

    private func looksLikeScript(_ run: String) -> Bool {
        let lower = run.lowercased()
        guard (lower.hasPrefix("on ") || lower.contains("\non ") || lower.hasPrefix("function ")) && lower.contains("end ") else {
            return false
        }
        // HyperCard 2.2 scripts can BE AppleScript (WOSA/`ascr` OSA blocks —
        // Annuaire NET's `on run aplic / tell application …`). Those aren't
        // HyperTalk; auditing them as parse errors is noise.
        if lower.contains("tell application ") && lower.contains("end tell") { return false }
        return true
    }

    private func trimToCompleteHandlers(_ script: String) -> String {
        let lines = script.components(separatedBy: "\n")
        func headWord(_ line: String, _ keyword: String) -> String? {
            let t = line.trimmingCharacters(in: .whitespaces).lowercased()
            guard t == keyword || t.hasPrefix(keyword + " ") else { return nil }
            return t.dropFirst(keyword.count).drop(while: { $0 == " " }).split(separator: " ").first.map(String.init)
        }
        var open: String?
        var lastCompleteEnd: Int?
        for (i, line) in lines.enumerated() {
            if let name = headWord(line, "on") ?? headWord(line, "function") { open = name }
            else if let endName = headWord(line, "end"), let o = open, endName == o { lastCompleteEnd = i; open = nil }
        }
        guard let last = lastCompleteEnd else { return "" }
        return lines[0...last].joined(separator: "\n")
    }

    /// Every handler-looking script in the stack, labelled by its block.
    func scripts() -> [(label: String, source: String)] {
        var out: [(String, String)] = []
        for block in walkBlocks() where ["STAK", "BKGD", "CARD"].contains(block.type) {
            let label = block.type == "STAK" ? "STAK" : "\(block.type) id \(block.id)"
            for run in textRuns(from: block.offset, end: block.offset + block.size) where looksLikeScript(run) {
                let trimmed = trimToCompleteHandlers(run)
                if !trimmed.isEmpty { out.append((label, trimmed)) }
            }
        }
        return out
    }
}

// MARK: - The audit

private func classicStackFiles(under root: String) -> [String] {
    let fm = FileManager.default
    guard let en = fm.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.isRegularFileKey],
                                 options: [.skipsHiddenFiles]) else { return [] }
    var files: [String] = []
    for case let url as URL in en {
        let path = url.path
        if path.contains("/.build/") || path.contains("/.git/") { en.skipDescendants(); continue }
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
        // Cheap magic check: first block must be a STAK block.
        guard let fh = try? FileHandle(forReadingFrom: url) else { continue }
        let head = try? fh.read(upToCount: 8); try? fh.close()
        if let head, head.count == 8, String(bytes: head[4..<8], encoding: .ascii) == "STAK" {
            files.append(path)
        }
    }
    return files.sorted()
}

@Test func corpusParseAudit() async throws {
    guard ProcessInfo.processInfo.environment["CONTRAPT_AUDIT"] == "1" else { return }
    // Parsing is synchronous and deeply recursive — real scripts nest ~100 deep
    // (BMUG's AppointmentMaster has a 96-level if/else time dispatcher). Run it
    // on a large-stack thread so it can't overflow the test runner's small
    // cooperative-pool stack, as the app's main thread wouldn't.
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let thread = Thread { runCorpusParseAudit(); continuation.resume() }
        thread.stackSize = 64 * 1024 * 1024
        thread.start()
    }
}

private func runCorpusParseAudit() {
    let env = ProcessInfo.processInfo.environment
    let root = env["CONTRAPT_CORPUS"] ?? "/Users/wanderer/Desktop/Homemade Apps/HyperPad"
    let outPath = env["CONTRAPT_AUDIT_OUT"] ?? (root + "/corpus-audit.txt")

    let files = classicStackFiles(under: root)

    // Optional triage aid: CONTRAPT_DUMP=<substring> prints the full source of
    // each failing script whose error message contains the substring.
    let dumpNeedle = env["CONTRAPT_DUMP"]
    struct Finding { let stack: String; let label: String; let line: Int; let message: String }
    var findings: [Finding] = []
    var stacksScanned = 0, scriptsParsed = 0, scriptsOK = 0

    for file in files {
        guard let data = FileManager.default.contents(atPath: file), let reader = StakReader(data) else { continue }
        stacksScanned += 1
        let stackName = (file as NSString).lastPathComponent
        // Dedupe identical scripts within a stack: the simplified extractor can
        // capture the same handler text more than once per block (part record +
        // stale bytes), and a shared handler recurs verbatim — collapse so one
        // gap counts once, not N times.
        var seenInStack = Set<String>()
        for (label, source) in reader.scripts() {
            guard seenInStack.insert(source).inserted else { continue }
            scriptsParsed += 1
            do { _ = try Parser.parse(source); scriptsOK += 1 }
            catch let e as ScriptError {
                findings.append(Finding(stack: stackName, label: label, line: e.line, message: e.message))
                if let dumpNeedle, e.message.contains(dumpNeedle) {
                    let lines = source.components(separatedBy: "\n")
                    let lo = max(0, e.line - 3), hi = min(lines.count, e.line + 2)
                    var ctx = ""
                    for n in lo..<hi { ctx += "  \(n + 1): \(lines[n])\n" }
                    print("----- \(stackName) › \(label) › line \(e.line): \(e.message)\n\(ctx)-----")
                }
            } catch {
                findings.append(Finding(stack: stackName, label: label, line: 0, message: "\(error)"))
            }
        }
    }

    // Rank by exact message (each distinct unknown command/property is its own
    // line, which surfaces the most common specific gaps first).
    var byMessage: [String: [Finding]] = [:]
    for f in findings { byMessage[f.message, default: []].append(f) }
    let ranked = byMessage.sorted { $0.value.count > $1.value.count }

    var report = ""
    func line(_ s: String) { report += s + "\n" }
    line("Contrapt corpus parse audit")
    line("root: \(root)")
    line("stacks scanned: \(stacksScanned)   scripts parsed: \(scriptsParsed)   clean: \(scriptsOK)   with errors: \(findings.count)")
    line("")
    line("=== parse-error gaps, most frequent first ===")
    for (message, group) in ranked {
        line("")
        line("[\(group.count)]  \(message)")
        for f in group.prefix(5) {
            line("      \(f.stack) › \(f.label) › line \(f.line)")
        }
        if group.count > 5 { line("      … and \(group.count - 5) more") }
    }
    line("")
    line("=== stacks with no parse errors ===")
    let failedStacks = Set(findings.map(\.stack))
    let allStacks = Set(files.map { ($0 as NSString).lastPathComponent })
    for s in allStacks.subtracting(failedStacks).sorted() { line("  \(s)") }

    try? report.write(toFile: outPath, atomically: true, encoding: .utf8)
    print("CORPUS-AUDIT: \(stacksScanned) stacks, \(scriptsParsed) scripts, \(findings.count) with parse errors (\(ranked.count) distinct messages). Report: \(outPath)")
}

