//
//  KitoAIChatSession.swift
//  KitoAIChat
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation
import Observation

/// The state behind a chat: the conversation, the reply being generated, and the actions —
/// send, stop, regenerate, retry, edit-and-resend and feedback. `KitoAIChatView` is a pure
/// function of it, so you can drive it from your own UI or tests too.
///
/// ```swift
/// @State private var session = KitoAIChatSession(stream: MyBackend())
///
/// KitoAIChatView(session: session)
/// session.send("Plan a weekend in Diani")
/// ```
@MainActor
@Observable
public final class KitoAIChatSession {
    public var conversation: KitoAIConversation
    /// Starter prompts shown while the conversation is empty.
    public var suggestions: [KitoAISuggestion]
    /// Files waiting in the composer; sent with the next message.
    public var attachments: [KitoAIAttachment]
    /// The id of the user message being edited, if any.
    public private(set) var editingMessageID: String?
    /// Bumped on every change to the visible content — observe it to follow streaming text.
    public private(set) var revision = 0

    /// Called with each finished (or failed, or stopped) assistant reply — save the conversation here.
    @ObservationIgnored public var onReplyFinished: ((KitoAIMessage) -> Void)?
    /// Called when a reply gets thumbs up or down.
    @ObservationIgnored public var onFeedback: ((KitoAIMessage, KitoAIFeedback) -> Void)?

    @ObservationIgnored private let stream: KitoAIStream
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    public init(
        conversation: KitoAIConversation = KitoAIConversation(),
        stream: KitoAIStream = KitoMockAIStream(),
        suggestions: [KitoAISuggestion] = KitoAISuggestion.defaults
    ) {
        self.conversation = conversation
        self.stream = stream
        self.suggestions = suggestions
        self.attachments = []
    }

    // MARK: State

    public var messages: [KitoAIMessage] { conversation.messages }

    /// True while a reply is streaming.
    public var isGenerating: Bool { conversation.messages.last?.isStreaming == true }

    /// The latest reply's follow-ups, once it has finished without error.
    public var followUps: [String] {
        guard let last = conversation.messages.last, last.role == .assistant, !last.isStreaming, last.errorMessage == nil else { return [] }
        return last.followUps
    }

    /// The last user message, which is the one that can be edited.
    public var editableMessageID: String? {
        guard !isGenerating else { return nil }
        return conversation.lastUserMessage?.id
    }

    // MARK: Actions

    /// Sends a message (with the waiting attachments) and starts a reply. When editing, replaces
    /// the edited message and everything after it instead.
    public func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        stop()
        if let editingID = editingMessageID, let index = conversation.index(of: editingID) {
            conversation.messages[index].blocks = [.markdown(trimmed)]
            conversation.messages[index].date = Date()
            conversation.removeMessages(after: editingID)
            editingMessageID = nil
        } else {
            conversation.messages.append(KitoAIMessage(role: .user, text: trimmed, attachments: attachments))
            attachments = []
        }
        if conversation.title == nil, conversation.messages.filter({ $0.role == .user }).count == 1 {
            conversation.title = KitoAITitle.make(from: trimmed)
        }
        generate()
    }

    /// Stops the reply in progress, keeping what has arrived.
    public func stop() {
        guard isGenerating else { return }
        task?.cancel()
        task = nil
        finishLast { message in
            message.wasStopped = true
        }
    }

    /// Replaces the latest reply with a new one.
    public func regenerate() {
        stop()
        guard let last = conversation.messages.last, last.role == .assistant else { return }
        conversation.messages.removeLast()
        generate()
    }

    /// Tries a failed reply again.
    public func retry() { regenerate() }

    /// Starts editing the last user message and returns its text for the composer.
    @discardableResult
    public func beginEditing() -> String? {
        guard let id = editableMessageID, let message = conversation.messages.first(where: { $0.id == id }) else { return nil }
        editingMessageID = id
        return message.text
    }

    public func cancelEditing() { editingMessageID = nil }

    /// Thumbs up or down; the same again clears it.
    public func setFeedback(_ feedback: KitoAIFeedback, for messageID: String) {
        guard let index = conversation.index(of: messageID) else { return }
        let current = conversation.messages[index].feedback
        let next: KitoAIFeedback = current == feedback ? .none : feedback
        conversation.messages[index].feedback = next
        onFeedback?(conversation.messages[index], next)
    }

    /// Starts a fresh conversation.
    public func reset(to conversation: KitoAIConversation = KitoAIConversation()) {
        task?.cancel()
        task = nil
        editingMessageID = nil
        attachments = []
        self.conversation = conversation
        revision += 1
    }

    // MARK: Streaming

    private func generate() {
        generation += 1
        let current = generation
        let request = conversation
        conversation.messages.append(KitoAIMessage(role: .assistant, isStreaming: true))
        conversation.updatedAt = Date()
        revision += 1
        let events = stream.reply(to: request)
        task = Task { [weak self] in
            do {
                for try await event in events {
                    guard let self, self.generation == current else { return }
                    self.applyToLast(event)
                }
                self?.complete(generation: current, error: nil)
            } catch is CancellationError {
                return
            } catch {
                self?.complete(generation: current, error: error)
            }
        }
    }

    private func applyToLast(_ event: KitoAIStreamEvent) {
        guard let index = conversation.messages.indices.last, conversation.messages[index].isStreaming else { return }
        conversation.messages[index].apply(event)
        revision += 1
    }

    private func complete(generation finished: Int, error: Error?) {
        guard finished == generation, !Task.isCancelled else { return }
        task = nil
        finishLast { message in
            if let error {
                message.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong. Please try again."
            }
        }
    }

    private func finishLast(_ update: (inout KitoAIMessage) -> Void) {
        guard let index = conversation.messages.indices.last, conversation.messages[index].isStreaming else { return }
        conversation.messages[index].isStreaming = false
        for (position, block) in conversation.messages[index].blocks.enumerated() {
            if case .toolCall(let call) = block, call.status == .running {
                conversation.messages[index].blocks[position] = .toolCall(call.with(status: .failed))
            }
        }
        update(&conversation.messages[index])
        conversation.updatedAt = Date()
        revision += 1
        onReplyFinished?(conversation.messages[index])
    }
}
