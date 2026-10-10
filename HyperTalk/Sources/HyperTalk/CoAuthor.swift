//
//  CoAuthor.swift
//  HyperTalk
//
//  The AI co-author's prompt construction — shared, provider-agnostic, and pure
//  (String in, String out), so it's unit-tested here while the actual model
//  call (Apple's on-device FoundationModels, or later an opt-in cloud model)
//  lives app-side behind a protocol. Increment 1 is the read-side: explaining a
//  script to someone learning HyperTalk — the "gentle slope" on-ramp.
//

import Foundation

/// A task for the co-author to perform. Read-side tasks first; write-side
/// (generate/revise HyperTalk) comes later behind the same request shape.
public enum CoAuthorTask: Equatable, Sendable {
    /// Explain what a script does, in plain language, for a learner.
    /// `objectLabel` names what owns the script ("card button \"Save\"").
    case explainScript(objectLabel: String, script: String)
}

/// The two text pieces a language-model session needs: the system `instructions`
/// (how to behave) and the `prompt` (the turn's content).
public struct CoAuthorRequest: Equatable, Sendable {
    public let instructions: String
    public let prompt: String

    public init(instructions: String, prompt: String) {
        self.instructions = instructions
        self.prompt = prompt
    }
}

public enum CoAuthor {
    /// Whether a task is worth sending to the model at all (e.g. an empty script
    /// has nothing to explain) — the app skips the call and says so itself.
    public static func isActionable(_ task: CoAuthorTask) -> Bool {
        switch task {
        case .explainScript(_, let script):
            return !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public static func request(for task: CoAuthorTask) -> CoAuthorRequest {
        switch task {
        case .explainScript(let objectLabel, let script):
            return CoAuthorRequest(instructions: explainInstructions, prompt: explainPrompt(objectLabel: objectLabel, script: script))
        }
    }

    /// Teaches the model what HyperTalk is and how to explain it — kept short
    /// (every token counts against the on-device context window) but specific
    /// enough that it describes behavior faithfully instead of inventing it.
    static let explainInstructions = """
    You are a friendly guide to HyperTalk, the plain-English scripting language of HyperCard and Contrapt. \
    Explain what a script does in clear, simple terms for someone learning to program. \
    Go handler by handler: name the message that triggers each one (for example mouseUp fires when a button is clicked, openCard when a card opens) and describe what it then does. \
    Be concise and concrete. Only describe behavior that is actually in the script — do not invent features or suggest changes unless asked.
    """

    static func explainPrompt(objectLabel: String, script: String) -> String {
        let owner = objectLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let lead = owner.isEmpty ? "Explain this HyperTalk script:" : "Explain this HyperTalk script (\(owner)):"
        return "\(lead)\n\n\(script)"
    }
}
