//
//  KitoAIMessage.swift
//  KitoAIChat
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// Who wrote a message.
public enum KitoAIRole: String, Codable, Hashable, Sendable {
    case user
    case assistant
    /// A notice from the app or the model ("Switched to Kito Pro"), shown as a centred caption.
    case system
    /// The output of a tool the assistant called. Shown collapsed.
    case tool
}

/// A picture inside a message: a remote `url`, or encoded image `data` (PNG or JPEG).
public struct KitoAIImage: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var url: URL?
    public var data: Data?
    /// Width divided by height, used to size the image before it loads.
    public var aspectRatio: Double
    /// Read by VoiceOver.
    public var altText: String?

    public init(id: String = UUID().uuidString, url: URL? = nil, data: Data? = nil, aspectRatio: Double = 4 / 3, altText: String? = nil) {
        self.id = id
        self.url = url
        self.data = data
        self.aspectRatio = aspectRatio
        self.altText = altText
    }
}

/// Where a tool call has got to.
public enum KitoAIToolStatus: String, Codable, Hashable, Sendable {
    case running
    case done
    case failed
}

/// A tool the assistant is using — shown as a chip that reads "Searching the web…" while it runs
/// and "Searched the web · 5 sources" once it's done.
public struct KitoAIToolCall: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    /// Your tool's identifier, e.g. `"web_search"`.
    public var name: String
    /// Shown while running, e.g. "Searching the web…".
    public var runningTitle: String
    /// Shown when finished, e.g. "Searched the web".
    public var doneTitle: String
    /// A short result summary shown after the title, e.g. "5 sources".
    public var detail: String?
    /// An SF Symbol name.
    public var symbol: String
    public var status: KitoAIToolStatus

    public init(
        id: String = UUID().uuidString,
        name: String,
        runningTitle: String,
        doneTitle: String,
        detail: String? = nil,
        symbol: String = "wrench.and.screwdriver",
        status: KitoAIToolStatus = .running
    ) {
        self.id = id
        self.name = name
        self.runningTitle = runningTitle
        self.doneTitle = doneTitle
        self.detail = detail
        self.symbol = symbol
        self.status = status
    }

    /// The title that matches `status`.
    public var title: String {
        switch status {
        case .running: return runningTitle
        case .done: return doneTitle
        case .failed: return runningTitle.replacingOccurrences(of: "…", with: "") + " didn't finish"
        }
    }

    /// A copy with a new status (and optionally a detail).
    public func with(status: KitoAIToolStatus, detail: String? = nil) -> KitoAIToolCall {
        var copy = self
        copy.status = status
        if let detail { copy.detail = detail }
        return copy
    }

    /// A web search chip.
    public static func webSearch(id: String = UUID().uuidString, query: String? = nil) -> KitoAIToolCall {
        KitoAIToolCall(id: id, name: "web_search", runningTitle: "Searching the web…", doneTitle: "Searched the web",
                       detail: query, symbol: "globe")
    }
}

/// A source the answer draws on, shown as a numbered chip.
public struct KitoAICitation: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var url: URL?
    /// Usually the site's domain; derived from `url` when nil.
    public var source: String?

    public init(id: String = UUID().uuidString, title: String, url: URL? = nil, source: String? = nil) {
        self.id = id
        self.title = title
        self.url = url
        self.source = source
    }

    /// `source`, or the url's host without "www.".
    public var displaySource: String {
        if let source, !source.isEmpty { return source }
        let host = url?.host() ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// One piece of a message. Assistant replies are usually a single `.markdown` block that streams
/// in, with tool calls, images and citations around it.
public enum KitoAIContentBlock: Codable, Hashable, Sendable {
    /// Markdown text — headings, lists, tables, fenced code and inline styles are all rendered.
    case markdown(String)
    /// A code block supplied separately from the text.
    case code(language: String?, code: String)
    case image(KitoAIImage)
    case toolCall(KitoAIToolCall)
    case citations([KitoAICitation])
}

/// Thumbs up or down on an assistant reply.
public enum KitoAIFeedback: String, Codable, Hashable, Sendable {
    case none
    case positive
    case negative
}

/// A file attached to a user message (or waiting in the composer).
public struct KitoAIAttachment: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case image, document, pdf, code, spreadsheet, audio
    }

    public var id: String
    public var name: String
    public var kind: Kind
    public var byteCount: Int?
    public var thumbnail: KitoAIImage?

    public init(id: String = UUID().uuidString, name: String, kind: Kind, byteCount: Int? = nil, thumbnail: KitoAIImage? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.byteCount = byteCount
        self.thumbnail = thumbnail
    }

    /// An SF Symbol for the kind.
    public var symbol: String {
        switch kind {
        case .image: return "photo"
        case .document: return "doc.text"
        case .pdf: return "doc.richtext"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .spreadsheet: return "tablecells"
        case .audio: return "waveform"
        }
    }

    /// "PDF · 1.2 MB", "Image", …
    public var subtitle: String {
        let label: String
        switch kind {
        case .image: label = "Image"
        case .document: label = "Document"
        case .pdf: label = "PDF"
        case .code: label = "Code"
        case .spreadsheet: label = "Spreadsheet"
        case .audio: label = "Audio"
        }
        guard let byteCount else { return label }
        return "\(label) · \(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))"
    }
}

/// One message in a conversation.
public struct KitoAIMessage: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var role: KitoAIRole
    public var blocks: [KitoAIContentBlock]
    public var attachments: [KitoAIAttachment]
    public var date: Date
    /// True while the reply is still arriving.
    public var isStreaming: Bool
    /// True when the person stopped the reply before it finished.
    public var wasStopped: Bool
    /// Set when the reply failed; the message shows an error bubble with Retry.
    public var errorMessage: String?
    public var feedback: KitoAIFeedback
    /// Suggested next prompts, shown as chips after the latest reply.
    public var followUps: [String]

    public init(
        id: String = UUID().uuidString,
        role: KitoAIRole,
        blocks: [KitoAIContentBlock] = [],
        attachments: [KitoAIAttachment] = [],
        date: Date = Date(),
        isStreaming: Bool = false,
        wasStopped: Bool = false,
        errorMessage: String? = nil,
        feedback: KitoAIFeedback = .none,
        followUps: [String] = []
    ) {
        self.id = id
        self.role = role
        self.blocks = blocks
        self.attachments = attachments
        self.date = date
        self.isStreaming = isStreaming
        self.wasStopped = wasStopped
        self.errorMessage = errorMessage
        self.feedback = feedback
        self.followUps = followUps
    }

    /// A message whose content is one markdown block.
    public init(id: String = UUID().uuidString, role: KitoAIRole, text: String, attachments: [KitoAIAttachment] = [], date: Date = Date()) {
        self.init(id: id, role: role, blocks: [.markdown(text)], attachments: attachments, date: date)
    }

    public static func user(_ text: String, attachments: [KitoAIAttachment] = [], date: Date = Date()) -> KitoAIMessage {
        KitoAIMessage(role: .user, text: text, attachments: attachments, date: date)
    }

    public static func assistant(_ text: String, date: Date = Date()) -> KitoAIMessage {
        KitoAIMessage(role: .assistant, text: text, date: date)
    }

    public static func system(_ text: String, date: Date = Date()) -> KitoAIMessage {
        KitoAIMessage(role: .system, text: text, date: date)
    }

    /// The markdown and code of the message joined together — what Copy puts on the pasteboard.
    public var text: String {
        blocks.compactMap { block -> String? in
            switch block {
            case .markdown(let text): return text
            case .code(let language, let code): return "```\(language ?? "")\n\(code)\n```"
            default: return nil
            }
        }
        .joined(separator: "\n\n")
    }

    /// The text without markdown syntax, for previews and VoiceOver.
    public var plainText: String { KitoAIMarkdown.plainText(text) }

    public var toolCalls: [KitoAIToolCall] {
        blocks.compactMap { if case .toolCall(let call) = $0 { return call } else { return nil } }
    }

    public var citations: [KitoAICitation] {
        blocks.flatMap { block -> [KitoAICitation] in
            if case .citations(let list) = block { return list } else { return [] }
        }
    }

    /// True when there's nothing to show yet — the moment to show "Thinking…".
    public var hasVisibleContent: Bool {
        blocks.contains { block in
            switch block {
            case .markdown(let text): return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            default: return true
            }
        }
    }

    /// Applies one streamed event: tokens extend the last markdown block (or start one after a
    /// tool call), tool calls are inserted or updated in place by id, citations merge into one row.
    public mutating func apply(_ event: KitoAIStreamEvent) {
        switch event {
        case .token(let token):
            appendToken(token)
        case .toolCall(let call):
            upsert(call)
        case .citations(let citations):
            mergeCitations(citations)
        case .image(let image):
            blocks.append(.image(image))
        case .followUps(let suggestions):
            followUps = suggestions
        }
    }

    private mutating func appendToken(_ token: String) {
        guard !token.isEmpty else { return }
        if case .markdown(let existing)? = blocks.last {
            blocks[blocks.count - 1] = .markdown(existing + token)
        } else {
            blocks.append(.markdown(token))
        }
    }

    private mutating func upsert(_ call: KitoAIToolCall) {
        let index = blocks.firstIndex { block in
            if case .toolCall(let existing) = block { return existing.id == call.id }
            return false
        }
        if let index {
            blocks[index] = .toolCall(call)
        } else {
            blocks.append(.toolCall(call))
        }
    }

    private mutating func mergeCitations(_ citations: [KitoAICitation]) {
        let index = blocks.firstIndex { if case .citations = $0 { return true } else { return false } }
        guard let index, case .citations(let existing) = blocks[index] else {
            blocks.append(.citations(citations))
            return
        }
        let known = Set(existing.map(\.id))
        blocks[index] = .citations(existing + citations.filter { !known.contains($0.id) })
    }
}

/// A whole conversation.
public struct KitoAIConversation: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    /// Leave nil to derive one from the first message (see `KitoAITitle`).
    public var title: String?
    public var messages: [KitoAIMessage]
    public var updatedAt: Date
    /// The model used, shown as a badge in the conversation list.
    public var model: String?
    public var isPinned: Bool

    public init(
        id: String = UUID().uuidString,
        title: String? = nil,
        messages: [KitoAIMessage] = [],
        updatedAt: Date? = nil,
        model: String? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.updatedAt = updatedAt ?? messages.last?.date ?? Date()
        self.model = model
        self.isPinned = isPinned
    }

    /// `title`, else one made from the first user message, else "New chat".
    public var displayTitle: String {
        if let title, !title.isEmpty { return title }
        guard let first = messages.first(where: { $0.role == .user }) else { return "New chat" }
        return KitoAITitle.make(from: first.text)
    }

    /// The latest user or assistant text, without markdown, for a list row.
    public var snippet: String {
        let last = messages.last { ($0.role == .assistant || $0.role == .user) && !$0.text.isEmpty }
        return last?.plainText.replacingOccurrences(of: "\n", with: " ") ?? ""
    }

    public var lastUserMessage: KitoAIMessage? { messages.last { $0.role == .user } }
    public var lastAssistantMessage: KitoAIMessage? { messages.last { $0.role == .assistant } }

    public func index(of id: String) -> Int? { messages.firstIndex { $0.id == id } }

    /// Removes every message after the one with `id`.
    public mutating func removeMessages(after id: String) {
        guard let index = index(of: id) else { return }
        messages.removeSubrange((index + 1)...)
    }
}

/// A starter prompt for an empty conversation.
public struct KitoAISuggestion: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String
    /// What gets sent; defaults to the title and subtitle together.
    public var prompt: String
    public var symbol: String

    public init(id: String = UUID().uuidString, title: String, subtitle: String, prompt: String? = nil, symbol: String = "sparkles") {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.prompt = prompt ?? "\(title) \(subtitle)"
        self.symbol = symbol
    }

    /// Four East-African flavoured starters that match `KitoMockAIStream`'s replies.
    public static let defaults: [KitoAISuggestion] = [
        KitoAISuggestion(title: "Plan a weekend", subtitle: "in Diani on a budget", prompt: "Plan a weekend in Diani on a budget", symbol: "beach.umbrella"),
        KitoAISuggestion(title: "Explain M-Pesa", subtitle: "STK push in Swift", prompt: "Show me M-Pesa STK push in Swift", symbol: "chevron.left.forwardslash.chevron.right"),
        KitoAISuggestion(title: "Teach me Swahili", subtitle: "phrases for a safari", prompt: "Teach me Swahili phrases for a safari", symbol: "character.bubble"),
        KitoAISuggestion(title: "Compare the SGR", subtitle: "and a matatu to Mombasa", prompt: "Compare the SGR and a matatu to Mombasa", symbol: "tram.fill"),
    ]
}

/// A model the person can choose.
public struct KitoAIModelOption: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var detail: String
    public var symbol: String

    public init(id: String, name: String, detail: String, symbol: String = "sparkles") {
        self.id = id
        self.name = name
        self.detail = detail
        self.symbol = symbol
    }

    /// Three sample models for previews.
    public static let defaults: [KitoAIModelOption] = [
        KitoAIModelOption(id: "fast", name: "Kito Fast", detail: "Quick everyday answers", symbol: "bolt.fill"),
        KitoAIModelOption(id: "pro", name: "Kito Pro", detail: "Deeper reasoning", symbol: "sparkles"),
        KitoAIModelOption(id: "local", name: "Kito Local", detail: "Runs on this device", symbol: "iphone"),
    ]
}
