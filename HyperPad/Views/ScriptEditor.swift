//
//  ScriptEditor.swift
//  HyperPad
//

import SwiftUI
import HyperTalk

/// A HyperTalk script editor with live syntax coloring. The colored
/// AttributedString is local state; the plain text flows through the
/// `script` binding. Recoloring mutates attributes in place — never the
/// characters — so the selection survives.
struct ScriptEditor: View {
    @Binding var script: String
    @State private var text = AttributedString()

    var body: some View {
        TextEditor(text: $text)
            .font(.system(.callout, design: .monospaced))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .frame(minHeight: 220)
            .onAppear {
                text = highlighted(AttributedString(script))
            }
            .onChange(of: script) { _, newScript in
                // External change (part switched, undo): rebuild wholesale.
                if String(text.characters) != newScript {
                    text = highlighted(AttributedString(newScript))
                }
            }
            .onChange(of: text) { _, newText in
                let plain = String(newText.characters)
                if plain != script {
                    script = plain
                }
                let recolored = highlighted(newText)
                if recolored != newText {
                    text = recolored
                }
            }
    }

    private func highlighted(_ source: AttributedString) -> AttributedString {
        var result = source
        result.foregroundColor = nil
        let plain = String(result.characters)
        for span in HyperTalk.syntaxSpans(in: plain) {
            guard let color = color(for: span.kind),
                  let range = Range(span.range, in: result) else { continue }
            result[range].foregroundColor = color
        }
        return result
    }

    private func color(for kind: SyntaxSpan.Kind) -> Color? {
        switch kind {
        case .keyword: .purple
        case .string: .red
        case .number: .blue
        case .comment: .gray
        case .identifier, .symbol: nil
        }
    }
}

/// A form section holding a script editor plus the Check Script button,
/// shared by the part inspector and the object-scripts inspector.
struct ScriptFormSection: View {
    let title: String
    @Binding var script: String

    @State private var checkResult: CheckResult?

    private struct CheckResult: Equatable {
        let isValid: Bool
        let message: String
    }

    var body: some View {
        Section(title) {
            ScriptEditor(script: $script)
            Button("Check Script", systemImage: "checkmark.seal") {
                checkScript()
            }
            if let checkResult {
                Label(checkResult.message, systemImage: checkResult.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(checkResult.isValid ? .green : .red)
            }
        }
        .onChange(of: script) {
            checkResult = nil
        }
    }

    private func checkScript() {
        do {
            try HyperTalk.check(script)
            checkResult = CheckResult(isValid: true, message: "No problems found.")
        } catch {
            checkResult = CheckResult(isValid: false, message: error.localizedDescription)
        }
    }
}

#Preview {
    @Previewable @State var script = """
    on mouseUp -- greet the user
      if field "Name" is empty then
        put "Hello, stranger!" into field "Greeting"
      else
        put "Hello," && field "Name" & "!" into field "Greeting"
      end if
      put 42 into answer
    end mouseUp
    """
    Form {
        ScriptEditor(script: $script)
    }
}
