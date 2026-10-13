//
//  FeedTests.swift
//  HyperTalk
//
//  `FeedItems(url "…")` — RSS 2.0 / Atom feeds parsed into the array shape
//  `make a card for each element` fills fields from (title/link/date/text).
//

import Testing
@testable import HyperTalk

private let rssXML = """
<?xml version="1.0"?>
<rss version="2.0"><channel>
  <title>The Channel</title>
  <item>
    <title>First &amp; Foremost</title>
    <link>https://example.com/one</link>
    <pubDate>Mon, 12 Oct 2026 09:00:00 GMT</pubDate>
    <description><![CDATA[<p>Hello <b>world</b> &mdash; a story.</p>]]></description>
  </item>
  <item>
    <title>Second</title>
    <link>https://example.com/two</link>
    <author>jane@example.com (Jane)</author>
    <category>News</category>
    <dc:creator>Jane</dc:creator>
    <guid isPermaLink="false">tag:example.com,2026:two</guid>
  </item>
</channel></rss>
"""

private let atomXML = """
<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>The Feed</title>
  <entry>
    <title>Atom Entry</title>
    <link rel="self" href="https://example.com/entry.xml"/>
    <link rel="alternate" href="https://example.com/entry"/>
    <updated>2026-10-12T09:00:00Z</updated>
    <summary>A &quot;quoted&quot; summary.</summary>
  </entry>
</feed>
"""

@Test func rssItemsParseWithAllFields() {
    let items = HyperTalkArray.decode(WebFeed.items(rssXML))!
    #expect(items.count == 2)
    let first = items[0].value
    #expect(HyperTalkArray.value(forKey: "title", in: first) == "First & Foremost")
    #expect(HyperTalkArray.value(forKey: "link", in: first) == "https://example.com/one")
    #expect(HyperTalkArray.value(forKey: "date", in: first) == "Mon, 12 Oct 2026 09:00:00 GMT")
    #expect(HyperTalkArray.value(forKey: "text", in: first) == "Hello world — a story.")
}

@Test func rssMissingPartsReadEmpty() {
    let items = HyperTalkArray.decode(WebFeed.items(rssXML))!
    let second = items[1].value
    #expect(HyperTalkArray.value(forKey: "title", in: second) == "Second")
    #expect(HyperTalkArray.value(forKey: "date", in: second) == "")
    #expect(HyperTalkArray.value(forKey: "text", in: second) == "")
}

@Test func atomEntriesPreferTheAlternateLink() {
    let items = HyperTalkArray.decode(WebFeed.items(atomXML))!
    #expect(items.count == 1)
    let entry = items[0].value
    #expect(HyperTalkArray.value(forKey: "title", in: entry) == "Atom Entry")
    #expect(HyperTalkArray.value(forKey: "link", in: entry) == "https://example.com/entry")
    #expect(HyperTalkArray.value(forKey: "date", in: entry) == "2026-10-12T09:00:00Z")
    #expect(HyperTalkArray.value(forKey: "text", in: entry) == "A \"quoted\" summary.")
}

@Test func extraFeedTagsComeThroughAsKeys() {
    // Beyond the normalized four, a feed's other simple tags survive —
    // keyed by local name (dc:creator → creator) — so `the keys of
    // items[1]` shows what a particular feed actually provides.
    let items = HyperTalkArray.decode(WebFeed.items(rssXML))!
    let second = items[1].value
    #expect(HyperTalkArray.value(forKey: "author", in: second) == "jane@example.com (Jane)")
    #expect(HyperTalkArray.value(forKey: "category", in: second) == "News")
    #expect(HyperTalkArray.value(forKey: "creator", in: second) == "Jane")
    #expect(HyperTalkArray.value(forKey: "guid", in: second) == "tag:example.com,2026:two")
    // The first item (no extras) still has exactly the four.
    #expect(HyperTalkArray.keys(of: items[0].value) == ["title", "link", "date", "text"])
}

@Test func keysOfAFeedItemReadInTheMessageBoxStyle() async throws {
    // The discovery one-liner: `the keys of FeedItems(url "…")[1]`.
    let host = MockHost()
    host.httpResponses["GET https://example.com/feed.xml"] = (rssXML, 200, [:], nil)
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put the keys of FeedItems(url "https://example.com/feed.xml")[2] into msg
    end p
    """, host: host)
    #expect(host.messages.last == "title\nlink\ndate\ntext\nauthor\ncategory\ncreator\nguid")
}

@Test func nonFeedInputYieldsNoItems() {
    #expect(HyperTalkArray.count(of: WebFeed.items("<html><body>not a feed</body></html>")) == 0)
    #expect(HyperTalkArray.count(of: WebFeed.items("")) == 0)
}

@Test func feedItemsOfURLReadsInTheLanguage() async throws {
    let host = MockHost()
    host.httpResponses["GET https://example.com/feed.xml"] = (rssXML, 200, [:], nil)
    _ = try await HyperTalk.run(handler: "p", in: """
    on p
      put FeedItems(url "https://example.com/feed.xml") into stories
      put the number of elements of stories & "," & stories[1]["title"] & "," & stories[2]["link"] into msg
    end p
    """, host: host)
    #expect(host.messages.last == "2,First & Foremost,https://example.com/two")
}
