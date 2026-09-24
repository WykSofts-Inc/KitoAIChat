//
//  KitoAIChatView.swift
//  KitoAIChat
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// A whole AI conversation: a welcome and starter prompts when it's empty, streaming replies
/// with markdown, code, tool chips and sources, Stop, Regenerate, Copy, feedback, edit-and-resend
/// of the last message, errors with Retry, follow-up chips, and the composer. It follows new text
/// as it streams, pauses when you scroll up, and offers "Jump to latest".
///
/// ```swift
/// // Try it with canned replies:
/// KitoAIChatView(stream: KitoMockAIStream(), userName: "Wycliff N")
///
/// // Or with your model:
/// @State private var session = KitoAIChatSession(stream: MyBackend())
/// KitoAIChatView(session: session) {
///     KitoAIModelPicker(models, selection: $model)
/// }
/// ```
///
/// The view keeps the session it's first given, like `@State`.
public struct KitoAIChatView<Accessory: View>: View {
    @State private var session: KitoAIChatSession
    private let userName: String?
    private let placeholder: String
    private let tint: Color?
    private let onAttach: (() -> Void)?
    private let accessory: Accessory

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft = ""
    @State private var policy = KitoAIAutoScrollPolicy()
    @State private var viewportHeight: CGFloat = 0

    private static var bottomID: String { "kito.ai.bottom" }
    private static var space: String { "kito.ai.scroll" }

    /// - Parameters:
    ///   - userName: greets them by first name on the welcome screen.
    ///   - onAttach: shows the composer's attach button. Add files to `session.attachments`.
    ///   - composerAccessory: sits beside the attach button — made for `KitoAIModelPicker`.
    public init(
        session: KitoAIChatSession,
        userName: String? = nil,
        placeholder: String = "Ask anything",
        tint: Color? = nil,
        onAttach: (() -> Void)? = nil,
        @ViewBuilder composerAccessory: () -> Accessory
    ) {
        _session = State(initialValue: session)
        self.userName = userName
        self.placeholder = placeholder
        self.tint = tint
        self.onAttach = onAttach
        self.accessory = composerAccessory()
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                scrollView(proxy: proxy)
            }
            if session.editingMessageID != nil {
                editingBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            KitoAIComposer(
                text: $draft,
                attachments: $session.attachments,
                isGenerating: session.isGenerating,
                placeholder: placeholder,
                tint: tint,
                onAttach: onAttach,
                onStop: { session.stop() },
                onSend: send,
                accessory: { accessory }
            )
        }
        .background(theme.colors.background.ignoresSafeArea())
        .animation(KitoAIMotion.spring(reduceMotion), value: session.editingMessageID)
    }

    // MARK: Conversation

    private func scrollView(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.xl) {
                if session.messages.isEmpty {
                    emptyState
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
                ForEach(session.messages) { message in
                    row(for: message)
                        .id(message.id)
                        .transition(rowTransition(for: message))
                }
                if !session.followUps.isEmpty {
                    KitoAIFollowUpChips(session.followUps, tint: tint) { send($0) }
                        .padding(.leading, 24 + theme.spacing.md)
                        .transition(.opacity)
                }
                Color.clear
                    .frame(height: 1)
                    .id(Self.bottomID)
            }
            .padding(.horizontal, theme.spacing.lg)
            .padding(.top, theme.spacing.lg)
            .padding(.bottom, theme.spacing.md)
            .animation(KitoAIMotion.spring(reduceMotion), value: session.messages.count)
            .animation(KitoAIMotion.spring(reduceMotion), value: session.followUps)
            .background(metricsReader)
        }
        .coordinateSpace(name: Self.space)
        .scrollDismissesKeyboard(.interactively)
        .defaultScrollAnchor(.bottom)
        .background(viewportReader)
        .onPreferenceChange(KitoAIScrollMetricsKey.self) { metrics in
            observe(metrics)
        }
        .onChange(of: session.revision) { _, _ in
            guard policy.shouldFollowContent else { return }
            scrollToBottom(proxy, animated: true)
        }
        .onChange(of: viewportHeight) { _, _ in
            guard policy.shouldFollowContent else { return }
            scrollToBottom(proxy, animated: false)
        }
        .overlay(alignment: .bottom) { bottomFade }
        .overlay(alignment: .bottom) { jumpPill(proxy: proxy) }
        .animation(KitoAIMotion.spring(reduceMotion), value: policy.showsJumpToLatest)
    }

    private var metricsReader: some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: KitoAIScrollMetricsKey.self,
                value: KitoAIScrollMetrics(maxY: geometry.frame(in: .named(Self.space)).maxY, height: geometry.size.height)
            )
        }
    }

    private var viewportReader: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear { viewportHeight = geometry.size.height }
                .onChange(of: geometry.size.height) { _, height in viewportHeight = height }
        }
    }

    private func observe(_ metrics: KitoAIScrollMetrics) {
        let distance = max(0, metrics.maxY - viewportHeight)
        policy.observe(distanceFromBottom: distance, contentHeight: metrics.height, viewportHeight: viewportHeight)
    }

    private func rowTransition(for message: KitoAIMessage) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let edge: UnitPoint = message.role == .user ? .bottomTrailing : .topLeading
        return .scale(scale: 0.96, anchor: edge).combined(with: .opacity)
    }

    private func row(for message: KitoAIMessage) -> some View {
        let isLast = message.id == session.messages.last?.id
        let canRegenerate = isLast && message.role == .assistant && !message.isStreaming
        let canEdit = message.id == session.editableMessageID && session.editingMessageID == nil
        return KitoAIMessageRow(
            message: message,
            canEdit: canEdit,
            canRegenerate: canRegenerate,
            tint: tint,
            onRegenerate: { session.regenerate() },
            onEdit: { beginEditing() },
            onFeedback: { feedback in session.setFeedback(feedback, for: message.id) }
        )
        .equatable()
    }

    private var emptyState: some View {
        VStack(spacing: theme.spacing.xl) {
            Spacer(minLength: theme.spacing.lg)
            KitoAIWelcome(name: userName, tint: tint)
            Spacer(minLength: theme.spacing.lg)
            KitoAISuggestedPrompts(session.suggestions, tint: tint) { suggestion in
                send(suggestion.prompt)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: max(0, viewportHeight - theme.spacing.lg - theme.spacing.md - 2))
    }

    // MARK: Overlays

    private var bottomFade: some View {
        LinearGradient(colors: [theme.colors.background.opacity(0), theme.colors.background], startPoint: .top, endPoint: .bottom)
            .frame(height: theme.spacing.lg)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func jumpPill(proxy: ScrollViewProxy) -> some View {
        if policy.showsJumpToLatest && !session.messages.isEmpty {
            Button {
                policy.jumpToLatest()
                scrollToBottom(proxy, animated: true)
            } label: {
                HStack(spacing: theme.spacing.xs + 2) {
                    Image(systemName: "arrow.down")
                        .font(.caption.weight(.bold))
                    Text("Jump to latest")
                        .font(theme.typography.caption.weight(.semibold))
                    if session.isGenerating {
                        KitoAIOrb(size: 12, isActive: true, tint: tint)
                    }
                }
                .foregroundStyle(theme.colors.onSurface)
                .padding(.horizontal, theme.spacing.md)
                .padding(.vertical, theme.spacing.sm)
                .background(Capsule().fill(.regularMaterial))
                .overlay(Capsule().strokeBorder(theme.colors.border.opacity(0.7), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            }
            .buttonStyle(KitoAIPressableStyle(scale: 0.95))
            .padding(.bottom, theme.spacing.md)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityLabel(session.isGenerating ? "Jump to latest, still replying" : "Jump to latest")
        }
    }

    private var editingBanner: some View {
        HStack(spacing: theme.spacing.sm) {
            Image(systemName: "pencil")
                .font(.caption.weight(.bold))
                .foregroundStyle(tint ?? theme.colors.primary)
            Text("Editing your message")
                .font(theme.typography.caption.weight(.semibold))
                .foregroundStyle(theme.colors.onSurface)
            Spacer()
            Button("Cancel") {
                session.cancelEditing()
                draft = ""
            }
            .font(theme.typography.caption.weight(.semibold))
            .foregroundStyle(tint ?? theme.colors.primary)
        }
        .padding(.horizontal, theme.spacing.lg)
        .padding(.vertical, theme.spacing.sm)
        .background(Capsule().fill(theme.colors.surfaceMuted))
        .padding(.horizontal, theme.spacing.lg)
        .padding(.top, theme.spacing.xs)
    }

    // MARK: Actions

    private func send(_ text: String) {
        policy.didSendMessage()
        session.send(text)
    }

    private func beginEditing() {
        if let text = session.beginEditing() { draft = text }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard animated, !reduceMotion else {
            proxy.scrollTo(Self.bottomID, anchor: .bottom)
            return
        }
        let animation: Animation = session.isGenerating ? .linear(duration: 0.12) : .easeOut(duration: 0.28)
        withAnimation(animation) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
    }
}

public extension KitoAIChatView where Accessory == EmptyView {
    /// A chat driven by `session`.
    init(
        session: KitoAIChatSession,
        userName: String? = nil,
        placeholder: String = "Ask anything",
        tint: Color? = nil,
        onAttach: (() -> Void)? = nil
    ) {
        self.init(session: session, userName: userName, placeholder: placeholder, tint: tint, onAttach: onAttach) { EmptyView() }
    }

    /// A chat that owns its session, streaming replies from `stream`.
    init(
        stream: KitoAIStream,
        conversation: KitoAIConversation = KitoAIConversation(),
        suggestions: [KitoAISuggestion] = KitoAISuggestion.defaults,
        userName: String? = nil,
        placeholder: String = "Ask anything",
        tint: Color? = nil
    ) {
        let session = KitoAIChatSession(conversation: conversation, stream: stream, suggestions: suggestions)
        self.init(session: session, userName: userName, placeholder: placeholder, tint: tint, onAttach: nil) { EmptyView() }
    }
}

/// A message row that only redraws when its message or flags change — so streaming one reply
/// doesn't redraw the whole conversation.
struct KitoAIMessageRow: View, Equatable {
    let message: KitoAIMessage
    let canEdit: Bool
    let canRegenerate: Bool
    let tint: Color?
    let onRegenerate: () -> Void
    let onEdit: () -> Void
    let onFeedback: (KitoAIFeedback) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.message == rhs.message && lhs.canEdit == rhs.canEdit && lhs.canRegenerate == rhs.canRegenerate && lhs.tint == rhs.tint
    }

    var body: some View {
        KitoAIMessageView(
            message,
            tint: tint,
            onRegenerate: canRegenerate ? onRegenerate : nil,
            onFeedback: message.role == .assistant ? onFeedback : nil,
            onRetry: message.errorMessage != nil ? onRegenerate : nil,
            onEdit: canEdit ? onEdit : nil
        )
    }
}

struct KitoAIScrollMetrics: Equatable {
    var maxY: CGFloat = 0
    var height: CGFloat = 0
}

struct KitoAIScrollMetricsKey: PreferenceKey {
    static let defaultValue = KitoAIScrollMetrics()

    static func reduce(value: inout KitoAIScrollMetrics, nextValue: () -> KitoAIScrollMetrics) {
        value = nextValue()
    }
}
