//
//  KitoAIStreamAssembler.swift
//  KitoAIChat
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// Turns streamed tokens into markdown blocks without flicker.
///
/// Rendering raw partial markdown makes blocks jump: a lone `#` shows as text and then becomes a
/// heading, `**bo` shows its asterisks until the closing pair arrives, and a table header shows as
/// a paragraph until its `|---|` row arrives. The assembler holds back the few characters that
/// could still change meaning and closes open inline markers, so every frame is a plausible,
/// stable rendering of what has arrived so far.
///
/// ```swift
/// var assembler = KitoAIStreamAssembler()
/// for try await token in stream { assembler.append(token); render(assembler.blocks) }
/// assembler.finish()
/// ```
public struct KitoAIStreamAssembler: Hashable, Sendable {
    /// Everything received so far.
    public private(set) var text: String
    public private(set) var isFinished: Bool

    public init(text: String = "", isFinished: Bool = false) {
        self.text = text
        self.isFinished = isFinished
    }

    public mutating func append(_ token: String) {
        text += token
    }

    /// Marks the stream as complete; nothing is held back after this.
    public mutating func finish() {
        isFinished = true
    }

    /// The text that is safe to render now.
    public var displayText: String { Self.displayText(for: text, isStreaming: !isFinished) }

    /// The blocks to render now.
    public var blocks: [KitoAIMarkdownBlock] { KitoAIMarkdown.blocks(from: displayText) }

    /// The renderable part of `text`. When `isStreaming` is false the text is returned unchanged.
    public static func displayText(for text: String, isStreaming: Bool) -> String {
        guard isStreaming, !text.isEmpty else { return text }
        var lines = KitoAIMarkdown.normalizedLines(text)
        let partial = lines.removeLast()
        let insideFence = isInsideFence(lines)
        var shown = lines
        var heldPartial = false

        if isAmbiguous(partial: partial, insideFence: insideFence) {
            heldPartial = true
        } else {
            shown.append(insideFence ? partial : closingOpenInlineMarkers(in: partial))
        }

        // A lone "| a | b |" line is a table header only if a "|---|" row follows it.
        let partialIsEmpty = heldPartial || partial.isEmpty
        if !insideFence, partialIsEmpty, let lastComplete = lines.last, KitoAIMarkdown.isTableRow(lastComplete) {
            let previous = lines.count >= 2 ? lines[lines.count - 2] : nil
            let isInTable = previous.map(KitoAIMarkdown.isTableRow) ?? false
            if !isInTable {
                let dropCount = heldPartial ? 1 : 2
                shown.removeLast(min(dropCount, shown.count))
            }
        }
        return shown.joined(separator: "\n")
    }

    /// True when the lines so far leave a code fence open.
    static func isInsideFence(_ lines: [String]) -> Bool {
        var open: (character: Character, length: Int)?
        for line in lines {
            if let current = open {
                if KitoAIMarkdown.closesFence(line, character: current.character, length: current.length) { open = nil }
            } else if let fence = KitoAIMarkdown.fenceOpening(line) {
                open = (fence.character, fence.length)
            }
        }
        return open != nil
    }

    /// Whether an unfinished last line could still turn into a different kind of block.
    static func isAmbiguous(partial: String, insideFence: Bool) -> Bool {
        let trimmed = KitoAIMarkdown.unindented(partial)
        guard let first = trimmed.first else { return false }
        if first == "`" || first == "~" {
            // A fence (or its closing line) until the line ends, so the language label doesn't flicker.
            let run = trimmed.prefix { $0 == first }.count
            return run == trimmed.count || run >= 3
        }
        if insideFence { return false }
        if trimmed.allSatisfy({ $0 == "#" }) { return true }
        if trimmed.allSatisfy({ "-*_+ ".contains($0) }) { return true }
        if trimmed == ">" { return true }
        if first == "|" { return true }
        let digits = trimmed.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty, digits.count <= 9 {
            let rest = trimmed.dropFirst(digits.count)
            return rest.isEmpty || rest == "." || rest == ")"
        }
        return false
    }

    /// Closes bold, italic, strikethrough and code spans left open at the end of a streamed line,
    /// and shows an unfinished link as its text. A marker with nothing after it yet is hidden.
    public static func closingOpenInlineMarkers(in line: String) -> String {
        let prefixLength = blockPrefixLength(of: line)
        let prefix = String(line.prefix(prefixLength))
        var body = hidingUnfinishedLink(in: String(line.dropFirst(prefixLength)))
        let open = openMarkers(in: body)
        for marker in open.reversed() {
            let characters = Array(body)
            let end = marker.offset + marker.token.count
            let after = end < characters.count ? String(characters[end...]) : ""
            if after.trimmingCharacters(in: .whitespaces).isEmpty {
                body = String(characters[..<marker.offset])
            } else {
                body = trimmingTrailingSpaces(body) + marker.token
            }
        }
        return prefix + body
    }

    private struct OpenMarker {
        let token: String
        let offset: Int
    }

    private static func openMarkers(in text: String) -> [OpenMarker] {
        let characters = Array(text)
        var stack: [OpenMarker] = []
        var index = 0
        var codeTicks = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\\" {
                index += 2
                continue
            }
            if character == "`" {
                let run = runLength(of: "`", in: characters, from: index)
                if codeTicks == 0 {
                    codeTicks = run
                    stack.append(OpenMarker(token: String(repeating: "`", count: run), offset: index))
                } else if run == codeTicks {
                    codeTicks = 0
                    stack.removeLast()
                }
                index += run
                continue
            }
            if codeTicks > 0 {
                index += 1
                continue
            }
            if let token = emphasisToken(in: characters, at: index) {
                if stack.last?.token == token {
                    stack.removeLast()
                } else {
                    stack.append(OpenMarker(token: token, offset: index))
                }
                index += token.count
                continue
            }
            index += 1
        }
        return stack
    }

    private static func emphasisToken(in characters: [Character], at index: Int) -> String? {
        let character = characters[index]
        if character == "*" {
            return runLength(of: "*", in: characters, from: index) >= 2 ? "**" : "*"
        }
        if character == "~", index + 1 < characters.count, characters[index + 1] == "~" {
            return "~~"
        }
        return nil
    }

    private static func runLength(of character: Character, in characters: [Character], from index: Int) -> Int {
        var end = index
        while end < characters.count, characters[end] == character { end += 1 }
        return end - index
    }

    private static func trimmingTrailingSpaces(_ text: String) -> String {
        var result = text
        while result.last == " " { result.removeLast() }
        return result
    }

    /// Length of a list marker, quote marker or heading hashes at the start of the line.
    private static func blockPrefixLength(of line: String) -> Int {
        let characters = Array(line)
        var index = 0
        while index < characters.count, characters[index] == " " { index += 1 }
        guard index < characters.count else { return index }
        let first = characters[index]
        if first == ">" || first == "#" {
            while index < characters.count, characters[index] == first { index += 1 }
            while index < characters.count, characters[index] == " " { index += 1 }
            return index
        }
        if "-*+".contains(first), index + 1 < characters.count, characters[index + 1] == " " {
            return index + 2
        }
        var digitsEnd = index
        while digitsEnd < characters.count, characters[digitsEnd].isASCII, characters[digitsEnd].isNumber { digitsEnd += 1 }
        let hasDelimiter = digitsEnd > index && digitsEnd + 1 < characters.count
            && (characters[digitsEnd] == "." || characters[digitsEnd] == ")") && characters[digitsEnd + 1] == " "
        return hasDelimiter ? digitsEnd + 2 : index
    }

    /// `"see [the docs](https://exa"` → `"see the docs"`, `"see [the do"` → `"see the do"`.
    private static func hidingUnfinishedLink(in text: String) -> String {
        guard let open = text.lastIndex(of: "[") else { return text }
        let tail = text[text.index(after: open)...]
        let prefix = text[..<open].hasSuffix("!") ? text[..<text.index(before: open)] : text[..<open]
        guard let close = tail.firstIndex(of: "]") else {
            return String(prefix + tail)
        }
        let label = tail[..<close]
        let afterClose = tail[tail.index(after: close)...]
        if afterClose.isEmpty { return String(prefix + label) }
        guard afterClose.first == "(" else { return text }
        if afterClose.contains(")") { return text }
        return String(prefix + label)
    }
}
