//
//  ScriptExplainButton.swift
//  Contrapt
//
//  The read-side AI co-author in the script editor: "Explain" runs the current
//  script through the on-device model (FoundationModels) and shows a plain-
//  language walkthrough — the gentle-slope on-ramp for someone learning
//  HyperTalk. Private/offline; disabled for an empty script.
//

import SwiftUI
import HyperTalk

struct ScriptExplainButton: View {
    /// What owns the script (e.g. "Card Script", "Script of Greet Button") —
    /// used in both the prompt and the sheet.
    let objectLabel: String
    let script: String

    @State private var isPresented = false
    @State private var phase: Phase = .loading
    private let coAuthor: CoAuthoring = FoundationModelsCoAuthor()

    private enum Phase {
        case loading
        case result(String)
        case message(String)   // unavailable, or an error
    }

    var body: some View {
        Button("Explain", systemImage: "sparkles") { explain() }
            .disabled(!CoAuthor.isActionable(.explainScript(objectLabel: objectLabel, script: script)))
            .sheet(isPresented: $isPresented) { sheet }
    }

    private func explain() {
        if let reason = coAuthor.unavailableReason {
            phase = .message(reason)
            isPresented = true
            return
        }
        phase = .loading
        isPresented = true
        Task {
            do {
                let request = CoAuthor.request(for: .explainScript(objectLabel: objectLabel, script: script))
                phase = .result(try await coAuthor.respond(to: request))
            } catch {
                phase = .message("The co-author couldn’t finish: \(error.localizedDescription)")
            }
        }
    }

    @ViewBuilder private var sheet: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Reading the script…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .result(let text):
                    ScrollView {
                        Text(text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                case .message(let message):
                    ContentUnavailableView("Co-author unavailable",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(message))
                }
            }
            .navigationTitle("Explain")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 560, minHeight: 360, idealHeight: 460)
        #endif
    }
}
