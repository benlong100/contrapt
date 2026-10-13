//
//  PageReaderTests.swift
//  HyperTalk
//
//  `the title of url "…"`, `the text of url "…"`, `the links of url "…"` —
//  web-page readers (Contrapt web gathering). The HTMLPage extraction core
//  is tested pure; the language forms run against MockHost's canned
//  responses so they stay fast and offline.
//

import Testing
@testable import HyperTalk

// MARK: - HTMLPage core

@Test func htmlTitleIsExtractedAndDecoded() {
    let html = "<html><head><title id=\"t\">  Tom &amp; Jerry&rsquo;s\n Page </title></head><body></body></html>"
    #expect(HTMLPage.title(of: html) == "Tom & Jerry\u{2019}s Page")
}

@Test func htmlTitleMissingReadsEmpty() {
    #expect(HTMLPage.title(of: "<html><body>no title</body></html>") == "")
}

@Test func htmlTextStripsMachineryAndKeepsParagraphs() {
    let html = """
    <html><head><title>T</title><style>p { color: red }</style></head>
    <body><script>alert("hi")</script><!-- hidden -->
    <h1>Heading</h1>
    <p>First   paragraph&nbsp;here.</p>
    <ul><li>One</li><li>Two &lt;3</li></ul>
    </body></html>
    """
    let text = HTMLPage.text(of: html)
    #expect(text.contains("Heading"))
    #expect(text.contains("First paragraph here."))
    #expect(text.contains("Two <3"))
    #expect(!text.contains("alert"))
    #expect(!text.contains("color: red"))
    #expect(!text.contains("hidden"))
    // Block elements separate lines: heading and paragraph aren't joined.
    #expect(text.components(separatedBy: "\n").contains("Heading"))
}

@Test func htmlTextDecodesNumericEntities() {
    #expect(HTMLPage.text(of: "<p>caf&#233; &#x2606;</p>") == "café ☆")
}

@Test func htmlLinksResolveAndFilter() {
    let html = """
    <a href="/stacks/index.html">Stacks</a>
    <a href='news.html'>News</a>
    <a href=bare.html>Bare</a>
    <a href="#top">Skip</a>
    <a href="javascript:void(0)">Skip</a>
    <a href="mailto:x@y.z">Skip</a>
    <a href="https://other.example/page">Other</a>
    <a href="/stacks/index.html">Duplicate</a>
    """
    let links = HTMLPage.links(of: html, base: "https://example.com/home/start.html")
    #expect(links == [
        "https://example.com/stacks/index.html",
        "https://example.com/home/news.html",
        "https://example.com/home/bare.html",
        "https://other.example/page",
    ])
}

// MARK: - Language forms

@Test func titleOfURLFetchesAndReads() async throws {
    let host = MockHost()
    host.httpResponses["GET https://example.com/"] = ("<title>Home of the Stack</title>", 200, [:], nil)
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put the title of url "https://example.com/" into msg
    end p
    """, host: host)
    #expect(host.messages.last == "Home of the Stack")
    #expect(host.httpRequests.last?.method == "GET")
    #expect(host.httpRequests.last?.url == "https://example.com/")
}

@Test func textOfURLReadsBodyText() async throws {
    let host = MockHost()
    host.httpResponses["GET https://example.com/a"] = ("<body><p>Hello &amp; welcome</p></body>", 200, [:], nil)
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put the text of url "https://example.com/a" into msg
    end p
    """, host: host)
    #expect(host.messages.last == "Hello & welcome")
}

@Test func linksOfURLResolveAgainstTheFetchedAddress() async throws {
    let host = MockHost()
    host.httpResponses["GET https://example.com/dir/page.html"] =
        ("<a href=\"one.html\">1</a> <a href=\"/two.html\">2</a>", 200, [:], nil)
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put line 2 of the links of url "https://example.com/dir/page.html" into msg
    end p
    """, host: host)
    #expect(host.messages.last == "https://example.com/two.html")
}

@Test func pageReaderErrorGoesToResult() async throws {
    let host = MockHost()
    host.httpResponses["GET https://nope.example/"] = ("", 0, [:], "Can't reach the server.")
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put the title of url "https://nope.example/" into it
      put the result into msg
    end p
    """, host: host)
    #expect(host.messages.last == "Can't reach the server.")
}

@Test func titleOfButtonStaysAnObjectProperty() throws {
    // The page readers key on `of url`; `the title of btn 1` must still
    // parse as a part property, not a page read.
    try HyperTalk.check("""
    on p
      get the title of button 1
    end p
    """)
}
