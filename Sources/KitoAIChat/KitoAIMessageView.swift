//
//  KitoAIMessageView.swift
//  KitoAIChat
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import UIKit
import KitoCore

/// One message. User messages sit in a bubble on the right; assistant replies run full width
/// beside a small orb, with tool chips, markdown, code, images and sources, then Copy, 👍, 👎 and
/// Regenerate once they finish. A failed reply shows an error bubble with Retry.
///
/// ```swift
/// KitoAIMessageView(message, onRegenerate: { session.regenerate() }) { feedback in
///     session.setFeedback(feedback, for: message.id)
/// }
/// ```
public struct KitoAIMessageView: View {
    private let message: KitoAIMessage
    private let showsAvatar: Bool
    private let tint: Color?
    private let onRegenerate: (() -> Void)?
    private let onRetry: (() -> Void)?
    private let onEdit: (() -> Void)?
    private let onFeedback: ((KitoAIFeedback) -> Void)?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false
    @State private var copyCount = 0

    /// - Parameters:
    ///   - onRegenerate: shows Regenerate under a finished reply.
    ///   - onFeedback: shows thumbs up and down under a finished reply.
    ///   - onRetry: the error bubble's Retry; defaults to `onRegenerate`.
    ///   - onEdit: shows Edit under a user message.
    public init(
        _ message: KitoAIMessage,
        showsAvatar: Bool = true,
        tint: Color? = nil,
        onRegenerate: (() -> Void)? = nil,
        onFeedback: ((KitoAIFeedback) -> Void)? = nil,
        onRetry: (() -> Void)? = nil,
        onEdit: (() -> Void)? = nil
    ) {
        self.message = message
        self.showsAvatar = showsAvatar
        self.tint = tint
        self.onRegenerate = onRegenerate
        self.onRetry = onRetry ?? onRegenerate
        self.onEdit = onEdit
        self.onFeedback = onFeedback
    }

    private var accent: Color { tint ?? theme.colors.primary }

    public var body: some View {
        Group {
            switch message.role {
            case .user: userMessage
            case .assistant: assistantMessage
            case .system: systemMessage
            case .tool: toolMessage
            }
        }
        .sensoryFeedback(.success, trigger: copyCount)
    }

    // MARK: User

    private var userMessage: some View {
        VStack(alignment: .trailing, spacing: theme.spacing.xs + 2) {
            if !message.attachments.isEmpty {
                VStack(alignment: .trailing, spacing: theme.spacing.xs + 2) {
                    ForEach(message.attachments) { attachment in
                        KitoAIAttachmentChip(attachment, tint: tint)
                    }
                }
            }
            if !message.text.isEmpty {
                Text(KitoAIInlineMarkdown.attributed(message.text, theme: theme, accent: accent))
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.onSurface)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, theme.spacing.md + 2)
                    .padding(.vertical, theme.spacing.sm + 2)
                    .background(
                        RoundedRectangle(cornerRadius: theme.radii.xl, style: .continuous)
                            .fill(theme.colors.surfaceMuted)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.radii.xl, style: .continuous)
                            .strokeBorder(theme.colors.border.opacity(0.5), lineWidth: 0.5)
                    )
                    .contextMenu { userMenu }
                    .accessibilityLabel("You: \(message.plainText)")
                    .accessibilityAction(named: "Copy") { copy() }
            }
            if let onEdit {
                HStack(spacing: 2) {
                    actionButton(copied ? "checkmark" : "doc.on.doc", label: copied ? "Copied" : "Copy", action: copy)
                    actionButton("pencil", label: "Edit message", action: onEdit)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, theme.spacing.xxl + theme.spacing.lg)
    }

    @ViewBuilder
    private var userMenu: some View {
        Button { copy() } label: { Label("Copy", systemImage: "doc.on.doc") }
        if let onEdit {
            Button(action: onEdit) { Label("Edit", systemImage: "pencil") }
        }
    }

    // MARK: Assistant

    private var assistantMessage: some View {
        HStack(alignment: .top, spacing: theme.spacing.md) {
            if showsAvatar {
                KitoAIOrb(size: 24, isActive: message.isStreaming, animatesWhenIdle: false, tint: tint)
                    .padding(.top, 1)
            }
            VStack(alignment: .leading, spacing: theme.spacing.md) {
                if message.isStreaming && !message.hasVisibleContent {
                    Text("Thinking…")
                        .font(theme.typography.label)
                        .foregroundStyle(theme.colors.onSurface.opacity(0.55))
                        .kitoAIShimmer()
                        .padding(.top, 3)
                        .accessibilityAddTraits(.updatesFrequently)
                        .transition(.opacity)
                }
                ForEach(Array(message.blocks.enumerated()), id: \.offset) { index, block in
                    blockView(block, isLast: index == message.blocks.count - 1)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                if let error = message.errorMessage {
                    KitoAIErrorBubble(error, onRetry: onRetry)
                        .transition(.scale(scale: 0.96, anchor: .topLeading).combined(with: .opacity))
                }
                if message.wasStopped {
                    Label("Stopped", systemImage: "stop.circle")
                        .font(theme.typography.caption.weight(.medium))
                        .foregroundStyle(theme.colors.onSurface.opacity(0.5))
                }
                if !message.isStreaming && message.hasVisibleContent {
                    assistantActions
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(KitoAIMotion.spring(reduceMotion), value: message.isStreaming)
        .animation(KitoAIMotion.spring(reduceMotion), value: message.errorMessage)
        .animation(KitoAIMotion.spring(reduceMotion), value: message.blocks.count)
    }

    @ViewBuilder
    private func blockView(_ block: KitoAIContentBlock, isLast: Bool) -> some View {
        switch block {
        case .markdown(let text):
            KitoAIMarkdownView(text, isStreaming: message.isStreaming && isLast, tint: tint)
        case .code(let language, let code):
            KitoAICodeBlock(code, language: language, isStreaming: message.isStreaming && isLast, tint: tint)
        case .image(let image):
            KitoAIImageView(image: image)
                .aspectRatio(image.aspectRatio, contentMode: .fit)
                .frame(maxWidth: 360, maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous))
        case .toolCall(let call):
            KitoAIToolChip(call, tint: tint)
        case .citations(let citations):
            KitoAICitationChips(citations, tint: tint)
        }
    }

    private var assistantActions: some View {
        HStack(spacing: 2) {
            actionButton(copied ? "checkmark" : "doc.on.doc", label: copied ? "Copied" : "Copy", action: copy)
            if let onFeedback {
                feedbackButton(.positive, onFeedback: onFeedback)
                feedbackButton(.negative, onFeedback: onFeedback)
            }
            if let onRegenerate {
                actionButton("arrow.clockwise", label: "Regenerate", action: onRegenerate)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, -theme.spacing.sm)
    }

    private func feedbackButton(_ value: KitoAIFeedback, onFeedback: @escaping (KitoAIFeedback) -> Void) -> some View {
        let isSelected = message.feedback == value
        let base = value == .positive ? "hand.thumbsup" : "hand.thumbsdown"
        return Button { onFeedback(value) } label: {
            Image(systemName: isSelected ? "\(base).fill" : base)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? accent : theme.colors.onSurface.opacity(0.5))
                .symbolEffect(.bounce, value: isSelected)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(KitoAIPressableStyle())
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityLabel(value == .positive ? "Good response" : "Bad response")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func actionButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.colors.onSurface.opacity(0.5))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(KitoAIPressableStyle())
        .accessibilityLabel(label)
    }

    // MARK: System and tool

    private var systemMessage: some View {
        Text(message.plainText)
            .font(theme.typography.caption.weight(.medium))
            .foregroundStyle(theme.colors.onSurface.opacity(0.6))
            .multilineTextAlignment(.center)
            .padding(.horizontal, theme.spacing.md)
            .padding(.vertical, theme.spacing.xs + 2)
            .background(Capsule().fill(theme.colors.surfaceMuted))
            .frame(maxWidth: .infinity)
    }

    private var toolMessage: some View {
        DisclosureGroup {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(message.text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(theme.colors.onSurface.opacity(0.75))
                    .textSelection(.enabled)
                    .padding(theme.spacing.sm)
            }
            .background(RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous).fill(theme.colors.surfaceMuted))
        } label: {
            Label("Tool result", systemImage: "shippingbox")
                .font(theme.typography.caption.weight(.semibold))
                .foregroundStyle(theme.colors.onSurface.opacity(0.6))
        }
        .tint(theme.colors.onSurface.opacity(0.6))
        .padding(.leading, showsAvatar ? 24 + theme.spacing.md : 0)
    }

    private func copy() {
        UIPasteboard.general.string = message.text
        copyCount += 1
        withAnimation(KitoAIMotion.snappy(reduceMotion)) { copied = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(KitoAIMotion.snappy(reduceMotion)) { copied = false }
        }
    }
}

/// "Something went wrong" with the reason and a Retry button.
public struct KitoAIErrorBubble: View {
    private let message: String
    private let onRetry: (() -> Void)?

    @Environment(\.kitoTheme) private var theme

    public init(_ message: String, onRetry: (() -> Void)? = nil) {
        self.message = message
        self.onRetry = onRetry
    }

    public var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.colors.danger)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Something went wrong")
                        .font(theme.typography.label.weight(.semibold))
                        .foregroundStyle(theme.colors.onSurface)
                    Text(message)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.onSurface.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let onRetry {
                    Button(action: onRetry) {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(theme.typography.label.weight(.semibold))
                            .padding(.horizontal, theme.spacing.md)
                            .padding(.vertical, theme.spacing.xs + 2)
                            .background(Capsule().fill(theme.colors.danger))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(KitoAIPressableStyle(scale: 0.95))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(theme.spacing.md)
        .background(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous).fill(theme.colors.danger.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous).strokeBorder(theme.colors.danger.opacity(0.25), lineWidth: 0.75))
        .accessibilityElement(children: .combine)
    }
}
