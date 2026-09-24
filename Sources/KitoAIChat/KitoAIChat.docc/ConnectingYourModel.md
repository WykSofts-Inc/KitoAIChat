# Connecting Your Model

Stream replies from any provider into the chat interface.

## Overview

KitoAIChat never talks to a network itself. Replies come from a type that
conforms to ``KitoAIStream``, which receives the current
``KitoAIConversation`` and returns an `AsyncThrowingStream` of
``KitoAIStreamEvent`` values.

### Conform to KitoAIStream

Wrap your provider's streaming API and yield events as they arrive:

```swift
struct MyBackend: KitoAIStream {
    func reply(to conversation: KitoAIConversation) -> AsyncThrowingStream<KitoAIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await chunk in api.stream(conversation.messages) {
                        continuation.yield(.token(chunk.text))
                    }
                    continuation.yield(.followUps(["Tell me more"]))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

KitoAIChatView(stream: MyBackend())
```

Stopping a reply cancels the task consuming the stream, so honour
cancellation in your implementation.

### Choose the events to send

- `.token(String)` appends text to the reply. Any chunk size works.
- `.toolCall(KitoAIToolCall)` starts or updates a tool chip. Send the same
  identifier again with a `.done` status to finish it.
- `.citations([KitoAICitation])` attaches sources to the reply.
- `.image(KitoAIImage)` adds an image to the reply.
- `.followUps([String])` offers suggested next prompts once the reply finishes.

### Wrap an existing text sequence

If your client already produces an `AsyncSequence` of strings, adapt it with
``KitoAITokenStream`` instead of writing a conformance:

```swift
let stream = KitoAITokenStream { conversation in
    client.streamText(for: conversation.messages)
}
```

### Develop without a backend

Use ``KitoMockAIStream`` in previews and demos. It streams canned replies with
realistic timing, runs tool calls, and cites sources, so every part of the
interface can be exercised before a model is connected.
