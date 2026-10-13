//
//  EngineJSON.swift
//  HyperTalkEngine
//
//  The string-in / string-out ABI the browser bridge calls across the Wasm
//  boundary. Passing JSON strings (rather than marshalling Swift structs
//  through JavaScriptKit) keeps the boundary simple and stable: JS sends an
//  event, gets back `{ effects, state }` (or `{ error }`) as JSON, and renders.
//
//  These wrappers never throw — a script error becomes `error` in the envelope
//  so the page can show it instead of the whole call trapping.
//

import Foundation

// MARK: - Effect encoding (tagged union)

extension HostEffect: Encodable {
    private enum CodingKeys: String, CodingKey {
        case type, cardIndex, effects, text, scriptID, start, end, name, card, encoded
        case message, arguments, partScriptID, cardScriptID, afterSeconds
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .navigate(let index, let effects):
            try c.encode("navigate", forKey: .type)
            try c.encode(index, forKey: .cardIndex)
            try c.encode(effects, forKey: .effects)
        case .message(let text):
            try c.encode("message", forKey: .type)
            try c.encode(text, forKey: .text)
        case .beep:
            try c.encode("beep", forKey: .type)
        case .findHighlight(let scriptID, let start, let end):
            try c.encode("findHighlight", forKey: .type)
            try c.encode(scriptID, forKey: .scriptID)
            try c.encode(start, forKey: .start)
            try c.encode(end, forKey: .end)
        case .clearFindHighlight:
            try c.encode("clearFindHighlight", forKey: .type)
        case .goHome:
            try c.encode("goHome", forKey: .type)
        case .goStack(let name, let card):
            try c.encode("goStack", forKey: .type)
            try c.encode(name, forKey: .name)
            try c.encodeIfPresent(card, forKey: .card)
        case .clickPart(let scriptID):
            try c.encode("clickPart", forKey: .type)
            try c.encode(scriptID, forKey: .scriptID)
        case .persist(let encoded):
            try c.encode("persist", forKey: .type)
            try c.encode(encoded, forKey: .encoded)
        case .scheduleSend(let message, let arguments, let partScriptID, let cardScriptID, let afterSeconds):
            try c.encode("scheduleSend", forKey: .type)
            try c.encode(message, forKey: .message)
            try c.encode(arguments, forKey: .arguments)
            try c.encodeIfPresent(partScriptID, forKey: .partScriptID)
            try c.encode(cardScriptID, forKey: .cardScriptID)
            try c.encode(afterSeconds, forKey: .afterSeconds)
        }
    }
}

// MARK: - Envelopes

/// The result of an event: what changed in the world, and the current card to
/// render. `error` is set instead when a script failed.
struct EventResult: Encodable {
    var effects: [HostEffect]
    var state: CardState
    var error: String?
}

/// A message-box line's result: its printed value plus the usual envelope.
struct MessageResult: Encodable {
    var result: String?
    var effects: [HostEffect]
    var state: CardState
    var error: String?
}

/// The initial load payload: stack dimensions and the first card's state.
struct Snapshot: Encodable {
    var name: String
    var cardCount: Int
    var currentCardIndex: Int
    var cardWidth: Double
    var cardHeight: Double
    var state: CardState
}

// MARK: - JSON entry points

extension StackEngine {
    /// The stack's dimensions and current card, for the page's first render.
    public func snapshotJSON() -> String {
        encode(Snapshot(
            name: stackName, cardCount: cardCount, currentCardIndex: currentCardIndex,
            cardWidth: cardWidth, cardHeight: cardHeight, state: currentCardState()
        ))
    }

    /// `openStack` + `openCard` for the first card; returns `{ effects, state }`.
    public func startJSON() async -> String {
        await eventJSON { try await self.start() }
    }

    /// A button/locked-field click: `{ effects, state }` (or `{ error }`).
    /// Field clicks may carry the clicked line/word (see dispatchMouseUp).
    public func dispatchMouseUpJSON(partScriptID: Int, clickLine: Int? = nil, clickText: String? = nil) async -> String {
        await eventJSON { try await self.dispatchMouseUp(partScriptID: partScriptID, clickLine: clickLine, clickText: clickText) }
    }

    /// Land on a card and send it `openCard`.
    public func openCardJSON(index: Int) async -> String {
        await eventJSON { try await self.openCard(index: index) }
    }

    /// Send a named message to a part — the field-editing lifecycle
    /// (openField / closeField / exitField) from the page's focus events.
    /// `{ effects, state }` (or `{ error }`); unhandled messages are fine.
    public func sendToPartJSON(_ message: String, partScriptID: Int) async -> String {
        await eventJSON { try await self.send(message, toPartWithScriptID: partScriptID) }
    }

    /// A `send … in <time>` timer firing: deliver the message to its target
    /// (part scriptID, or the carrying card's path when partScriptID < 0).
    /// Arguments arrive as a JSON array string. `{ effects, state }`.
    public func deliverScheduledJSON(message: String, argumentsJSON: String, partScriptID: Int, cardScriptID: Int) async -> String {
        let arguments = (try? JSONDecoder().decode([String].self, from: Data(argumentsJSON.utf8))) ?? []
        return await eventJSON {
            try await self.deliverScheduled(message: message, arguments: arguments,
                                            partScriptID: partScriptID >= 0 ? partScriptID : nil,
                                            cardScriptID: cardScriptID)
        }
    }

    /// The visitor edited a field: record its text. `{ effects, state }` —
    /// effects is always empty today (typing sends no messages yet; openField/
    /// closeField are a follow-up), but the envelope matches the other calls.
    public func setFieldJSON(partScriptID: Int, text: String) -> String {
        do {
            try setField(partScriptID: partScriptID, text: text)
            return encode(EventResult(effects: [], state: currentCardState()))
        } catch {
            return encode(EventResult(effects: [], state: currentCardState(),
                                      error: error.localizedDescription))
        }
    }

    /// Run one message-box line; `{ result, effects, state }` (or `{ error }`).
    public func runMessageJSON(_ line: String) async -> String {
        do {
            let value = try await runMessage(line)
            return encode(MessageResult(result: value, effects: drainEffects(), state: currentCardState()))
        } catch {
            return encode(MessageResult(result: nil, effects: [], state: currentCardState(),
                                        error: error.localizedDescription))
        }
    }

    // MARK: - Helpers

    private func eventJSON(_ body: () async throws -> [HostEffect]) async -> String {
        do {
            let effects = try await body()
            return encode(EventResult(effects: effects, state: currentCardState()))
        } catch {
            return encode(EventResult(effects: [], state: currentCardState(),
                                      error: error.localizedDescription))
        }
    }

    private func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let string = String(data: data, encoding: .utf8) else {
            return #"{"error":"Failed to encode engine output."}"#
        }
        return string
    }
}
