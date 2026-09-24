//
//  KitoAIConversationList.swift
//  KitoAIChat
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// A sidebar row: the conversation's title, the latest text, when it was last active and the model.
///
/// ```swift
/// KitoAIConversationRow(conversation, isSelected: conversation.id == openID)
/// ```
public struct KitoAIConversationRow: View {
    private let conversation: KitoAIConversation
    private let isSelected: Bool
    private let now: Date
    private let tint: Color?

    @Environment(\.kitoTheme) private var theme

    public init(_ conversation: KitoAIConversation, isSelected: Bool = false, now: Date = Date(), tint: Color? = nil) {
        self.conversation = conversation
        self.isSelected = isSelected
        self.now = now
        self.tint = tint
    }

    private var accent: Color { tint ?? theme.colors.primary }
    private var timestamp: String { KitoAIDateFormat.rowTimestamp(for: conversation.updatedAt, now: now) }

    public var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.md) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: theme.spacing.sm) {
                    Text(conversation.displayTitle)
                        .font(theme.typography.label.weight(.semibold))
                        .foregroundStyle(theme.colors.onSurface)
                        .lineLimit(1)
                    Spacer(minLength: theme.spacing.xs)
                    Text(timestamp)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(theme.colors.onSurface.opacity(0.45))
                }
                if !conversation.snippet.isEmpty {
                    Text(conversation.snippet)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.onSurface.opacity(0.58))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if let model = conversation.model {
                    Text(model)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, theme.spacing.sm)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(accent.opacity(0.1)))
                        .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, theme.spacing.md)
        .padding(.vertical, theme.spacing.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous)
                .fill(isSelected ? accent.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous)
                .strokeBorder(isSelected ? accent.opacity(0.25) : Color.clear, lineWidth: 0.75)
        )
        .contentShape(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var icon: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous)
        return Image(systemName: conversation.isPinned ? "pin.fill" : "text.bubble")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isSelected ? .white : accent)
            .frame(width: 34, height: 34)
            .background(shape.fill(isSelected ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(accent.opacity(0.12))))
    }

    private var accessibilityText: String {
        let pinned = conversation.isPinned ? "Pinned. " : ""
        return "\(pinned)\(conversation.displayTitle), \(timestamp). \(conversation.snippet)"
    }
}

/// A searchable sidebar of conversations, grouped into Pinned, Today, Yesterday, Previous 7 days,
/// Previous 30 days and months, with a New chat button and pin / delete in each row's menu.
///
/// ```swift
/// KitoAIConversationList(conversations: history, selection: $openID, onNewChat: { startChat() })
/// ```
public struct KitoAIConversationList: View {
    private let conversations: [KitoAIConversation]
    @Binding private var selection: String?
    private let showsSearch: Bool
    private let tint: Color?
    private let onNewChat: (() -> Void)?
    private let onTogglePin: ((KitoAIConversation) -> Void)?
    private let onDelete: ((KitoAIConversation) -> Void)?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""

    public init(
        conversations: [KitoAIConversation],
        selection: Binding<String?>,
        showsSearch: Bool = true,
        tint: Color? = nil,
        onNewChat: (() -> Void)? = nil,
        onTogglePin: ((KitoAIConversation) -> Void)? = nil,
        onDelete: ((KitoAIConversation) -> Void)? = nil
    ) {
        self.conversations = conversations
        _selection = selection
        self.showsSearch = showsSearch
        self.tint = tint
        self.onNewChat = onNewChat
        self.onTogglePin = onTogglePin
        self.onDelete = onDelete
    }

    private var sections: [KitoAIConversationSection] {
        KitoAIConversationGrouping.sections(for: KitoAIConversationGrouping.filter(conversations, query: query))
    }

    public var body: some View {
        let sections = self.sections
        VStack(spacing: 0) {
            if showsSearch || onNewChat != nil {
                header
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.conversations) { conversation in
                                row(conversation)
                            }
                        } header: {
                            sectionHeader(section.title)
                        }
                    }
                }
                .padding(.horizontal, theme.spacing.sm)
                .padding(.bottom, theme.spacing.lg)
                .animation(KitoAIMotion.spring(reduceMotion), value: sections.map(\.conversations.count))
            }
            .overlay {
                if sections.isEmpty { emptyState }
            }
        }
        .background(theme.colors.background)
    }

    private var header: some View {
        HStack(spacing: theme.spacing.sm) {
            if showsSearch {
                HStack(spacing: theme.spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.colors.onSurface.opacity(0.45))
                    TextField("Search chats", text: $query)
                        .font(theme.typography.label)
                        .foregroundStyle(theme.colors.onSurface)
                        .submitLabel(.search)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(theme.colors.onSurface.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, theme.spacing.md)
                .frame(height: 38)
                .background(Capsule().fill(theme.colors.surfaceMuted))
            } else {
                Spacer()
            }
            if let onNewChat {
                Button(action: onNewChat) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.colors.background)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(tint ?? theme.colors.onBackground))
                }
                .buttonStyle(KitoAIPressableStyle())
                .accessibilityLabel("New chat")
            }
        }
        .padding(.horizontal, theme.spacing.md)
        .padding(.vertical, theme.spacing.sm)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(theme.typography.caption.weight(.semibold))
            .foregroundStyle(theme.colors.onSurface.opacity(0.5))
            .padding(.horizontal, theme.spacing.md)
            .padding(.top, theme.spacing.md)
            .padding(.bottom, theme.spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.colors.background)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ conversation: KitoAIConversation) -> some View {
        Button {
            selection = conversation.id
        } label: {
            KitoAIConversationRow(conversation, isSelected: selection == conversation.id, tint: tint)
        }
        .buttonStyle(KitoAIPressableStyle(scale: 0.98))
        .contextMenu {
            if let onTogglePin {
                Button { onTogglePin(conversation) } label: {
                    Label(conversation.isPinned ? "Unpin" : "Pin", systemImage: conversation.isPinned ? "pin.slash" : "pin")
                }
            }
            if let onDelete {
                Button(role: .destructive) { onDelete(conversation) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }

    private var emptyState: some View {
        VStack(spacing: theme.spacing.sm) {
            Image(systemName: query.isEmpty ? "bubble.left.and.text.bubble.right" : "magnifyingglass")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(theme.colors.onSurface.opacity(0.3))
            Text(query.isEmpty ? "No chats yet" : "No chats match “\(query)”")
                .font(theme.typography.label.weight(.semibold))
                .foregroundStyle(theme.colors.onSurface.opacity(0.7))
        }
        .padding(theme.spacing.xl)
    }
}
