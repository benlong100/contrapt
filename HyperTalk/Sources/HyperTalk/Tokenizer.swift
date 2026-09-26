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

        if character.isLetter || character == "_" {
            return identifier()
        }

        return try symbol(character)
    }

    /// Straight or curly double quotes both delimit strings — iPad smart
    /// quotes (and scripts pasted from anywhere) must not break scripts.
    static func isQuote(_ character: Character) -> Bool {
        character == "\"" || character == "\u{201C}" || character == "\u{201D}"
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
        advance() // opening quote
        var text = ""
        while let character = current {
            if Self.isQuote(character) {
                advance()
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
        while let character = current, character.isLetter || character.isNumber || character == "_" {
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
