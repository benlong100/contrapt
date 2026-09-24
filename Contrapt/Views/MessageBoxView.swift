//
//  MessageBoxView.swift
//  Contrapt
//

import SwiftUI

/// HyperCard's Message Box: `put` output lands here, and the field below
/// runs any typed HyperTalk line in the context of the current card —
/// commands (`go to card 3`), messages (`greet "Bill"`), or expressions
/// (`2 + 3`, `field "Name"`) whose values display as output.
struct MessageBoxView: View {
    let output: String?
    var onCommand: (String) -> Void

    @State private var command = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let output, !output.isEmpty {
                Text(output)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
            }
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(.caption, design: .monospaced).bold())
                    .foregroundStyle(.secondary)
                TextField("Type HyperTalk and press return…", text: $command)
                    .font(.system(.callout, design: .monospaced))
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        let line = command.trimmingCharacters(in: .whitespaces)
                        guard !line.isEmpty else { return }
                        onCommand(line)
                    }
            }
        }
        .padding(14)
        .frame(maxWidth: 560, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.bottom, 12)
    }
}

#Preview {
    MessageBoxView(output: "You've arrived at card 2", onCommand: { _ in })
}
