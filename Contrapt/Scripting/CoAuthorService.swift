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
