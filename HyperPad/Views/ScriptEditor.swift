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

/// The outcome of a Check Script run.
struct ScriptCheckResult: Equatable {
    let isValid: Bool
    let message: String

    static func checking(_ script: String) -> ScriptCheckResult {
        do {
            try HyperTalk.check(script)
            return ScriptCheckResult(isValid: true, message: "No problems found.")
        } catch {
            return ScriptCheckResult(isValid: false, message: error.localizedDescription)
        }
    }

    var label: some View {
        Label(message, systemImage: isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(isValid ? Color.green : Color.red)
    }
}

/// A form section holding a script editor plus Check Script and an expand
/// button opening the full-screen editor; shared by the part inspector and
/// the object-scripts inspector.
struct ScriptFormSection: View {
    let title: String
    var editorTitle: String? = nil
    @Binding var script: String

    @State private var checkResult: ScriptCheckResult?
    @State private var isExpanded = false

    var body: some View {
        Section(title) {
            ScriptEditor(script: $script)
            HStack {
                Button("Check Script", systemImage: "checkmark.seal") {
                    checkResult = .checking(script)
                }
                Spacer()
                Button("Expand Editor", systemImage: "arrow.up.left.and.arrow.down.right") {
                    isExpanded = true
                }
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            if let checkResult {
                checkResult.label
            }
        }
        .onChange(of: script) {
            checkResult = nil
        }
        .fullScreenCover(isPresented: $isExpanded) {
            LargeScriptEditor(title: editorTitle ?? title, script: $script)
        }
    }
}

/// The full-screen script editor — HyperCard's dedicated script window,
/// for scripts too big for the inspector column.
struct LargeScriptEditor: View {
    let title: String
    @Binding var script: String

    @Environment(\.dismiss) private var dismiss
    @State private var checkResult: ScriptCheckResult?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScriptEditor(script: $script)
                    .padding(.horizontal)
                if let checkResult {
                    checkResult.label
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.bar)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Check Script", systemImage: "checkmark.seal") {
                        checkResult = .checking(script)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: script) {
                checkResult = nil
            }
        }
    }
}

#Preview("Large Editor") {
    @Previewable @State var script = """
    on mouseUp -- a deeply nested example
      repeat with i = 1 to 10
        if i mod 3 = 0 then
          if field "Mode" is "loud" then
            put "Fizz at" && i after field "Log"
          else
            put "fizz" after field "Log"
          end if
        else
          put i after field "Log"
        end if
      end repeat
    end mouseUp
    """
    LargeScriptEditor(title: "Script of Greet Button", script: $script)
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
