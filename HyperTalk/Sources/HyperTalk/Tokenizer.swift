//
//  Tokenizer.swift
//  HyperTalk
//

import Foundation

enum TokenKind: Equatable {
    /// Identifiers and keywords, lowercased (HyperTalk is case-insensitive).
    case identifier(String)
    case number(Double)
    case string(String)
    /// One of: + - * / ( ) , = < > <= >= <> & &&
    case symbol(String)
    case newline
    case endOfScript
}

struct Token: Equatable {
    let kind: TokenKind
    let line: Int
}

struct Tokenizer {
    private let characters: [Character]
    private var index = 0
    private var line = 1

    init(_ source: String) {
        // Normalize CRLF and the Unicode variants HyperTalk sources may carry.
        characters = Array(source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n"))
    }

    static func tokenize(_ source: String) throws -> [Token] {
        var tokenizer = Tokenizer(source)
        var tokens: [Token] = []
        while true {
            let token = try tokenizer.next()
            tokens.append(token)
            if token.kind == .endOfScript { break }
        }
        return tokens
    }

    private var current: Character? { index < characters.count ? characters[index] : nil }
    private var peekAhead: Character? { index + 1 < characters.count ? characters[index + 1] : nil }

    private mutating func advance() { index += 1 }

    private mutating func next() throws -> Token {
        skipSpacesAndComments()

        guard let character = current else {
            return Token(kind: .endOfScript, line: line)
        }

        if character == "\n" {
            let token = Token(kind: .newline, line: line)
            advance()
            line += 1
            return token
        }

        // ¬ (or ⌐) at end of line continues the statement on the next line.
        if character == "¬" || character == "⌐" {
            advance()
            skipSpacesAndComments()
            if current == "\n" {
                advance()
                line += 1
            }
            return try next()
        }

        if Self.isQuote(character) {
            return try stringLiteral()
        }

        if character.isNumber || (character == "." && peekAhead?.isNumber == true) {
            return numberLiteral()
        }

        // Classic Mac authors used option-key symbols in names (`∆` as a
        // delimiter variable, Aloun-Madu) — HyperCard accepted them.
        if character.isLetter || character == "_" || character == "\u{2206}" {
            return identifier()
        }

        return try symbol(character)
    }

    /// Any straight or curly double quote can *open* a string — iPad smart
    /// quotes (and scripts pasted from anywhere) must not break scripts.
    static func isQuote(_ character: Character) -> Bool {
        character == "\"" || character == "\u{201C}" || character == "\u{201D}"
    }

    /// Which quote *closes* a string depends on how it opened. A straight
    /// `"…"` closes only on another straight quote, so classic scripts can
    /// carry literal curly quotes as content (`"“"`, `"”"` — the ldquo/rdquo
    /// characters typed with option-[ / option-shift-[). A curly-open `“…`
    /// closes on its `”` mate, or tolerantly on a straight quote (iPad may
    /// convert only one of a pair).
    static func closesString(opener: Character, _ character: Character) -> Bool {
        switch opener {
        case "\"":
            return character == "\""
        case "\u{201C}":
            return character == "\u{201D}" || character == "\""
        default:
            return isQuote(character)
        }
    }

    /// `--` starts a comment; so do en/em dashes, which is what iOS smart
    /// dashes turn a typed `--` into.
    static func startsComment(_ character: Character, next: Character?) -> Bool {
        (character == "-" && next == "-") || character == "\u{2013}" || character == "\u{2014}"
    }

    private mutating func skipSpacesAndComments() {
        while let character = current {
            if character == " " || character == "\t" {
                advance()
            } else if Self.startsComment(character, next: peekAhead) {
                while let c = current, c != "\n" { advance() }
            } else {
                break
            }
        }
    }

    private mutating func stringLiteral() throws -> Token {
        let startLine = line
        let opener = current ?? "\""
        advance() // opening quote
        var text = ""
        while let character = current {
            if Self.closesString(opener: opener, character) {
                advance()
                // A DOUBLED quote is a literal quote inside the string —
                // `answer "Please fill in ""Lotto 5"" field"` (Balls!). An
                // empty string (`""` then anything else) is unaffected.
                if opener == "\"", current == "\"" {
                    text.append("\"")
                    advance()
                    continue
                }
                return Token(kind: .string(text), line: startLine)
            }
            if character == "\n" {
                throw ScriptError(line: startLine, message: "This quoted text is missing its closing quote.")
            }
            text.append(character)
            advance()
        }
        throw ScriptError(line: startLine, message: "This quoted text is missing its closing quote.")
    }

    private mutating func numberLiteral() -> Token {
        var text = ""
        while let character = current, character.isNumber {
            text.append(character)
            advance()
        }
        // A trailing period after the digits is part of the number, as the
        // classic converter read it — `go to card 39.` (Castle Quest) is 39.
        if current == ".", peekAhead?.isNumber != true, peekAhead != "." {
            advance()
            return Token(kind: .number(Double(text) ?? 0), line: line)
        }
        if current == ".", peekAhead?.isNumber == true {
            text.append(".")
            advance()
            while let character = current, character.isNumber {
                text.append(character)
                advance()
            }
        }
        return Token(kind: .number(Double(text) ?? 0), line: line)
    }

    private mutating func identifier() -> Token {
        var text = ""
        while let character = current, character.isLetter || character.isNumber || character == "_" || character == "\u{2206}"
                || character == "\u{00AE}" || character == "\u{2122}" || character == "\u{00A9}"
                // An apostrophe CONTINUES an identifier only when a letter
                // follows (doesn't, isn't) — a trailing quote stays a symbol.
                || ((character == "'" || character == "\u{2019}") && peekAhead?.isLetter == true) {
            text.append(character)
            advance()
        }
        return Token(kind: .identifier(text.lowercased()), line: line)
    }

    private mutating func symbol(_ character: Character) throws -> Token {
        let startLine = line
        func make(_ text: String, consume: Int) -> Token {
            for _ in 0..<consume { advance() }
            return Token(kind: .symbol(text), line: startLine)
        }
        switch character {
        case "+", "*", "/", "(", ")", ",", "-", "^":
            return make(String(character), consume: 1)
        case "&":
            return peekAhead == "&" ? make("&&", consume: 2) : make("&", consume: 1)
        case "=":
            return make("=", consume: 1)
        case "<":
            if peekAhead == "=" { return make("<=", consume: 2) }
            if peekAhead == ">" { return make("<>", consume: 2) }
            return make("<", consume: 1)
        case ">":
            return peekAhead == "=" ? make(">=", consume: 2) : make(">", consume: 1)
        case "≤":
            return make("<=", consume: 1)
        case "≥":
            return make(">=", consume: 1)
        case "≠":
            return make("<>", consume: 1)
        default:
            // Any other character (stray high-Mac-Roman glyphs like ∞ • °, a
            // colon, etc.) becomes a lone symbol token rather than a hard
            // tokenizer failure. Such glyphs appear in decorative banners and
            // notes outside handlers, which the parser skips as loose text.
            return make(String(character), consume: 1)
        }
    }
}
