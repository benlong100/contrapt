//
//  Syntax.swift
//  HyperTalk
//

import Foundation

/// A classified region of script source, for syntax coloring.
public struct SyntaxSpan: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case keyword
        case string
        case number
        case comment
        case identifier
        case symbol
    }

    public let kind: Kind
    public let range: Range<String.Index>
}

public extension HyperTalk {
    /// Parses without running: throws a line-numbered `ScriptError` if the
    /// script has problems, returns silently if it's well-formed.
    static func check(_ scriptSource: String) throws {
        _ = try Parser.parse(scriptSource)
    }

    /// Lightweight scan for syntax coloring. Never throws and tolerates
    /// incomplete code — an unterminated string colors to the end of its
    /// line, unknown characters are skipped.
    static func syntaxSpans(in source: String) -> [SyntaxSpan] {
        SyntaxScanner.scan(source)
    }
}

enum SyntaxScanner {
    /// Words colored as keywords: commands, control flow, operators-as-words,
    /// and the built-in constants.
    static let keywords: Set<String> = [
        "on", "end", "exit", "next",
        "if", "then", "else",
        "repeat", "forever", "while", "until", "with", "times", "down", "to", "for",
        "go", "put", "into", "after", "before", "beep",
        "and", "or", "not", "is", "contains", "div", "mod",
        "the", "card", "field",
        "previous", "prev", "first", "last",
        "empty", "true", "false", "quote", "space", "return", "comma", "tab",
    ]

    static func scan(_ source: String) -> [SyntaxSpan] {
        var spans: [SyntaxSpan] = []
        var index = source.startIndex

        func advance() {
            index = source.index(after: index)
        }

        while index < source.endIndex {
            let character = source[index]
            let start = index

            let next: Character? = {
                let after = source.index(after: index)
                return after < source.endIndex ? source[after] : nil
            }()
            if Tokenizer.startsComment(character, next: next) {
                while index < source.endIndex, source[index] != "\n" { advance() }
                spans.append(SyntaxSpan(kind: .comment, range: start..<index))
            } else if Tokenizer.isQuote(character) {
                advance()
                while index < source.endIndex, !Tokenizer.isQuote(source[index]), source[index] != "\n" { advance() }
                if index < source.endIndex, Tokenizer.isQuote(source[index]) { advance() }
                spans.append(SyntaxSpan(kind: .string, range: start..<index))
            } else if character.isNumber {
                while index < source.endIndex, source[index].isNumber { advance() }
                if index < source.endIndex, source[index] == "." {
                    let next = source.index(after: index)
                    if next < source.endIndex, source[next].isNumber {
                        advance()
                        while index < source.endIndex, source[index].isNumber { advance() }
                    }
                }
                spans.append(SyntaxSpan(kind: .number, range: start..<index))
            } else if character.isLetter || character == "_" {
                while index < source.endIndex,
                      source[index].isLetter || source[index].isNumber || source[index] == "_" {
                    advance()
                }
                let word = source[start..<index].lowercased()
                let kind: SyntaxSpan.Kind = keywords.contains(word) ? .keyword : .identifier
                spans.append(SyntaxSpan(kind: kind, range: start..<index))
            } else {
                advance()
                if !character.isWhitespace {
                    spans.append(SyntaxSpan(kind: .symbol, range: start..<index))
                }
            }
        }
        return spans
    }
}
