# ``KitoAIChat``

A model-agnostic AI chat interface kit for SwiftUI with streaming markdown replies, a composer, and a conversation sidebar.

## Overview

KitoAIChat provides the full chat experience: replies that stream in token by
token with markdown, code blocks, and tables; tool-use chips and sources; Stop,
Regenerate, feedback, and edit-and-resend; a composer with dictation and a
model picker; a conversation sidebar; and a welcome screen with starter
prompts.

The package has no network code or SDK dependency of its own. You connect your
provider by conforming to ``KitoAIStream`` and yielding ``KitoAIStreamEvent``
values as they arrive. ``KitoMockAIStream`` types out canned replies with
realistic timing, so the whole interface works in previews and demos before
you connect a model.

```swift
import KitoAIChat

KitoAIChatView(stream: KitoMockAIStream(), userName: "Wycliff N")
```

``KitoAIChatSession`` is the observable state behind the view. Own it yourself
to send, stop, regenerate, or edit messages programmatically, and to save
history: ``KitoAIConversation``, ``KitoAIMessage``, and every content block are
`Codable`. The individual views and the text-processing logic, such as
``KitoAIMarkdown`` and ``KitoAIStreamAssembler``, are also public for building
your own layouts. Colours, fonts, spacing, and radii come from the Kito theme.

## Topics

### Essentials

- <doc:ConnectingYourModel>
- ``KitoAIChatView``
- ``KitoAIChatSession``

### Streaming

- ``KitoAIStream``
- ``KitoAIStreamEvent``
- ``KitoAITokenStream``
- ``KitoMockAIStream``
- ``KitoAIStreamError``

### Conversations and Messages

- ``KitoAIConversation``
- ``KitoAIMessage``
- ``KitoAIRole``
- ``KitoAIContentBlock``
- ``KitoAIToolCall``
- ``KitoAIToolStatus``
- ``KitoAICitation``
- ``KitoAIImage``
- ``KitoAIAttachment``
- ``KitoAIFeedback``
- ``KitoAISuggestion``
- ``KitoAIModelOption``

### Views

- ``KitoAIMessageView``
- ``KitoAIMarkdownView``
- ``KitoAICodeBlock``
- ``KitoAIComposer``
- ``KitoAIModelPicker``
- ``KitoAIConversationList``
- ``KitoAIConversationRow``
- ``KitoAIWelcome``
- ``KitoAIOrb``
- ``KitoAIThinkingIndicator``
- ``KitoAIStreamingCursor``
- ``KitoAIErrorBubble``

### Chips

- ``KitoAIToolChip``
- ``KitoAICitationChips``
- ``KitoAIFollowUpChips``
- ``KitoAISuggestedPrompts``
- ``KitoAIAttachmentChip``

### Text Processing

- ``KitoAIMarkdown``
- ``KitoAIMarkdownBlock``
- ``KitoAIMarkdownListItem``
- ``KitoAIMarkdownTable``
- ``KitoAIStreamAssembler``
- ``KitoAISyntaxHighlighter``
- ``KitoAISyntaxToken``
- ``KitoAISyntaxKind``
- ``KitoAITitle``
- ``KitoAITextStats``
- ``KitoAIGreeting``
- ``KitoAIDateFormat``
- ``KitoAIConversationGrouping``
- ``KitoAIConversationSection``
- ``KitoAIAutoScrollPolicy``
