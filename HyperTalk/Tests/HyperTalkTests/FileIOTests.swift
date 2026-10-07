//
//  FileIOTests.swift
//  `open file` / `read from file` / `write to file` / `close file`.
//  Failures report via `the result` (HyperCard never aborts the handler);
//  `read` fills `it` and sets the result to "eof" at end of file.
//

import Testing
@testable import HyperTalk

@Test func writeThenReadRoundTrips() async throws {
    let host = try await run("""
    on p
      open file "scores"
      write "alice,10" & return & "bob,7" & return to file "scores"
      close file "scores"
      open file "scores"
      read from file "scores" until return
      put it into firstLine
      read from file "scores" until return
      put firstLine & item 2 of it
      close file "scores"
    end p
    """, handler: "p")
    #expect(host.messages.last == "alice,10\n7\n")
}

@Test func readForCountAndEOFResult() async throws {
    let host = try await run("""
    on p
      open file "t"
      write "abcdef" to file "t"
      close file "t"
      open file "t"
      read from file "t" for 3
      put it into chunk1
      read from file "t" for 99
      put chunk1 & "|" & it & "|" & the result
      close file "t"
    end p
    """, handler: "p")
    #expect(host.messages.last == "abc|def|eof")
}

@Test func fileFailuresReportViaTheResult() async throws {
    // Reading a file that was never opened must not abort the handler.
    let host = try await run("""
    on p
      read from file "nope"
      put the result & "|" & it
    end p
    """, handler: "p")
    #expect(host.messages.last == "File not open.|")
}

@Test func writeAtEOFAppendsAndOpenPrintingNoOps() async throws {
    let host = try await run("""
    on p
      open printing with dialog
      open file "log"
      write "one" to file "log"
      write "+two" to file "log" at eof
      close file "log"
      open file "log"
      read from file "log" until return
      put it
      close file "log"
      close printing
    end p
    """, handler: "p")
    #expect(host.messages.last == "one+two")
}

@Test func writeAtMarkOverwritesInPlace() async throws {
    let host = try await run("""
    on p
      open file "t"
      write "abcdef" to file "t"
      close file "t"
      open file "t"
      write "XY" to file "t"
      close file "t"
      open file "t"
      read from file "t" for 99
      put it
      close file "t"
    end p
    """, handler: "p")
    #expect(host.messages.last == "XYcdef")
}
