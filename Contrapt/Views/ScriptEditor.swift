//
//  ScriptEditor.swift
//  Contrapt
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
    @State private var selection = AttributedTextSelection()

    var body: some View {
        TextEditor(text: $text, selection: $selection)
            .font(.system(.callout, design: .monospaced))
            .autocorrectionDisabled()
            .codeEntryTraits()
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
                guard plain != script else { return }

                // The caret comes from the text diff, not the selection
                // binding — the selection hasn't been updated yet when
                // this change handler runs.
                let caretOffset = caretOffsetAfterEdit(from: script, to: plain)

                // A newly typed return re-indents the whole script from its
                // block structure, HyperCard style. The caret's fresh empty
                // line is pre-indented to block depth so typing starts there.
                if newlineCount(of: plain) > newlineCount(of: script) {
                    let caretLine = plain.prefix(caretOffset).lazy.filter { $0 == "\n" }.count
                    let reindented = HyperTalk.reindent(plain, indentingEmptyLine: caretLine)
                    if reindented != plain {
                        script = reindented
                        applyReindented(reindented, caretWasAt: caretOffset, in: plain)
                        return
                    }
                }

                script = plain
                let recolored = highlighted(newText)
                if recolored != newText {
                    // Wholesale attribute replacement also resets the caret
                    // (e.g. a newline typed after a colored token inherits
                    // its color, forcing a recolor pass) — restore it.
                    text = recolored
                    setCaret(at: min(caretOffset, plain.count), in: recolored)
                }
            }
    }

    /// Sets the insertion point now, and re-asserts it on the next runloop
    /// turn in case the editor's own (stale) selection update lands after
    /// this handler. The re-assert is skipped if the text moved on.
    private func setCaret(at offset: Int, in expected: AttributedString) {
        let caret = expected.characters.index(expected.startIndex, offsetBy: offset)
        selection = AttributedTextSelection(insertionPoint: caret)
        let expectedPlain = String(expected.characters)
        Task { @MainActor in
            guard String(text.characters) == expectedPlain else { return }
            let caret = text.characters.index(text.startIndex, offsetBy: offset)
            selection = AttributedTextSelection(insertionPoint: caret)
        }
    }

    private func newlineCount(of string: String) -> Int {
        string.lazy.filter { $0 == "\n" }.count
    }

    /// Where the caret sits after an edit, derived from the old and new
    /// text. Matching greedily from the end resolves ambiguous insertions
    /// (a return typed before an existing newline) toward the newly
    /// created line, which is where the caret actually is.
    private func caretOffsetAfterEdit(from old: String, to new: String) -> Int {
        let oldChars = Array(old)
        let newChars = Array(new)
        var suffix = 0
        while suffix < oldChars.count, suffix < newChars.count,
              oldChars[oldChars.count - 1 - suffix] == newChars[newChars.count - 1 - suffix] {
            suffix += 1
        }
        return newChars.count - suffix
    }

    /// Replaces the text with the re-indented script, keeping the caret on
    /// its line at the equivalent column (adjusted for the line's new
    /// leading whitespace).
    private func applyReindented(_ reindented: String, caretWasAt caretOffset: Int, in plain: String) {
        // Locate the caret's line and column in the pre-indent text.
        let plainLines = plain.components(separatedBy: "\n")
        var lineIndex = 0
        var lineStart = 0
        for line in plainLines {
            let lineEnd = lineStart + line.count
            if caretOffset <= lineEnd { break }
            lineStart = lineEnd + 1
            lineIndex += 1
        }
        lineIndex = min(lineIndex, plainLines.count - 1)
        let oldLine = plainLines[lineIndex]
        let column = max(0, caretOffset - lineStart)
        let oldLeading = oldLine.prefix(while: { $0 == " " }).count
        let contentColumn = max(0, column - oldLeading)

        // The same line and content column in the re-indented text.
        let newLines = reindented.components(separatedBy: "\n")
        var offset = 0
        for line in newLines.prefix(lineIndex) { offset += line.count + 1 }
        if lineIndex < newLines.count {
            let newLine = newLines[lineIndex]
            let newLeading = newLine.prefix(while: { $0 == " " }).count
            offset += min(newLeading + contentColumn, newLine.count)
        }
        offset = min(offset, reindented.count)

        let updated = highlighted(AttributedString(reindented))
        text = updated
        setCaret(at: offset, in: updated)
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
/// button; shared by the part inspector and the object-scripts inspector.
/// The full-screen presentation itself is owned by the enclosing Form —
/// presentations anchored inside a Form row get torn down when the row
/// rebuilds (e.g. as the keyboard dismisses), closing the cover instantly.
struct ScriptFormSection: View {
    let title: String
    @Binding var script: String
    var onExpand: () -> Void

    @State private var checkResult: ScriptCheckResult?

    var body: some View {
        Section(title) {
            ScriptEditor(script: $script)
            HStack {
                Button("Check Script", systemImage: "checkmark.seal") {
                    checkResult = .checking(script)
                }
                ScriptExplainButton(objectLabel: title, script: script)
                ScriptWriteButton(objectLabel: title, script: $script)
                Spacer()
                Button("Expand Editor", systemImage: "arrow.up.left.and.arrow.down.right") {
                    onExpand()
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
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Check Script", systemImage: "checkmark.seal") {
                        checkResult = .checking(script)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    ScriptExplainButton(objectLabel: title, script: script)
                }
                ToolbarItem(placement: .primaryAction) {
                    ScriptWriteButton(objectLabel: title, script: $script)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: script) {
                checkResult = nil
            }
        }
        #if os(macOS)
        // On macOS this editor is a sheet, which sizes to its content —
        // give it room for real, deeply nested scripts.
        .frame(minWidth: 700, idealWidth: 900, minHeight: 500, idealHeight: 720)
        #endif
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
