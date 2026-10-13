//
//  HostEffect.swift
//  HyperTalkEngine
//
//  Side effects a running script produces that the *outside world* (the web
//  page) must apply — navigation, the message box, a beep, a find highlight,
//  cross-stack jumps. The headless host records them in order; the JS bridge
//  drains and applies them after each dispatch. (Field/property writes mutate
//  the in-memory stack directly and surface through `currentCardState()`, so
//  they are not effects.)
//

import Foundation
import HyperTalk

public enum HostEffect: Equatable, Sendable {
    /// Navigate to a card index (0-based), optionally with visual effects to
    /// play (kind/direction/speed, as scripted). The engine has already made
    /// this the current card; the page renders the transition.
    case navigate(cardIndex: Int, effects: [ScreenEffect])
    /// `put <x>` with no destination — show `text` in the message box.
    case message(String)
    /// `beep`.
    case beep
    /// A successful `find`: box the match on the given part.
    case findHighlight(partScriptID: Int, start: Int, end: Int)
    /// A failed `find` — clear any existing highlight.
    case clearFindHighlight
    /// `go home` — open the Home stack (the page decides what that means).
    case goHome
    /// `go [card N of] stack "X"` — open another stack by name.
    case goStack(name: String, card: String?)
    /// `click at h,v` resolved to a part; the page may re-dispatch its mouseUp.
    case clickPart(scriptID: Int)
    /// A write to the stack's persistent store (`stackData`) — the page flushes
    /// `encoded` to localStorage, keyed by the stack, so it survives reloads.
    case persist(encoded: String)
    /// `send <msg> to <object> in <time>` — the page sets a timer and, when
    /// it fires, calls the engine's `deliverScheduled` with these values. A
    /// part target carries its scriptID; otherwise the message travels the
    /// carrying card's path. Page timers die with the page, which is exactly
    /// the rule: pending sends die when the stack closes.
    case scheduleSend(message: String, arguments: [String], partScriptID: Int?, cardScriptID: Int, afterSeconds: Double)
}

/// How the host answers the interactive, suspending commands. The JS bridge
/// supplies real implementations (a dialog, a prompt, a timer); tests and the
/// default use canned, instant responses so the engine runs headless.
public struct EngineInteraction: Sendable {
    public var answer: @Sendable (_ prompt: String, _ buttons: [String]) async -> String
    public var ask: @Sendable (_ prompt: String, _ initialAnswer: String) async -> String?
    /// `answer file` — returns the chosen file's path, or nil on cancel. The
    /// default cancels, since a headless/web host has no file picker.
    public var answerFile: @Sendable (_ prompt: String, _ type: String?) async -> String?
    public var wait: @Sendable (_ seconds: Double) async -> Void
    /// `url`/`post`/`delete url` — an HTTP request from the exported page. The JS
    /// bridge supplies a `fetch`-backed implementation (subject to the browser's
    /// CORS policy — the page can't proxy around it); the default reports that
    /// networking isn't available, so headless runs and tests stay offline.
    public var httpRequest: @Sendable (_ method: String, _ url: String, _ body: String?, _ headers: [String: String], _ timeout: Double) async -> (body: String, status: Int, headers: [String: String], error: String?)

    public init(
        answer: @escaping @Sendable (String, [String]) async -> String = { _, buttons in buttons.first ?? "OK" },
        ask: @escaping @Sendable (String, String) async -> String? = { _, initial in initial },
        answerFile: @escaping @Sendable (String, String?) async -> String? = { _, _ in nil },
        wait: @escaping @Sendable (Double) async -> Void = { _ in },
        httpRequest: @escaping @Sendable (String, String, String?, [String: String], Double) async -> (body: String, status: Int, headers: [String: String], error: String?) = { _, _, _, _, _ in ("", 0, [:], "Networking isn't available here.") }
    ) {
        self.answer = answer
        self.ask = ask
        self.answerFile = answerFile
        self.wait = wait
        self.httpRequest = httpRequest
    }
}
