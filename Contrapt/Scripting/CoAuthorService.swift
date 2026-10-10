//
//  CoAuthorService.swift
//  Contrapt
//
//  The app-side AI co-author providers. The read-side (explain) runs on Apple's
//  on-device FoundationModels — private, offline, no key. A provider protocol
//  keeps it pluggable so an opt-in cloud model (for the write-side, which the
//  on-device model isn't suited to) can slot in later without touching callers.
//  Authoring-only: nothing here ships in a stack or the web export.
//

import Foundation
import FoundationModels
import HyperTalk

/// A co-author backend. Prompt construction is shared (HyperTalk.CoAuthor);
/// a provider just runs a request and returns the model's text.
protocol CoAuthoring: Sendable {
    /// Nil when ready; otherwise a human-readable reason it can't run now.
    var unavailableReason: String? { get }
    func respond(to request: CoAuthorRequest) async throws -> String
}

extension CoAuthoring {
    var isAvailable: Bool { unavailableReason == nil }
}

/// The on-device provider (Apple Intelligence). Handles the read-side tasks the
/// on-device model is good at (explain/understand).
struct FoundationModelsCoAuthor: CoAuthoring {
    private var model: SystemLanguageModel { .default }

    var unavailableReason: String? {
        switch model.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            // The reason is an enum; map the common one and fall back to a
            // generic, actionable message for the rest.
            let text = String(describing: reason).lowercased()
            if text.contains("intelligence") {
                return "Turn on Apple Intelligence in System Settings to use the co-author."
            }
            if text.contains("notready") || text.contains("not_ready") || text.contains("downloading") {
                return "The on-device model is still downloading — try again in a little while."
            }
            if text.contains("eligible") || text.contains("device") {
                return "This device doesn’t support Apple Intelligence."
            }
            return "The on-device model isn’t available right now."
        @unknown default:
            return "The on-device model isn’t available right now."
        }
    }

    func respond(to request: CoAuthorRequest) async throws -> String {
        let session = LanguageModelSession(instructions: request.instructions)
        let response = try await session.respond(to: request.prompt)
        return response.content
    }
}

enum CoAuthorError: LocalizedError {
    case noKey
    case service(String)

    var errorDescription: String? {
        switch self {
        case .noKey: "Add your Claude API key in Settings to use AI script writing."
        case .service(let message): message
        }
    }
}

/// The opt-in cloud provider (Claude) for the write-side — generating and
/// revising HyperTalk, which the on-device model isn't suited to. Uses the
/// Anthropic Messages API with the key from the Keychain. The outgoing-network
/// entitlement (already enabled for the `url` container) covers the request.
struct CloudCoAuthor: CoAuthoring {
    /// Default model — fast and strong at code; changeable here.
    static let model = "claude-sonnet-4-6"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    var unavailableReason: String? {
        CoAuthorKeychain.load() == nil ? CoAuthorError.noKey.errorDescription : nil
    }

    func respond(to request: CoAuthorRequest) async throws -> String {
        guard let apiKey = CoAuthorKeychain.load() else { throw CoAuthorError.noKey }

        var urlRequest = URLRequest(url: Self.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": Self.model,
            "max_tokens": 2000,
            "system": request.instructions,
            "messages": [["role": "user", "content": request.prompt]],
        ])

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw CoAuthorError.service("The AI service didn’t respond.")
        }
        guard http.statusCode == 200 else {
            throw CoAuthorError.service("The AI service returned an error (\(http.statusCode))\(Self.errorDetail(data).map { ": \($0)" } ?? ".")")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = object["content"] as? [[String: Any]],
              let text = content.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String else {
            throw CoAuthorError.service("Couldn’t read the AI response.")
        }
        return text
    }

    /// Pulls `error.message` out of an Anthropic error body, if present.
    private static func errorDetail(_ data: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
            .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
    }
}
