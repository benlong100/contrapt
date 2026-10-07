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

    public init(
        answer: @escaping @Sendable (String, [String]) async -> String = { _, buttons in buttons.first ?? "OK" },
        ask: @escaping @Sendable (String, String) async -> String? = { _, initial in initial },
        answerFile: @escaping @Sendable (String, String?) async -> String? = { _, _ in nil },
        wait: @escaping @Sendable (Double) async -> Void = { _ in }
    ) {
        self.answer = answer
        self.ask = ask
        self.answerFile = answerFile
        self.wait = wait
    }
}
