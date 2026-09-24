//
//  KitoAIMarkdownView.swift
//  KitoAIChat
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// Renders markdown the way assistants write it: headings, paragraphs, bullet, numbered and task
/// lists, block quotes, tables, rules and fenced code, with bold, italic, `code`, ~~strike~~ and
/// links inline. While `isStreaming`, unfinished syntax is held back so nothing flickers, and a
/// cursor follows the text.
///
/// ```swift
/// KitoAIMarkdownView(reply)
/// KitoAIMarkdownView(partialReply, isStreaming: true)
/// ```
public struct KitoAIMarkdownView: View {
    private let markdown: String
    private let isStreaming: Bool
    private let tint: Color?

    @Environment(\.kitoTheme) private var theme

    public init(_ markdown: String, isStreaming: Bool = false, tint: Color? = nil) {
        self.markdown = markdown
        self.isStreaming = isStreaming
        self.tint = tint
    }

    public var body: some View {
        let blocks = KitoAIMarkdown.blocks(from: KitoAIStreamAssembler.displayText(for: markdown, isStreaming: isStreaming))
        let accent = tint ?? theme.colors.primary
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                KitoAIMarkdownBlockView(block: block, showsCursor: isStreaming && index == blocks.count - 1, accent: accent)
                    .equatable()
            }
            if isStreaming && blocks.isEmpty {
                KitoAIStreamingCursor(tint: accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One markdown block.
struct KitoAIMarkdownBlockView: View, Equatable {
    let block: KitoAIMarkdownBlock
    let showsCursor: Bool
    let accent: Color

    @Environment(\.kitoTheme) private var theme

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.block == rhs.block && lhs.showsCursor == rhs.showsCursor && lhs.accent == rhs.accent
    }

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text, cursor: showsCursor))
                .font(headingFont(level))
                .foregroundStyle(theme.colors.onSurface)
                .padding(.top, level <= 2 ? theme.spacing.xs : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            paragraph(text)
        case .list(let items):
            KitoAIMarkdownListView(items: items, showsCursor: showsCursor, accent: accent)
        case .quote(let text):
            quote(text)
        case .code(let language, let code, _):
            KitoAICodeBlock(code, language: language, isStreaming: showsCursor, tint: accent)
        case .table(let table):
            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                KitoAITableView(table: table, accent: accent)
                if showsCursor { KitoAIStreamingCursor(tint: accent) }
            }
        case .rule:
            Rectangle()
                .fill(theme.colors.border)
                .frame(height: 1)
                .padding(.vertical, theme.spacing.xs)
                .accessibilityHidden(true)
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(inline(text, cursor: showsCursor))
            .font(theme.typography.body)
            .foregroundStyle(theme.colors.onSurface)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func quote(_ text: String) -> some View {
        Text(inline(text, cursor: showsCursor))
            .font(theme.typography.body)
            .foregroundStyle(theme.colors.onSurface.opacity(0.8))
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, theme.spacing.sm)
            .padding(.leading, theme.spacing.lg)
            .padding(.trailing, theme.spacing.md)
            .background(
                RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous)
                    .fill(accent.opacity(0.07))
            )
            .overlay(alignment: .leading) {
                Capsule().fill(accent.opacity(0.7)).frame(width: 3).padding(.vertical, theme.spacing.xs)
            }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return theme.typography.titleLarge
        case 2: return theme.typography.titleMedium
        default: return theme.typography.bodyEmphasized.weight(.semibold)
        }
    }

    private func inline(_ text: String, cursor: Bool) -> AttributedString {
        KitoAIInlineMarkdown.attributed(text, theme: theme, accent: accent, cursor: cursor)
    }
}

/// Inline markdown → `AttributedString`, with themed code spans and links.
enum KitoAIInlineMarkdown {
    static func attributed(_ text: String, theme: KitoTheme, accent: Color, cursor: Bool = false) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        var result = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        var codeRanges: [Range<AttributedString.Index>] = []
        var linkRanges: [Range<AttributedString.Index>] = []
        for run in result.runs {
            if run.inlinePresentationIntent?.contains(.code) == true { codeRanges.append(run.range) }
            if run.link != nil { linkRanges.append(run.range) }
        }
        for range in codeRanges {
            result[range].font = .system(.callout, design: .monospaced)
            result[range].backgroundColor = theme.colors.surfaceMuted
            result[range].foregroundColor = theme.colors.onSurface
        }
        for range in linkRanges {
            result[range].foregroundColor = accent
            result[range].underlineStyle = .single
        }
        if cursor {
            var dot = AttributedString(" ●")
            dot.foregroundColor = accent
            dot.font = .system(.caption)
            result += dot
        }
        return result
    }
}

/// Bullet, numbered and task lists, nested by indentation.
struct KitoAIMarkdownListView: View {
    let items: [KitoAIMarkdownListItem]
    let showsCursor: Bool
    let accent: Color

    @Environment(\.kitoTheme) private var theme

    var body: some View {
        let markers = Self.markers(for: items)
        VStack(alignment: .leading, spacing: theme.spacing.xs + 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: theme.spacing.sm) {
                    marker(for: item, text: markers[index])
                    Text(KitoAIInlineMarkdown.attributed(item.text, theme: theme, accent: accent, cursor: showsCursor && index == items.count - 1))
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.onSurface)
                        .strikethrough(item.isChecked == true, color: theme.colors.onSurface.opacity(0.4))
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, indent(for: item))
            }
        }
    }

    @ViewBuilder
    private func marker(for item: KitoAIMarkdownListItem, text: String) -> some View {
        if let checked = item.isChecked {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(theme.typography.body)
                .foregroundStyle(checked ? accent : theme.colors.onSurface.opacity(0.45))
                .accessibilityLabel(checked ? "Done" : "Not done")
        } else if item.isOrdered {
            Text(text)
                .font(theme.typography.body.monospacedDigit())
                .foregroundStyle(theme.colors.onSurface.opacity(0.6))
                .frame(minWidth: 18, alignment: .trailing)
        } else {
            Text(text)
                .font(theme.typography.body.weight(.bold))
                .foregroundStyle(accent.opacity(0.85))
                .frame(minWidth: 10)
                .accessibilityHidden(true)
        }
    }

    private func indent(for item: KitoAIMarkdownListItem) -> CGFloat {
        CGFloat(min(item.level, 4)) * 20
    }

    /// "1.", "2.", … numbered per level (restarting under each parent), "•", "◦", "▪" for bullets.
    static func markers(for items: [KitoAIMarkdownListItem]) -> [String] {
        var counters: [Int: Int] = [:]
        var markers: [String] = []
        var previousLevel = 0
        for item in items {
            if item.level < previousLevel {
                counters = counters.filter { $0.key <= item.level }
            }
            previousLevel = item.level
            if let number = item.number {
                let next = counters[item.level].map { $0 + 1 } ?? number
                counters[item.level] = next
                markers.append("\(next).")
            } else {
                let bullets = ["•", "◦", "▪"]
                markers.append(bullets[item.level % bullets.count])
            }
        }
        return markers
    }
}

/// A GitHub-style table with a tinted header and striped rows; scrolls sideways when wide.
struct KitoAITableView: View {
    let table: KitoAIMarkdownTable
    let accent: Color

    @Environment(\.kitoTheme) private var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { column, text in
                        cell(text, column: column, row: -1)
                            .gridColumnAlignment(horizontal(for: column))
                    }
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { row, cells in
                    separator
                    GridRow {
                        ForEach(Array(cells.enumerated()), id: \.offset) { column, text in
                            cell(text, column: column, row: row)
                        }
                    }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous).fill(theme.colors.surface))
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous).strokeBorder(theme.colors.border, lineWidth: 0.75))
    }

    private var separator: some View {
        Rectangle()
            .fill(theme.colors.border.opacity(0.7))
            .frame(height: 0.5)
            .gridCellUnsizedAxes(.horizontal)
    }

    private func cell(_ text: String, column: Int, row: Int) -> some View {
        let isHeader = row < 0
        return Text(KitoAIInlineMarkdown.attributed(text, theme: theme, accent: accent))
            .font(isHeader ? theme.typography.label.weight(.semibold) : theme.typography.label.weight(.regular))
            .foregroundStyle(theme.colors.onSurface.opacity(isHeader ? 1 : 0.9))
            .multilineTextAlignment(textAlignment(for: column))
            .frame(minWidth: 56, maxWidth: 240, alignment: frameAlignment(for: column))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, theme.spacing.md)
            .padding(.vertical, theme.spacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment(for: column))
            .background(background(isHeader: isHeader, row: row))
    }

    private func background(isHeader: Bool, row: Int) -> Color {
        if isHeader { return accent.opacity(0.1) }
        return row % 2 == 1 ? theme.colors.surfaceMuted.opacity(0.55) : .clear
    }

    private func alignment(for column: Int) -> KitoAIMarkdownTable.Alignment {
        column < table.alignments.count ? table.alignments[column] : .leading
    }

    private func horizontal(for column: Int) -> HorizontalAlignment {
        switch alignment(for: column) {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func frameAlignment(for column: Int) -> Alignment {
        switch alignment(for: column) {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func textAlignment(for column: Int) -> TextAlignment {
        switch alignment(for: column) {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}
