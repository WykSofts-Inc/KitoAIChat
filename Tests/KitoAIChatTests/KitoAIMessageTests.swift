//
//  KitoAIMessageTests.swift
//  KitoAIChat
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import XCTest
import SwiftUI
@testable import KitoAIChat

final class KitoAIMessageTests: XCTestCase {

    func testTokensExtendTheLastMarkdownBlock() {
        var message = KitoAIMessage(role: .assistant, isStreaming: true)
        message.apply(.token("Habari "))
        message.apply(.token("Wycliff"))
        XCTAssertEqual(message.blocks, [.markdown("Habari Wycliff")])
        XCTAssertTrue(message.hasVisibleContent)
    }

    func testToolCallsUpdateInPlaceAndTextStartsAfterThem() {
        var message = KitoAIMessage(role: .assistant, isStreaming: true)
        let search = KitoAIToolCall.webSearch(id: "search")
        message.apply(.toolCall(search))
        XCTAssertTrue(message.hasVisibleContent)
        message.apply(.toolCall(search.with(status: .done, detail: "4 sources")))
        message.apply(.token("Diani is "))
        message.apply(.token("lovely."))
        XCTAssertEqual(message.blocks.count, 2)
        XCTAssertEqual(message.toolCalls.first?.status, .done)
        XCTAssertEqual(message.toolCalls.first?.title, "Searched the web")
        XCTAssertEqual(message.text, "Diani is lovely.")
    }

    func testCitationsMergeWithoutDuplicates() {
        var message = KitoAIMessage(role: .assistant)
        let first = KitoAICitation(id: "1", title: "Magical Kenya", url: URL(string: "https://www.magicalkenya.com"))
        let second = KitoAICitation(id: "2", title: "KWS", url: URL(string: "https://kws.go.ke"))
        message.apply(.citations([first]))
        message.apply(.citations([first, second]))
        XCTAssertEqual(message.citations.map(\.id), ["1", "2"])
        XCTAssertEqual(first.displaySource, "magicalkenya.com")
    }

    func testFollowUpsAndEmptyTokens() {
        var message = KitoAIMessage(role: .assistant, isStreaming: true)
        message.apply(.token(""))
        XCTAssertFalse(message.hasVisibleContent)
        message.apply(.followUps(["What should I pack?"]))
        XCTAssertEqual(message.followUps, ["What should I pack?"])
    }

    func testFailedToolTitle() {
        XCTAssertEqual(KitoAIToolCall.webSearch().with(status: .failed).title, "Searching the web didn't finish")
    }

    func testTextJoinsMarkdownAndCode() {
        let message = KitoAIMessage(role: .assistant, blocks: [.markdown("Run:"), .code(language: "bash", code: "swift build")])
        XCTAssertEqual(message.text, "Run:\n\n```bash\nswift build\n```")
    }

    func testConversationTitleSnippetAndTruncation() {
        let first = KitoAIMessage.user("Can you plan a weekend in Diani?")
        let reply = KitoAIMessage.assistant("## Plan\nTake the **SGR**.")
        let followUp = KitoAIMessage.user("Make it cheaper")
        var conversation = KitoAIConversation(messages: [first, reply, followUp])
        XCTAssertEqual(conversation.displayTitle, "Plan a weekend in Diani")
        XCTAssertEqual(conversation.snippet, "Make it cheaper")
        XCTAssertEqual(conversation.lastAssistantMessage?.id, reply.id)
        conversation.removeMessages(after: first.id)
        XCTAssertEqual(conversation.messages.map(\.id), [first.id])
        XCTAssertEqual(KitoAIConversation().displayTitle, "New chat")
    }

    func testConversationRoundTripsThroughCodable() throws {
        let conversation = KitoAIConversation(
            title: "SGR",
            messages: [
                .user("Compare SGR and matatu", attachments: [KitoAIAttachment(name: "fares.pdf", kind: .pdf, byteCount: 2_048)]),
                KitoAIMessage(role: .assistant, blocks: [.toolCall(.webSearch(id: "s")), .markdown("| a |\n|--|"), .citations([KitoAICitation(title: "KRC")])]),
            ],
            model: "Kito Pro"
        )
        let data = try JSONEncoder().encode(conversation)
        XCTAssertEqual(try JSONDecoder().decode(KitoAIConversation.self, from: data), conversation)
    }

    func testAttachmentSubtitle() {
        XCTAssertEqual(KitoAIAttachment(name: "a.png", kind: .image).subtitle, "Image")
        XCTAssertTrue(KitoAIAttachment(name: "b.pdf", kind: .pdf, byteCount: 1_200_000).subtitle.hasPrefix("PDF · "))
    }

    func testDictationJoinsOntoExistingText() {
        XCTAssertEqual(KitoAIComposer<EmptyView>.joined("Plan a trip to", "Diani"), "Plan a trip to Diani")
        XCTAssertEqual(KitoAIComposer<EmptyView>.joined("", "Diani"), "Diani")
        XCTAssertEqual(KitoAIComposer<EmptyView>.joined("Hi", ""), "Hi")
    }
}

@MainActor
final class KitoAIChatSessionTests: XCTestCase {

    private func fastMock(failures: Int = 0) -> KitoMockAIStream {
        KitoMockAIStream(speed: 60, thinkingDelay: 0, failures: failures, seed: 3)
    }

    private func waitUntilIdle(_ session: KitoAIChatSession, timeout: TimeInterval = 10) async {
        let deadline = Date().addingTimeInterval(timeout)
        while session.isGenerating, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testSendStreamsAReplyAndTitlesTheConversation() async {
        let session = KitoAIChatSession(stream: fastMock())
        session.send("Teach me Swahili phrases")
        XCTAssertTrue(session.isGenerating)
        await waitUntilIdle(session)
        XCTAssertEqual(session.conversation.title, "Teach me Swahili phrases")
        XCTAssertEqual(session.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(session.messages.last?.text, KitoMockAIStream.swahili.text)
        XCTAssertEqual(session.followUps, KitoMockAIStream.swahili.followUps)
    }

    func testStopKeepsThePartialReply() async {
        let session = KitoAIChatSession(stream: KitoMockAIStream(speed: 1, thinkingDelay: 0, seed: 3))
        session.send("Chapati recipe")
        try? await Task.sleep(nanoseconds: 300_000_000)
        session.stop()
        XCTAssertFalse(session.isGenerating)
        XCTAssertEqual(session.messages.last?.wasStopped, true)
        XCTAssertTrue(session.followUps.isEmpty)
    }

    func testFailureShowsAnErrorAndRetrySucceeds() async {
        let session = KitoAIChatSession(stream: fastMock(failures: 1))
        session.send("SGR or matatu?")
        await waitUntilIdle(session)
        XCTAssertNotNil(session.messages.last?.errorMessage)
        session.retry()
        await waitUntilIdle(session)
        XCTAssertNil(session.messages.last?.errorMessage)
        XCTAssertEqual(session.messages.count, 2)
    }

    func testEditAndResendReplacesTheLastTurn() async {
        let session = KitoAIChatSession(stream: fastMock())
        session.send("Chapati recipe")
        await waitUntilIdle(session)
        XCTAssertEqual(session.beginEditing(), "Chapati recipe")
        session.send("Landlord email about a leaking tap")
        await waitUntilIdle(session)
        XCTAssertEqual(session.messages.count, 2)
        XCTAssertEqual(session.messages.first?.text, "Landlord email about a leaking tap")
        XCTAssertEqual(session.messages.last?.text, KitoMockAIStream.landlord.text)
        XCTAssertNil(session.editingMessageID)
    }

    func testFeedbackToggles() async {
        let session = KitoAIChatSession(stream: fastMock())
        session.send("Chapati recipe")
        await waitUntilIdle(session)
        guard let id = session.messages.last?.id else { return XCTFail("No reply") }
        session.setFeedback(.positive, for: id)
        XCTAssertEqual(session.messages.last?.feedback, .positive)
        session.setFeedback(.positive, for: id)
        XCTAssertEqual(session.messages.last?.feedback, KitoAIFeedback.none)
    }
}
