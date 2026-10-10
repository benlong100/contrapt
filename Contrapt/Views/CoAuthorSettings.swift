//
//  CoAuthorSettings.swift
//  Contrapt
//
//  The Settings (Preferences) pane for the AI co-author's opt-in cloud key.
//  Explain runs on-device and needs nothing here; only "Write with AI" uses
//  this key, and only when you invoke it.
//

import SwiftUI

struct CoAuthorSettings: View {
    @State private var key = ""
    @State private var status: String?

    var body: some View {
        Form {
            Section {
                SecureField("Claude API Key", text: $key)
                HStack {
                    Button("Save") {
                        CoAuthorKeychain.save(key)
                        status = key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Cleared." : "Saved to Keychain."
                    }
                    Button("Clear") {
                        CoAuthorKeychain.clear()
                        key = ""
                        status = "Cleared."
                    }
                    if let status {
                        Text(status).foregroundStyle(.secondary).font(.callout)
                    }
                }
            } header: {
                Text("AI Co-author")
            } footer: {
                Text("Powers “Write with AI” (generating and revising scripts). Stored only in your Keychain. When you ask it to write or revise, the object’s script and your request are sent to Anthropic. “Explain” uses Apple’s on-device model and needs no key. Get a key at console.anthropic.com.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onAppear { key = CoAuthorKeychain.load() ?? "" }
    }
}
