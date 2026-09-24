//
//  KitoAIChips.swift
//  KitoAIChat
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

// MARK: - Tool call

/// A tool the assistant is using: a spinner and a light sweep while it runs ("Searching the
/// web…"), a tick and its result once it's done ("Searched the web · 4 sources").
///
/// ```swift
/// KitoAIToolChip(.webSearch(query: "Diani weekend"))
/// ```
public struct KitoAIToolChip: View {
    private let call: KitoAIToolCall
    private let tint: Color?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ call: KitoAIToolCall, tint: Color? = nil) {
        self.call = call
        self.tint = tint
    }

    private var accent: Color { tint ?? theme.colors.primary }

    public var body: some View {
        HStack(spacing: theme.spacing.sm) {
            statusIcon
                .frame(width: 18, height: 18)
            Image(systemName: call.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
            Text(call.title)
                .font(theme.typography.label)
                .foregroundStyle(theme.colors.onSurface.opacity(call.status == .running ? 0.75 : 0.9))
                .kitoAIShimmer(call.status == .running)
                .contentTransition(.opacity)
            if let detail = call.detail, call.status != .running {
                Text("· \(detail)")
                    .font(theme.typography.label)
                    .foregroundStyle(theme.colors.onSurface.opacity(0.5))
                    .lineLimit(1)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .padding(.leading, theme.spacing.sm)
        .padding(.trailing, theme.spacing.md)
        .padding(.vertical, theme.spacing.xs + 2)
        .background(Capsule().fill(theme.colors.surfaceMuted))
        .overlay(Capsule().strokeBorder(borderColor, lineWidth: 0.75))
        .animation(KitoAIMotion.spring(reduceMotion), value: call.status)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([call.title, call.status == .running ? nil : call.detail].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(call.status == .running ? .updatesFrequently : [])
    }

    private var borderColor: Color {
        switch call.status {
        case .running: return accent.opacity(0.35)
        case .done: return theme.colors.border.opacity(0.8)
        case .failed: return theme.colors.danger.opacity(0.4)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch call.status {
        case .running:
            ProgressView()
                .controlSize(.mini)
                .tint(accent)
                .transition(.scale.combined(with: .opacity))
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.colors.success)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.colors.danger)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
        }
    }
}

// MARK: - Citations

/// Numbered source chips that open their link.
///
/// ```swift
/// KitoAICitationChips(message.citations)
/// ```
public struct KitoAICitationChips: View {
    private let citations: [KitoAICitation]
    private let tint: Color?
    private let onSelect: ((KitoAICitation) -> Void)?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.openURL) private var openURL

    /// - Parameter onSelect: called instead of opening the link.
    public init(_ citations: [KitoAICitation], tint: Color? = nil, onSelect: ((KitoAICitation) -> Void)? = nil) {
        self.citations = citations
        self.tint = tint
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs + 2) {
            Label("Sources", systemImage: "books.vertical")
                .font(theme.typography.caption.weight(.semibold))
                .foregroundStyle(theme.colors.onSurface.opacity(0.55))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.spacing.sm) {
                    ForEach(Array(citations.enumerated()), id: \.element.id) { index, citation in
                        chip(citation, number: index + 1)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func chip(_ citation: KitoAICitation, number: Int) -> some View {
        let accent = tint ?? theme.colors.primary
        return Button {
            if let onSelect { onSelect(citation) } else if let url = citation.url { openURL(url) }
        } label: {
            HStack(spacing: theme.spacing.sm) {
                Text("\(number)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(accent)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(accent.opacity(0.14)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(citation.title)
                        .font(theme.typography.caption.weight(.semibold))
                        .foregroundStyle(theme.colors.onSurface)
                        .lineLimit(1)
                    if !citation.displaySource.isEmpty {
                        Text(citation.displaySource)
                            .font(.caption2)
                            .foregroundStyle(theme.colors.onSurface.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: 170, alignment: .leading)
            }
            .padding(.leading, theme.spacing.xs + 2)
            .padding(.trailing, theme.spacing.md)
            .padding(.vertical, theme.spacing.xs + 2)
            .background(RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous).fill(theme.colors.surface))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous).strokeBorder(theme.colors.border, lineWidth: 0.75))
        }
        .buttonStyle(KitoAIPressableStyle(scale: 0.96))
        .accessibilityLabel("Source \(number): \(citation.title), \(citation.displaySource)")
        .accessibilityAddTraits(.isLink)
    }
}

// MARK: - Follow-ups

/// Suggested next prompts under the latest reply.
///
/// ```swift
/// KitoAIFollowUpChips(["What should I pack?", "Make it cheaper"]) { prompt in session.send(prompt) }
/// ```
public struct KitoAIFollowUpChips: View {
    private let suggestions: [String]
    private let tint: Color?
    private let onSelect: (String) -> Void

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown = false

    public init(_ suggestions: [String], tint: Color? = nil, onSelect: @escaping (String) -> Void) {
        self.suggestions = suggestions
        self.tint = tint
        self.onSelect = onSelect
    }

    public var body: some View {
        KitoAIFlowLayout(spacing: theme.spacing.sm, lineSpacing: theme.spacing.sm) {
            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                chip(suggestion)
                    .opacity(isShown ? 1 : 0)
                    .offset(y: isShown || reduceMotion ? 0 : 8)
                    .animation(appear(index), value: isShown)
            }
        }
        .onAppear { isShown = true }
    }

    private func appear(_ index: Int) -> Animation {
        let base = KitoAIMotion.spring(reduceMotion)
        return reduceMotion ? base : base.delay(Double(index) * 0.06)
    }

    private func chip(_ suggestion: String) -> some View {
        let accent = tint ?? theme.colors.primary
        return Button { onSelect(suggestion) } label: {
            HStack(spacing: theme.spacing.xs + 2) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption.weight(.bold))
                    .flipsForRightToLeftLayoutDirection(true)
                    .foregroundStyle(accent)
                Text(suggestion)
                    .font(theme.typography.label)
                    .foregroundStyle(theme.colors.onSurface)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, theme.spacing.md)
            .padding(.vertical, theme.spacing.sm)
            .background(Capsule().fill(theme.colors.surface))
            .overlay(Capsule().strokeBorder(accent.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(KitoAIPressableStyle(scale: 0.95))
        .accessibilityHint("Sends this prompt")
    }
}

// MARK: - Suggested prompts

/// A two-column grid of starter prompts that rises in one card at a time.
///
/// ```swift
/// KitoAISuggestedPrompts(KitoAISuggestion.defaults) { suggestion in session.send(suggestion.prompt) }
/// ```
public struct KitoAISuggestedPrompts: View {
    private let suggestions: [KitoAISuggestion]
    private let tint: Color?
    private let onSelect: (KitoAISuggestion) -> Void

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isShown = false

    public init(_ suggestions: [KitoAISuggestion] = KitoAISuggestion.defaults, tint: Color? = nil, onSelect: @escaping (KitoAISuggestion) -> Void) {
        self.suggestions = suggestions
        self.tint = tint
        self.onSelect = onSelect
    }

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: theme.spacing.sm, alignment: .top), count: count)
    }

    public var body: some View {
        LazyVGrid(columns: columns, spacing: theme.spacing.sm) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                card(suggestion)
                    .opacity(isShown ? 1 : 0)
                    .offset(y: isShown || reduceMotion ? 0 : 14)
                    .scaleEffect(isShown || reduceMotion ? 1 : 0.97)
                    .animation(appear(index), value: isShown)
            }
        }
        .onAppear { isShown = true }
    }

    private func appear(_ index: Int) -> Animation {
        let base = KitoAIMotion.spring(reduceMotion)
        return reduceMotion ? base : base.delay(0.08 + Double(index) * 0.07)
    }

    private func card(_ suggestion: KitoAISuggestion) -> some View {
        let accent = tint ?? theme.colors.primary
        return Button { onSelect(suggestion) } label: {
            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                Image(systemName: suggestion.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous).fill(accent.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title)
                        .font(theme.typography.label.weight(.semibold))
                        .foregroundStyle(theme.colors.onSurface)
                    Text(suggestion.subtitle)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.onSurface.opacity(0.55))
                }
                .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .padding(theme.spacing.md)
            .background(
                RoundedRectangle(cornerRadius: theme.radii.xl, style: .continuous)
                    .fill(theme.colors.surface)
                    .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
            )
            .overlay(RoundedRectangle(cornerRadius: theme.radii.xl, style: .continuous).strokeBorder(theme.colors.border.opacity(0.8), lineWidth: 0.75))
        }
        .buttonStyle(KitoAIPressableStyle(scale: 0.96))
        .accessibilityLabel("\(suggestion.title) \(suggestion.subtitle)")
        .accessibilityHint("Sends this prompt")
    }
}

// MARK: - Attachments

/// A file waiting in the composer or sent with a message.
///
/// ```swift
/// KitoAIAttachmentChip(KitoAIAttachment(name: "Itinerary.pdf", kind: .pdf, byteCount: 482_000)) { remove(it) }
/// ```
public struct KitoAIAttachmentChip: View {
    private let attachment: KitoAIAttachment
    private let tint: Color?
    private let onRemove: (() -> Void)?

    @Environment(\.kitoTheme) private var theme

    /// - Parameter onRemove: shows a remove button when set.
    public init(_ attachment: KitoAIAttachment, tint: Color? = nil, onRemove: (() -> Void)? = nil) {
        self.attachment = attachment
        self.tint = tint
        self.onRemove = onRemove
    }

    public var body: some View {
        HStack(spacing: theme.spacing.sm) {
            thumbnail
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.name)
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.onSurface)
                    .lineLimit(1)
                Text(attachment.subtitle)
                    .font(.caption2)
                    .foregroundStyle(theme.colors.onSurface.opacity(0.5))
                    .lineLimit(1)
            }
            .frame(maxWidth: 150, alignment: .leading)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(theme.colors.onSurface.opacity(0.7))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(theme.colors.surfaceMuted))
                        .contentShape(Circle().inset(by: -8))
                }
                .buttonStyle(KitoAIPressableStyle())
                .accessibilityLabel("Remove \(attachment.name)")
            }
        }
        .padding(theme.spacing.xs + 2)
        .padding(.trailing, theme.spacing.xs)
        .background(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous).fill(theme.colors.surface))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous).strokeBorder(theme.colors.border, lineWidth: 0.75))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var thumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous)
        if let image = attachment.thumbnail {
            KitoAIImageView(image: image)
                .frame(width: 36, height: 36)
                .clipShape(shape)
        } else {
            Image(systemName: attachment.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(shape.fill(kindColor.gradient))
        }
    }

    private var kindColor: Color {
        switch attachment.kind {
        case .pdf: return theme.colors.danger
        case .spreadsheet: return theme.colors.success
        case .audio: return theme.colors.warning
        case .image, .document, .code: return tint ?? theme.colors.primary
        }
    }
}
