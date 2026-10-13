//
//  MarkdownLinksTests.swift
//  HyperTalk
//
//  The text logic behind `the link of <chunk> of field …` on rich fields:
//  wrap a range as [label](target), retarget a link the range touches,
//  unwrap with an empty target, read the covering target.
//

import Testing
@testable import HyperTalk

@Test func settingALinkWrapsTheRange() {
    // "Visit the site today" — link "the site" (chars 6..<14).
    let out = MarkdownLinks.settingLink(in: "Visit the site today", range: 6..<14, to: "https://example.com")
    #expect(out == "Visit [the site](https://example.com) today")
}

@Test func settingInsideAnExistingLinkRetargets() {
    let source = "Visit [the site](https://old.example) today"
    let out = MarkdownLinks.settingLink(in: source, range: 8..<11, to: "card:Contents")
    #expect(out == "Visit [the site](card:Contents) today")
}

@Test func emptyTargetUnwrapsTheLink() {
    let source = "Visit [the site](https://old.example) today"
    let out = MarkdownLinks.settingLink(in: source, range: 8..<11, to: "")
    #expect(out == "Visit the site today")
}

@Test func emptyTargetOutsideALinkChangesNothing() {
    #expect(MarkdownLinks.settingLink(in: "plain words", range: 0..<5, to: "") == "plain words")
    #expect(MarkdownLinks.settingLink(in: "plain words", range: 3..<3, to: "https://x") == "plain words")
}

@Test func readingTheLinkFindsTheCoveringTarget() {
    let source = "Visit [the site](https://example.com) today"
    #expect(MarkdownLinks.link(in: source, at: 8..<11) == "https://example.com")
    #expect(MarkdownLinks.link(in: source, at: 0..<5) == "")
}

@Test func rangesClampToTheSource() {
    let out = MarkdownLinks.settingLink(in: "short", range: 2..<99, to: "card:2")
    #expect(out == "sh[ort](card:2)")
}
