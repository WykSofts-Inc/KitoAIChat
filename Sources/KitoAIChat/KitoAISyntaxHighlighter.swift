//
//  KitoAISyntaxHighlighter.swift
//  KitoAIChat
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// What a piece of code is, for colouring.
public enum KitoAISyntaxKind: Hashable, Sendable {
    case plain, keyword, string, comment, number, type, function
}

/// A run of code of one kind.
public struct KitoAISyntaxToken: Hashable, Sendable {
    public var text: String
    public var kind: KitoAISyntaxKind

    public init(_ text: String, _ kind: KitoAISyntaxKind) {
        self.text = text
        self.kind = kind
    }
}

/// A small, forgiving highlighter for the languages models write most: Swift, Kotlin, JavaScript
/// and TypeScript, Python, Go, Rust, Java, C-family, JSON, shell, SQL and YAML. It never fails —
/// unknown languages get strings, numbers and comments — and the tokens always join back into the
/// original code.
public enum KitoAISyntaxHighlighter {
    public static func tokens(in code: String, language: String?) -> [KitoAISyntaxToken] {
        var scanner = Scanner(characters: Array(code), family: Family(language))
        return scanner.run()
    }

    enum Family {
        case cLike, hash, sql, json, markup

        init(_ language: String?) {
            switch language?.lowercased() ?? "" {
            case "python", "py", "ruby", "rb", "bash", "sh", "shell", "zsh", "console", "yaml", "yml", "toml", "r", "perl", "dockerfile", "makefile", "elixir":
                self = .hash
            case "sql", "postgres", "postgresql", "mysql", "sqlite":
                self = .sql
            case "json", "jsonc":
                self = .json
            case "html", "xml", "svg", "markdown", "md", "text", "txt", "plaintext":
                self = .markup
            default:
                self = .cLike
            }
        }
    }

    static let keywords: Set<String> = [
        // Swift, Kotlin, Java, C-family
        "actor", "associatedtype", "async", "await", "break", "case", "catch", "class", "continue", "default", "defer",
        "do", "else", "enum", "extension", "fallthrough", "false", "fileprivate", "final", "for", "func", "guard", "if",
        "import", "in", "init", "inout", "internal", "is", "let", "nil", "open", "operator", "override", "private",
        "protocol", "public", "repeat", "rethrows", "return", "self", "Self", "some", "any", "static", "struct", "subscript",
        "super", "switch", "throw", "throws", "true", "try", "typealias", "var", "where", "while", "mutating", "weak",
        "lazy", "fun", "val", "object", "when", "data", "sealed", "companion", "new", "this", "void", "null", "extends",
        "implements", "interface", "package", "abstract", "const", "volatile", "int", "char", "float", "double", "long",
        "bool", "boolean", "unsigned", "sizeof", "typedef", "goto",
        // JavaScript / TypeScript
        "function", "export", "from", "of", "typeof", "instanceof", "undefined", "yield", "delete", "type", "readonly",
        "keyof", "declare", "namespace", "constructor", "get", "set",
        // Python
        "def", "elif", "except", "finally", "lambda", "not", "and", "or", "pass", "raise", "with", "as", "None", "True",
        "False", "global", "nonlocal", "assert", "del",
        // Go / Rust
        "go", "chan", "select", "map", "range", "fn", "impl", "mod", "pub", "use", "crate", "trait", "match", "loop",
        "mut", "ref", "move", "unsafe", "dyn",
        // Shell
        "then", "fi", "esac", "done", "echo", "local", "source",
    ]

    static let sqlKeywords: Set<String> = [
        "select", "from", "where", "and", "or", "not", "insert", "into", "values", "update", "set", "delete", "create",
        "table", "index", "on", "join", "left", "right", "inner", "outer", "group", "by", "order", "limit", "as",
        "having", "distinct", "null", "is", "in", "primary", "key", "foreign", "references", "default", "count", "sum",
    ]

    private struct Scanner {
        let characters: [Character]
        let family: Family
        var index = 0
        var tokens: [KitoAISyntaxToken] = []

        init(characters: [Character], family: Family) {
            self.characters = characters
            self.family = family
        }

        mutating func run() -> [KitoAISyntaxToken] {
            guard family != .markup else { return characters.isEmpty ? [] : [KitoAISyntaxToken(String(characters), .plain)] }
            while index < characters.count {
                if scanComment() || scanString() || scanNumber() || scanWord() { continue }
                emit(String(characters[index]), .plain)
                index += 1
            }
            return tokens
        }

        func peek(_ offset: Int = 0) -> Character? {
            let position = index + offset
            return position < characters.count ? characters[position] : nil
        }

        mutating func emit(_ text: String, _ kind: KitoAISyntaxKind) {
            guard !text.isEmpty else { return }
            if let last = tokens.last, last.kind == kind, kind == .plain {
                tokens[tokens.count - 1].text += text
            } else {
                tokens.append(KitoAISyntaxToken(text, kind))
            }
        }

        mutating func take(while condition: (Character) -> Bool) -> String {
            let start = index
            while index < characters.count, condition(characters[index]) { index += 1 }
            return String(characters[start..<index])
        }

        mutating func scanComment() -> Bool {
            let current = peek()
            let next = peek(1)
            let lineComment: Bool
            switch family {
            case .cLike: lineComment = current == "/" && next == "/"
            case .hash: lineComment = current == "#"
            case .sql: lineComment = current == "-" && next == "-"
            case .json, .markup: lineComment = false
            }
            if lineComment {
                emit(take { $0 != "\n" }, .comment)
                return true
            }
            if family == .cLike || family == .sql, current == "/", next == "*" {
                let start = index
                index += 2
                while index < characters.count, !(characters[index] == "*" && peek(1) == "/") { index += 1 }
                index = min(characters.count, index + 2)
                emit(String(characters[start..<index]), .comment)
                return true
            }
            return false
        }

        mutating func scanString() -> Bool {
            guard let quote = peek(), quote == "\"" || quote == "'" || (quote == "`" && family == .cLike) else { return false }
            let start = index
            index += 1
            while index < characters.count {
                let character = characters[index]
                if character == "\\" {
                    index += 2
                    continue
                }
                index += 1
                if character == quote { break }
                if character == "\n", quote != "`" { break }
            }
            index = min(index, characters.count)
            emit(String(characters[start..<index]), .string)
            return true
        }

        mutating func scanNumber() -> Bool {
            guard let current = peek(), current.isASCII, current.isNumber else { return false }
            if let previous = tokens.last?.text.last, previous.isLetter || previous == "_" { return false }
            emit(take { $0.isASCII && ($0.isHexDigit || $0 == "." || $0 == "_" || $0 == "x" || $0 == "o" || $0 == "b") }, .number)
            return true
        }

        mutating func scanWord() -> Bool {
            guard let current = peek(), current.isLetter || current == "_" || current == "@" || current == "$" else { return false }
            let start = index
            index += 1
            while index < characters.count, characters[index].isLetter || characters[index].isNumber || characters[index] == "_" { index += 1 }
            let word = String(characters[start..<index])
            emit(word, kind(of: word))
            return true
        }

        func kind(of word: String) -> KitoAISyntaxKind {
            switch family {
            case .sql:
                return KitoAISyntaxHighlighter.sqlKeywords.contains(word.lowercased()) ? .keyword : .plain
            case .json:
                return ["true", "false", "null"].contains(word) ? .keyword : .plain
            default:
                if word.hasPrefix("@") { return .keyword }
                if KitoAISyntaxHighlighter.keywords.contains(word) { return .keyword }
                if peek() == "(" { return .function }
                if let first = word.first, first.isUppercase { return .type }
                return .plain
            }
        }
    }
}
