//
//  KitoAICodeBlock.swift
//  KitoAIChat
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import UIKit
import KitoCore

/// A fenced code block: a header with the language and a Copy button, then monospaced,
/// syntax-coloured code that scrolls sideways instead of wrapping.
///
/// ```swift
/// KitoAICodeBlock("let greeting = \"Habari\"", language: "swift")
/// ```
public struct KitoAICodeBlock: View {
    private let code: String
    private let language: String?
    private let isStreaming: Bool
    private let tint: Color?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false
    @State private var copyCount = 0

    /// - Parameter isStreaming: shows a cursor after the last character.
    public init(_ code: String, language: String? = nil, isStreaming: Bool = false, tint: Color? = nil) {
        self.code = code
        self.language = language
        self.isStreaming = isStreaming
        self.tint = tint
    }

    private var displayCode: String {
        guard isStreaming, code.hasSuffix("\n") else { return code }
        return String(code.dropLast())
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(theme.colors.border.opacity(0.6)).frame(height: 0.5)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(highlighted)
                    .font(.system(.footnote, design: .monospaced))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(theme.spacing.md)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous).fill(theme.colors.surfaceMuted))
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous).strokeBorder(theme.colors.border.opacity(0.7), lineWidth: 0.5))
        .sensoryFeedback(.success, trigger: copyCount)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Code\(language.map { ", \($0)" } ?? "")")
        .accessibilityValue(displayCode)
        .accessibilityAction(named: "Copy code") { copy() }
    }

    private var header: some View {
        HStack(spacing: theme.spacing.sm) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.caption2.weight(.bold))
            Text(language?.lowercased() ?? "code")
                .font(theme.typography.caption.weight(.semibold))
            Spacer(minLength: theme.spacing.sm)
            Button(action: copy) {
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                    Text(copied ? "Copied" : "Copy")
                }
                .font(theme.typography.caption.weight(.semibold))
                .padding(.horizontal, theme.spacing.sm)
                .padding(.vertical, theme.spacing.xs)
                .background(Capsule().fill(copied ? theme.colors.success.opacity(0.16) : theme.colors.surface.opacity(0.8)))
                .foregroundStyle(copied ? theme.colors.success : theme.colors.onSurface.opacity(0.8))
            }
            .buttonStyle(KitoAIPressableStyle())
            .disabled(isStreaming)
            .opacity(isStreaming ? 0.4 : 1)
            .accessibilityLabel(copied ? "Code copied" : "Copy code")
        }
        .foregroundStyle(theme.colors.onSurface.opacity(0.6))
        .padding(.leading, theme.spacing.md)
        .padding(.trailing, theme.spacing.sm)
        .padding(.vertical, theme.spacing.xs + 2)
        .background(theme.colors.border.opacity(0.22))
    }

    private var highlighted: AttributedString {
        var result = AttributedString()
        for token in KitoAISyntaxHighlighter.tokens(in: displayCode, language: language) {
            var piece = AttributedString(token.text)
            piece.foregroundColor = color(for: token.kind)
            result += piece
        }
        if isStreaming {
            var cursor = AttributedString(" ▍")
            cursor.foregroundColor = tint ?? theme.colors.primary
            result += cursor
        }
        return result
    }

    private func color(for kind: KitoAISyntaxKind) -> Color {
        let dark = colorScheme == .dark
        switch kind {
        case .plain: return theme.colors.onSurface
        case .keyword: return dark ? Color(red: 0.99, green: 0.47, blue: 0.72) : Color(red: 0.66, green: 0.13, blue: 0.53)
        case .string: return dark ? Color(red: 0.99, green: 0.55, blue: 0.43) : Color(red: 0.77, green: 0.21, blue: 0.13)
        case .comment: return theme.colors.onSurface.opacity(0.45)
        case .number: return dark ? Color(red: 0.82, green: 0.75, blue: 0.47) : Color(red: 0.11, green: 0.36, blue: 0.84)
        case .type: return dark ? Color(red: 0.36, green: 0.85, blue: 0.87) : Color(red: 0.07, green: 0.47, blue: 0.53)
        case .function: return dark ? Color(red: 0.55, green: 0.73, blue: 1.0) : Color(red: 0.24, green: 0.33, blue: 0.78)
        }
    }

    private func copy() {
        UIPasteboard.general.string = displayCode
        copyCount += 1
        withAnimation(KitoAIMotion.snappy(reduceMotion)) { copied = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation(KitoAIMotion.snappy(reduceMotion)) { copied = false }
        }
    }
}
