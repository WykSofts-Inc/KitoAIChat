//
//  KitoAIMarkdown.swift
//  KitoAIChat
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// One item of a markdown list.
public struct KitoAIMarkdownListItem: Hashable, Sendable {
    /// Inline markdown.
    public var text: String
    /// 0 for top-level items; nested items count up by indentation.
    public var level: Int
    /// The number as written for ordered items; nil for bullets.
    public var number: Int?
    /// `true`/`false` for task items (`- [x]` / `- [ ]`), nil otherwise.
    public var isChecked: Bool?

    public init(text: String, level: Int = 0, number: Int? = nil, isChecked: Bool? = nil) {
        self.text = text
        self.level = level
        self.number = number
        self.isChecked = isChecked
    }

    public var isOrdered: Bool { number != nil }
}

/// A GitHub-style table.
public struct KitoAIMarkdownTable: Hashable, Sendable {
    public enum Alignment: Hashable, Sendable { case leading, center, trailing }

    public var header: [String]
    public var alignments: [Alignment]
    /// Every row has exactly `header.count` cells.
    public var rows: [[String]]

    public init(header: [String], alignments: [Alignment], rows: [[String]]) {
        self.header = header
        self.alignments = alignments
        self.rows = rows
    }
}

/// A block of markdown. Inline styles (bold, italic, `code`, links, ~~strike~~) stay in the text.
public enum KitoAIMarkdownBlock: Hashable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list([KitoAIMarkdownListItem])
    case quote(String)
    /// `isClosed` is false while a streamed fence hasn't been closed yet.
    case code(language: String?, code: String, isClosed: Bool)
    case table(KitoAIMarkdownTable)
    case rule

    /// A short name for the kind of block — handy in tests and logs.
    public var kind: String {
        switch self {
        case .heading: return "heading"
        case .paragraph: return "paragraph"
        case .list: return "list"
        case .quote: return "quote"
        case .code: return "code"
        case .table: return "table"
        case .rule: return "rule"
        }
    }
}

/// Splits markdown into blocks: headings, paragraphs, lists (nested, ordered, task), block quotes,
/// fenced code, tables and rules. Pure and fast enough to run on every streamed token.
public enum KitoAIMarkdown {

    public static func blocks(from markdown: String) -> [KitoAIMarkdownBlock] {
        var parser = Parser(lines: normalizedLines(markdown))
        return parser.run()
    }

    /// The text with markdown syntax removed — for previews, titles and VoiceOver.
    public static func plainText(_ markdown: String) -> String {
        let lines = blocks(from: markdown).map { block -> String in
            switch block {
            case .heading(_, let text), .paragraph(let text), .quote(let text):
                return stripInline(text)
            case .list(let items):
                return items.map { stripInline($0.text) }.joined(separator: "\n")
            case .code(_, let code, _):
                return code
            case .table(let table):
                return ([table.header] + table.rows).map { $0.map(stripInline).joined(separator: ", ") }.joined(separator: "\n")
            case .rule:
                return ""
            }
        }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Removes inline markers: `**`, `*`, `` ` ``, `~~`, and turns `[text](url)` into `text`.
    public static func stripInline(_ text: String) -> String {
        var result = replacingLinks(in: text)
        for marker in ["**", "__", "~~", "`", "*"] {
            result = result.replacingOccurrences(of: marker, with: "")
        }
        return result
    }

    static func normalizedLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    }

    static func replacingLinks(in text: String) -> String {
        var result = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "[") {
            guard let close = rest[open...].firstIndex(of: "]"),
                  rest.index(after: close) < rest.endIndex,
                  rest[rest.index(after: close)] == "(",
                  let end = rest[close...].firstIndex(of: ")") else {
                break
            }
            var prefix = rest[..<open]
            if prefix.hasSuffix("!") { prefix = prefix.dropLast() }
            result += prefix
            result += rest[rest.index(after: open)..<close]
            rest = rest[rest.index(after: end)...]
        }
        return result + rest
    }

    // MARK: Line classification (shared with the stream assembler)

    /// The line without up to three spaces of indentation.
    static func unindented(_ line: String) -> Substring {
        var slice = Substring(line)
        var count = 0
        while count < 3, slice.first == " " {
            slice = slice.dropFirst()
            count += 1
        }
        return slice
    }

    static func indentation(of line: String) -> Int {
        var width = 0
        for character in line {
            if character == " " { width += 1 } else if character == "\t" { width += 4 } else { break }
        }
        return width
    }

    /// `("`", 3, "swift")` for a line opening a fence.
    static func fenceOpening(_ line: String) -> (character: Character, length: Int, info: String)? {
        let trimmed = unindented(line)
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let run = trimmed.prefix { $0 == first }.count
        guard run >= 3 else { return nil }
        let info = trimmed.dropFirst(run).trimmingCharacters(in: .whitespaces)
        if first == "`", info.contains("`") { return nil }
        return (first, run, info)
    }

    static func closesFence(_ line: String, character: Character, length: Int) -> Bool {
        let trimmed = unindented(line)
        let run = trimmed.prefix { $0 == character }.count
        guard run >= length else { return false }
        return trimmed.dropFirst(run).allSatisfy { $0 == " " || $0 == "\t" }
    }

    static func heading(_ line: String) -> (level: Int, text: String)? {
        let trimmed = unindented(line)
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = trimmed.dropFirst(hashes)
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("#") { text.removeLast() }
        return (hashes, text.trimmingCharacters(in: .whitespaces))
    }

    static func isRule(_ line: String) -> Bool {
        let compact = unindented(line).filter { $0 != " " && $0 != "\t" }
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    static func listItem(_ line: String) -> KitoAIMarkdownListItem? {
        let indent = indentation(of: line)
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        var number: Int?
        var rest: Substring
        if let first = trimmed.first, "-*+".contains(first) {
            rest = trimmed.dropFirst()
        } else {
            let digits = trimmed.prefix { $0.isASCII && $0.isNumber }
            guard (1...9).contains(digits.count) else { return nil }
            let afterDigits = trimmed.dropFirst(digits.count)
            guard let delimiter = afterDigits.first, delimiter == "." || delimiter == ")" else { return nil }
            number = Int(digits)
            rest = afterDigits.dropFirst()
        }
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        var checked: Bool?
        if text.hasPrefix("[ ] ") || text == "[ ]" {
            checked = false
            text = String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        } else if text.lowercased().hasPrefix("[x] ") || text.lowercased() == "[x]" {
            checked = true
            text = String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        }
        return KitoAIMarkdownListItem(text: text, level: indent / 2, number: number, isChecked: checked)
    }

    static func isQuote(_ line: String) -> Bool { unindented(line).first == ">" }

    static func quoteContent(_ line: String) -> String {
        var rest = unindented(line).dropFirst()
        if rest.first == " " { rest = rest.dropFirst() }
        return String(rest)
    }

    static func isTableRow(_ line: String) -> Bool { unindented(line).first == "|" }

    static func tableCells(_ line: String) -> [String] {
        var row = line.trimmingCharacters(in: .whitespaces)
        if row.hasPrefix("|") { row.removeFirst() }
        if row.hasSuffix("|"), !row.hasSuffix("\\|") { row.removeLast() }
        var cells: [String] = []
        var current = ""
        var previous: Character?
        for character in row {
            if character == "|", previous != "\\" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
            previous = character
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells.map { $0.replacingOccurrences(of: "\\|", with: "|") }
    }

    static func tableAlignments(_ line: String) -> [KitoAIMarkdownTable.Alignment]? {
        guard isTableRow(line) else { return nil }
        let cells = tableCells(line)
        var alignments: [KitoAIMarkdownTable.Alignment] = []
        for cell in cells {
            let dashes = cell.filter { $0 == "-" }.count
            guard dashes >= 1, cell.allSatisfy({ $0 == "-" || $0 == ":" }) else { return nil }
            let leading = cell.hasPrefix(":")
            let trailing = cell.hasSuffix(":")
            if leading && trailing { alignments.append(.center) } else if trailing { alignments.append(.trailing) } else { alignments.append(.leading) }
        }
        return alignments
    }

    // MARK: Parser

    private struct Parser {
        let lines: [String]
        var index = 0
        var blocks: [KitoAIMarkdownBlock] = []
        var paragraph: [String] = []
        var listItems: [KitoAIMarkdownListItem] = []
        var listIsOrdered = false
        var sawBlankInList = false

        init(lines: [String]) { self.lines = lines }

        mutating func run() -> [KitoAIMarkdownBlock] {
            while index < lines.count {
                let line = lines[index]
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    flushParagraph()
                    if !listItems.isEmpty { sawBlankInList = true }
                    index += 1
                    continue
                }
                if handleBlockStart(line) { continue }
                if handleListLine(line) { continue }
                flushList()
                paragraph.append(line.trimmingCharacters(in: .whitespaces))
                index += 1
            }
            flushParagraph()
            flushList()
            return blocks
        }

        /// Fences, headings, rules, quotes and tables. Returns true when it consumed lines.
        mutating func handleBlockStart(_ line: String) -> Bool {
            if let fence = KitoAIMarkdown.fenceOpening(line) {
                flushAll()
                parseFence(fence, indent: KitoAIMarkdown.indentation(of: line))
                return true
            }
            if let heading = KitoAIMarkdown.heading(line) {
                flushAll()
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                return true
            }
            if KitoAIMarkdown.isRule(line) {
                flushAll()
                blocks.append(.rule)
                index += 1
                return true
            }
            if KitoAIMarkdown.isQuote(line) {
                flushAll()
                var quoted: [String] = []
                while index < lines.count, KitoAIMarkdown.isQuote(lines[index]) {
                    quoted.append(KitoAIMarkdown.quoteContent(lines[index]))
                    index += 1
                }
                blocks.append(.quote(quoted.joined(separator: "\n")))
                return true
            }
            if KitoAIMarkdown.isTableRow(line), index + 1 < lines.count,
               let alignments = KitoAIMarkdown.tableAlignments(lines[index + 1]) {
                flushAll()
                parseTable(header: KitoAIMarkdown.tableCells(line), alignments: alignments)
                return true
            }
            return false
        }

        /// List items and their indented continuation lines.
        mutating func handleListLine(_ line: String) -> Bool {
            if let item = KitoAIMarkdown.listItem(line) {
                flushParagraph()
                let startsNewList = listItems.isEmpty || (item.level == 0 && item.isOrdered != listIsOrdered)
                if startsNewList {
                    flushList()
                    listIsOrdered = item.isOrdered
                }
                listItems.append(item)
                sawBlankInList = false
                index += 1
                return true
            }
            if !listItems.isEmpty, KitoAIMarkdown.indentation(of: line) >= 2, paragraph.isEmpty {
                let continuation = line.trimmingCharacters(in: .whitespaces)
                let last = listItems.count - 1
                let separator = sawBlankInList ? "\n" : " "
                listItems[last].text += listItems[last].text.isEmpty ? continuation : separator + continuation
                sawBlankInList = false
                index += 1
                return true
            }
            return false
        }

        mutating func parseFence(_ fence: (character: Character, length: Int, info: String), indent: Int) {
            index += 1
            var code: [String] = []
            var closed = false
            while index < lines.count {
                let line = lines[index]
                if KitoAIMarkdown.closesFence(line, character: fence.character, length: fence.length) {
                    closed = true
                    index += 1
                    break
                }
                code.append(Self.removingIndent(indent, from: line))
                index += 1
            }
            let language = fence.info.split(separator: " ").first.map(String.init)
            blocks.append(.code(language: language?.isEmpty == false ? language : nil, code: code.joined(separator: "\n"), isClosed: closed))
        }

        mutating func parseTable(header: [String], alignments: [KitoAIMarkdownTable.Alignment]) {
            index += 2
            let columns = header.count
            var rows: [[String]] = []
            while index < lines.count, KitoAIMarkdown.isTableRow(lines[index]) {
                rows.append(Self.fitted(KitoAIMarkdown.tableCells(lines[index]), to: columns))
                index += 1
            }
            let fittedAlignments = Array((alignments + Array(repeating: .leading, count: columns)).prefix(columns))
            blocks.append(.table(KitoAIMarkdownTable(header: header, alignments: fittedAlignments, rows: rows)))
        }

        static func fitted(_ cells: [String], to count: Int) -> [String] {
            if cells.count >= count { return Array(cells.prefix(count)) }
            return cells + Array(repeating: "", count: count - cells.count)
        }

        static func removingIndent(_ indent: Int, from line: String) -> String {
            var slice = Substring(line)
            var removed = 0
            while removed < indent, slice.first == " " {
                slice = slice.dropFirst()
                removed += 1
            }
            return String(slice)
        }

        mutating func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }

        mutating func flushList() {
            guard !listItems.isEmpty else { return }
            blocks.append(.list(listItems))
            listItems.removeAll()
            sawBlankInList = false
        }

        mutating func flushAll() {
            flushParagraph()
            flushList()
        }
    }
}
