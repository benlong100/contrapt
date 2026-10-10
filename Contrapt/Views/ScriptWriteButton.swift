//
//  ScriptWriteButton.swift
//  Contrapt
//
//  The write-side AI co-author: describe what you want, and the cloud model
//  (opt-in, your Claude key) returns the complete updated script. The output is
//  sanitized and parse-checked with HyperTalk.check before you can Apply, so
//  invalid code is flagged — never silently dropped into a stack.
//

import SwiftUI
import HyperTalk

struct ScriptWriteButton: View {
    /// What owns the script (used in the prompt and the sheet title).
    let objectLabel: String
    /// Bound so Apply can replace the script in place.
    @Binding var script: String

    @State private var isPresented = false
    @State private var instruction = ""
    @State private var phase: Phase = .input
    private let coAuthor: CoAuthoring = CloudCoAuthor()

    private enum Phase {
        case input
        case loading
        case preview(script: String, check: ScriptCheckResult)
        case message(String)   // unavailable, or an error
    }

    var body: some View {
        Button("Write with AI", systemImage: "wand.and.stars") { open() }
            .sheet(isPresented: $isPresented) { sheet }
    }

    private func open() {
        if let reason = coAuthor.unavailableReason {
            phase = .message(reason)
        } else {
            phase = .input
        }
        isPresented = true
    }

    private func generate() {
        let ask = instruction
        guard CoAuthor.isActionable(.writeScript(objectLabel: objectLabel, instruction: ask, currentScript: script)) else { return }
        phase = .loading
        Task {
            do {
                let request = CoAuthor.request(for: .writeScript(objectLabel: objectLabel, instruction: ask, currentScript: script))
                let raw = try await coAuthor.respond(to: request)
                let cleaned = CoAuthor.sanitizeGeneratedScript(raw)
                phase = .preview(script: cleaned, check: .checking(cleaned))
            } catch {
                phase = .message(error.localizedDescription)
            }
        }
    }

    @ViewBuilder private var sheet: some View {
        NavigationStack {
            Group {
                switch phase {
                case .input:
                    inputForm
                case .loading:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Writing HyperTalk…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .preview(let generated, let check):
                    previewForm(generated: generated, check: check)
                case .message(let message):
                    ContentUnavailableView("Co-author unavailable",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(message))
                }
            }
            .navigationTitle("Write with AI")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 420, idealHeight: 540)
        #endif
    }

    private var inputForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Describe what this \(objectLabel.isEmpty ? "script" : objectLabel) should do. The AI returns the complete updated script for you to review before applying.")
                .foregroundStyle(.secondary)
            TextEditor(text: $instruction)
                .font(.body)
                .frame(minHeight: 100)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            HStack {
                Spacer()
                Button("Generate") { generate() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
    }

    private func previewForm(generated: String, check: ScriptCheckResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            check.label
            ScrollView {
                Text(generated)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            HStack {
                Button("Try Again") { phase = .input }
                Spacer()
                Button("Apply") {
                    script = generated
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }
}
