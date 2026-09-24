//
//  KitoAIStream.swift
//  KitoAIChat
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// Something that happens while a reply streams in.
public enum KitoAIStreamEvent: Hashable, Sendable {
    /// More text. Tokens are appended as they arrive; any size works, from a character to a paragraph.
    case token(String)
    /// A tool call started or changed. Send the same `id` again with `.done` to finish it.
    case toolCall(KitoAIToolCall)
    case citations([KitoAICitation])
    case image(KitoAIImage)
    /// Suggested next prompts, shown as chips once the reply finishes.
    case followUps([String])
}

/// Where replies come from. Wrap your provider's streaming API — KitoAIChat has no network code of
/// its own, so any model, any SDK and any transport works.
///
/// ```swift
/// struct MyBackend: KitoAIStream {
///     func reply(to conversation: KitoAIConversation) -> AsyncThrowingStream<KitoAIStreamEvent, Error> {
///         AsyncThrowingStream { continuation in
///             let task = Task {
///                 for try await chunk in api.stream(conversation.messages) {
///                     continuation.yield(.token(chunk.text))
///                 }
///                 continuation.finish()
///             }
///             continuation.onTermination = { _ in task.cancel() }
///         }
///     }
/// }
/// ```
///
/// Stopping a reply cancels the task consuming the stream, so honour cancellation.
public protocol KitoAIStream: Sendable {
    func reply(to conversation: KitoAIConversation) -> AsyncThrowingStream<KitoAIStreamEvent, Error>
}

/// Adapts any `AsyncSequence` of text chunks into a `KitoAIStream`.
///
/// ```swift
/// let stream = KitoAITokenStream { conversation in
///     myClient.streamText(for: conversation.messages)   // some AsyncSequence<String>
/// }
/// ```
public struct KitoAITokenStream: KitoAIStream {
    private let make: @Sendable (KitoAIConversation) -> AsyncThrowingStream<KitoAIStreamEvent, Error>

    public init<Tokens: AsyncSequence>(_ tokens: @escaping @Sendable (KitoAIConversation) -> Tokens) where Tokens.Element == String {
        make = { conversation in
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        for try await token in tokens(conversation) {
                            try Task.checkCancellation()
                            continuation.yield(.token(token))
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }

    public func reply(to conversation: KitoAIConversation) -> AsyncThrowingStream<KitoAIStreamEvent, Error> {
        make(conversation)
    }
}

/// An error a stream can throw to show a friendly message in the error bubble.
public struct KitoAIStreamError: LocalizedError, Hashable, Sendable {
    public var message: String

    public init(_ message: String) { self.message = message }

    public var errorDescription: String? { message }

    public static let networkLost = KitoAIStreamError("The connection was lost before the reply finished.")
}
