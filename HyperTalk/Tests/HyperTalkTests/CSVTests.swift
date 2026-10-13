//
//  CSVTests.swift
//  HyperTalk
//
//  `CSVItems(url "…")` — comma-separated tables parsed into the array shape
//  `make a card for each element` fills fields from (header row → keys).
//

import Testing
@testable import HyperTalk

@Test func csvRowsBecomeKeyedElements() {
    let csv = """
    Title,Notes
    First,plain
    "Second, with comma","a ""quoted"" word"
    """
    let items = HyperTalkArray.decode(CSVTable.items(csv))!
    #expect(items.count == 2)
    #expect(HyperTalkArray.value(forKey: "Title", in: items[0].value) == "First")
    #expect(HyperTalkArray.value(forKey: "Notes", in: items[0].value) == "plain")
    #expect(HyperTalkArray.value(forKey: "Title", in: items[1].value) == "Second, with comma")
    #expect(HyperTalkArray.value(forKey: "Notes", in: items[1].value) == "a \"quoted\" word")
}

@Test func csvQuotedNewlinesAndCRLFSurvive() {
    let csv = "Title,Notes\r\nOne,\"line a\nline b\"\r\n"
    let items = HyperTalkArray.decode(CSVTable.items(csv))!
    #expect(items.count == 1)
    #expect(HyperTalkArray.value(forKey: "Notes", in: items[0].value) == "line a\nline b")
}

@Test func csvBlankAndDuplicateHeadersGetNames() {
    let csv = """
    Name,,Name
    a,b,c
    """
    let items = HyperTalkArray.decode(CSVTable.items(csv))!
    let row = items[0].value
    #expect(HyperTalkArray.value(forKey: "Name", in: row) == "a")
    #expect(HyperTalkArray.value(forKey: "column 2", in: row) == "b")
    #expect(HyperTalkArray.value(forKey: "Name 3", in: row) == "c")
}

@Test func csvShortRowsReadEmptyAndHeaderOnlyHasNoItems() {
    let short = HyperTalkArray.decode(CSVTable.items("A,B\nonly"))!
    #expect(HyperTalkArray.value(forKey: "B", in: short[0].value) == "")
    #expect(HyperTalkArray.count(of: CSVTable.items("A,B\n")) == 0)
    #expect(HyperTalkArray.count(of: CSVTable.items("")) == 0)
}

@Test func csvItemsOfURLReadsInTheLanguage() async throws {
    let host = MockHost()
    host.httpResponses["GET https://example.com/table.csv"] = ("Title,Notes\nHello,World\n", 200, [:], nil)
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put CSVItems(url "https://example.com/table.csv") into rows
      put the number of elements of rows & "," & rows[1]["Title"] & "," & rows[1]["Notes"] into msg
    end p
    """, host: host)
    #expect(host.messages.last == "1,Hello,World")
}
