# KitoAIChat

**[Documentation](https://wyksofts-inc.github.io/KitoAIChat/documentation/kitoaichat/)**

An AI chat UI kit for SwiftUI that works with any model: streaming replies with markdown, code
blocks and tables, tool-use chips, sources, Stop, Regenerate, feedback, edit-and-resend, a
composer with dictation and a model picker, a conversation sidebar and a welcome screen. It has no
network code or SDK dependency of its own — you connect your provider by handing it a stream of
tokens. Part of the [Kito](https://github.com/WykSofts-Inc/KitoDevKit) ecosystem.

## A chat in one view

```swift
import KitoAIChat

KitoAIChatView(stream: KitoMockAIStream(), userName: "Wycliff N")
```

`KitoMockAIStream` types out canned replies with realistic jitter, runs a web search first when
it fits, and cites sources, so the whole UI works in previews and demos before you connect a model.
Ask it about a weekend in Diani, M-Pesa STK push in Swift, Swahili phrases, the SGR or a matatu,
chapati, or a note to your landlord.

What you get:

- An empty conversation opens on an animated orb, "Good evening, Wycliff", and starter prompt cards.
- Replies stream in token by token with a cursor. Unfinished markdown is held back for a moment, so
  a lone `#`, `**bo` or a table header never flashes up as plain text first.
- "Thinking…" with a light sweep until the first token; tool chips go from "Searching the web…" to
  "Searched the web · 4 sources".
- Send morphs into Stop while a reply is generating. Stopped replies keep what arrived.
- Under each reply: Copy, 👍, 👎 and Regenerate. Under your last message: Copy and Edit — edit it
  and send, and the conversation continues from there.
- A failed reply shows what went wrong and a Retry button.
- Follow-up chips after the latest reply.
- The conversation follows new text as it streams, stops following the moment you scroll up, and
  offers a "Jump to latest" pill.

## Connect your model

Conform to `KitoAIStream` and yield events as they arrive:

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

Events are `.token(String)`, `.toolCall(KitoAIToolCall)` (send the same `id` again with `.done` to
finish it), `.citations([KitoAICitation])`, `.image(KitoAIImage)` and `.followUps([String])`.
Stopping a reply cancels the task consuming the stream.

Already have an `AsyncSequence` of strings? Wrap it:

```swift
let stream = KitoAITokenStream { conversation in client.streamText(for: conversation.messages) }
```

## The session

`KitoAIChatSession` is the state behind the view — an `@Observable` view model you can own,
save and drive yourself:

```swift
@State private var session = KitoAIChatSession(stream: MyBackend())
@State private var model = "pro"

KitoAIChatView(session: session, userName: "Wycliff N", onAttach: { showPicker = true }) {
    KitoAIModelPicker(KitoAIModelOption.defaults, selection: $model)
}

session.send("Plan a weekend in Diani")
session.stop()
session.regenerate()
session.beginEditing()                     // returns the last message's text
session.setFeedback(.positive, for: id)
session.attachments.append(KitoAIAttachment(name: "Itinerary.pdf", kind: .pdf, byteCount: 482_000))
session.onReplyFinished = { _ in save(session.conversation) }
```

`KitoAIConversation`, `KitoAIMessage` and every content block are `Codable`, so saving history is
one `JSONEncoder` away. The first message titles the conversation ("Hey, can you help me plan a
weekend in Diani?" becomes "Plan a weekend in Diani").

## Messages

```swift
KitoAIMessage.user("Compare the SGR and a matatu", attachments: [file])
KitoAIMessage.assistant("## Weekend in Diani\nTake the **SGR** …")
KitoAIMessage(role: .assistant, blocks: [
    .toolCall(.webSearch(query: "Diani weekend").with(status: .done, detail: "4 sources")),
    .markdown(text),
    .code(language: "swift", code: snippet),
    .image(KitoAIImage(url: url, aspectRatio: 16 / 9, altText: "Galu Beach")),
    .citations([KitoAICitation(title: "Magical Kenya", url: url)]),
])
KitoAIMessage.system("Switched to Kito Pro")
```

Roles are `.user`, `.assistant`, `.system` (a centred caption) and `.tool` (a collapsed result).

## Rendering

```swift
KitoAIMarkdownView(reply)                       // headings, lists, tasks, quotes, tables, rules, code
KitoAIMarkdownView(partial, isStreaming: true)  // holds back unfinished syntax, shows a cursor
KitoAICodeBlock(code, language: "swift")        // language label, Copy, syntax colours, sideways scroll
KitoAIMessageView(message, onRegenerate: { … }, onFeedback: { … })
```

Inline bold, italic, `code`, ~~strike~~ and links are rendered with `AttributedString`; blocks are
parsed by `KitoAIMarkdown`, which handles fenced code (open or closed), nested and numbered lists,
`- [x]` tasks, block quotes and GitHub tables with column alignment.

## Pieces

```swift
KitoAIWelcome(name: "Wycliff N")                          // orb + "Good evening, Wycliff"
KitoAIOrb(size: 64, isActive: true)
KitoAIThinkingIndicator()
KitoAIToolChip(.webSearch())
KitoAICitationChips(message.citations)
KitoAISuggestedPrompts(KitoAISuggestion.defaults) { session.send($0.prompt) }
KitoAIFollowUpChips(message.followUps) { session.send($0) }
KitoAIAttachmentChip(file) { remove(file) }
KitoAIErrorBubble("The connection was lost.") { session.retry() }
KitoAIStreamingCursor()
```

## Composer

```swift
KitoAIComposer(text: $draft, attachments: $files, isGenerating: generating,
               onAttach: { showPicker = true }, onStop: { stop() }) { prompt in
    send(prompt)
} accessory: {
    KitoAIModelPicker(models, selection: $model)
}
```

The field grows to eight lines and shows a token estimate for long prompts. The mic dictates into
the field with the Speech framework; add **`NSSpeechRecognitionUsageDescription`** and
**`NSMicrophoneUsageDescription`** to your Info.plist. Without them — or without permission or a
microphone — it shows a short hint instead of failing. Pass `allowsVoice: false` to hide it.

## Sidebar

```swift
KitoAIConversationList(conversations: history, selection: $openID,
                       onNewChat: { startChat() },
                       onTogglePin: { pin($0) }, onDelete: { delete($0) })

KitoAIConversationRow(conversation, isSelected: true)   // in your own List
```

Conversations are grouped into Pinned, Today, Yesterday, Previous 7 days, Previous 30 days and one
section per month, and the search field matches titles and the latest text.

## Logic without UI

```swift
KitoAIMarkdown.blocks(from: text)                          // [.heading, .paragraph, .list, .code, .table, …]
KitoAIMarkdown.plainText(text)                             // markdown stripped, for previews
KitoAIStreamAssembler.displayText(for: partial, isStreaming: true)
KitoAITitle.make(from: "Hey, can you help me plan a weekend in Diani?")   // "Plan a weekend in Diani"
KitoAITextStats.wordCount(text)
KitoAITextStats.estimatedTokens(text)                      // provider-neutral estimate
KitoAIGreeting.text(name: "Wycliff N")                     // "Good evening, Wycliff"
KitoAIConversationGrouping.sections(for: history)
KitoAIDateFormat.rowTimestamp(for: date)                   // "14:05", "Yesterday", "Mon", "12 Sep"
KitoAISyntaxHighlighter.tokens(in: code, language: "swift")

var policy = KitoAIAutoScrollPolicy()
policy.observe(distanceFromBottom: 420, contentHeight: 2_000, viewportHeight: 700)
policy.showsJumpToLatest
```

## Accessibility and theming

Replies, tool chips and code blocks have VoiceOver labels; code blocks and messages offer Copy as
an action; the orb, shimmer, cursor and card entrances hold still with Reduce Motion. Colours,
fonts, spacing and radii come from `kitoTheme`, so light and dark mode follow your theme. Every
public view takes an optional `tint`; without one, links use the theme's primary colour and the
send button uses the text colour — black in light mode, white in dark.

## Right-to-left

Everything mirrors with the layout direction: bubbles, chips, the composer, the sidebar and the
shimmer sweep. Markdown table columns map `:--` / `--:` to the leading / trailing edge, so they
follow the reading direction. Code blocks keep their source left-to-right (the header still
mirrors), and follow-up chips flip their arrow.

## Installation

```swift
.package(url: "https://github.com/WykSofts-Inc/KitoAIChat.git", from: "0.1.0")
```

## License

MIT — see [LICENSE](LICENSE).
