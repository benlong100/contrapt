//
//  Reindent.swift
//  HyperTalk
//

import Foundation

public extension HyperTalk {
    /// Recomputes every line's leading whitespace from the script's block
    /// structure (on/end, block if/else, repeat) — HyperCard's auto-indent.
    /// Indentation is derived, never hand-maintained; when it doesn't snap
    /// back after an `end`, the user can see a block is unbalanced.
    /// Tolerant of incomplete code: never throws, clamps at zero.
    ///
    /// Blank lines normally stay empty, but the line at `indentingEmptyLine`
    /// (the caret's freshly created line in an editor) receives the
    /// indentation a statement there would get, so typing starts at depth.
    static func reindent(_ source: String, indentWidth: Int = 2, indentingEmptyLine: Int? = nil) -> String {
        var depth = 0
        var previousWasSingleLineIf = false
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        let indented = lines.enumerated().map { lineNumber, line -> String in
            let content = line.trimmingCharacters(in: .whitespaces)
            if content.isEmpty {
                previousWasSingleLineIf = false
                if lineNumber == indentingEmptyLine {
                    return String(repeating: " ", count: max(0, depth) * indentWidth)
                }
                return ""
            }

            // Tokenize just this line; comments and string contents can't
            // masquerade as keywords. Incomplete lines still yield tokens.
            let words = meaningfulWords(of: content)
            let first = words.first
            let last = words.last

            var printDepth = depth
            var depthAfter = depth
            var isSingleLineIf = false

            switch first {
            case "on":
                printDepth = 0
                depthAfter = 1
            case "end":
                printDepth = depth - 1
                depthAfter = depth - 1
            case "else":
                // `else` belongs to the enclosing block if — dedent it,
                // unless it pairs with a single-line if on the line above.
                printDepth = previousWasSingleLineIf ? depth : depth - 1
                depthAfter = previousWasSingleLineIf ? depth : depth
            case "repeat":
                depthAfter = depth + 1
            case "if":
                if last == "then" {
                    depthAfter = depth + 1
                } else {
                    isSingleLineIf = true
                }
            default:
                break
            }

            previousWasSingleLineIf = isSingleLineIf
            depth = max(0, depthAfter)
            let clamped = max(0, printDepth)
            return String(repeating: " ", count: clamped * indentWidth) + content
        }
        return indented.joined(separator: "\n")
    }

    /// The line's identifier/keyword words, ignoring comments and strings.
    private static func meaningfulWords(of line: String) -> [String] {
        guard let tokens = try? Tokenizer.tokenize(line) else {
            // Unterminated string or stray character: fall back to the
            // first word so `if "oops` still reads as an if line.
            return line.lowercased().components(separatedBy: .whitespaces)
        }
        return tokens.compactMap {
            if case .identifier(let word) = $0.kind { word } else { nil }
        }
    }
}
