//
//  KitoAITextTests.swift
//  KitoAIChat
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import XCTest
@testable import KitoAIChat

final class KitoAITextTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Africa/Nairobi") ?? .current
        return calendar
    }

    private let locale = Locale(identifier: "en_GB")

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? Date()
    }

    // MARK: Titles

    func testTitleDropsGreetingsAndRequests() {
        XCTAssertEqual(KitoAITitle.make(from: "Hey, can you help me plan a weekend in Diani?"), "Plan a weekend in Diani")
        XCTAssertEqual(KitoAITitle.make(from: "Please explain **M-Pesa** STK push in Swift"), "Explain M-Pesa STK push in Swift")
        XCTAssertEqual(KitoAITitle.make(from: "habari! teach me Swahili phrases"), "Teach me Swahili phrases")
    }

    func testTitleKeepsWordsThatOnlyStartLikeFillers() {
        XCTAssertEqual(KitoAITitle.make(from: "hiking routes near Nanyuki"), "Hiking routes near Nanyuki")
        XCTAssertEqual(KitoAITitle.make(from: "Hi"), "Hi")
    }

    func testTitleTruncatesAtAWord() {
        let title = KitoAITitle.make(from: "What are the best places to eat nyama choma in Nairobi on a Sunday afternoon")
        XCTAssertEqual(title, "What are the best places to eat nyama…")
    }

    func testTitleUsesTheFirstLineAndFallsBack() {
        XCTAssertEqual(KitoAITitle.make(from: "Fix this bug\n\n```swift\nlet x = 1\n```"), "Fix this bug")
        XCTAssertEqual(KitoAITitle.make(from: "   \n "), "New chat")
    }

    // MARK: Counts

    func testWordCount() {
        XCTAssertEqual(KitoAITextStats.wordCount("Habari yako, Wycliff! Karibu Nairobi."), 5)
        XCTAssertEqual(KitoAITextStats.wordCount(""), 0)
        XCTAssertEqual(KitoAITextStats.wordCount("**Bold** and *italic*"), 3)
    }

    func testTokenEstimate() {
        XCTAssertEqual(KitoAITextStats.estimatedTokens(""), 0)
        XCTAssertEqual(KitoAITextStats.estimatedTokens("   \n"), 0)
        XCTAssertEqual(KitoAITextStats.estimatedTokens("abcd"), 2)
        XCTAssertEqual(KitoAITextStats.estimatedTokens("Habari yako"), 3)
        XCTAssertEqual(KitoAITextStats.estimatedTokens(String(repeating: "word ", count: 80)), 107)
    }

    func testReadingTime() {
        XCTAssertEqual(KitoAITextStats.readingTime(""), 0)
        XCTAssertEqual(KitoAITextStats.readingTime("one two"), 3)
        XCTAssertEqual(KitoAITextStats.readingTime(String(repeating: "neno ", count: 230)), 60, accuracy: 0.001)
    }

    // MARK: Greeting

    func testGreetingFollowsTheTimeOfDay() {
        XCTAssertEqual(KitoAIGreeting.period(for: date(2026, 9, 24, 8), calendar: calendar), .morning)
        XCTAssertEqual(KitoAIGreeting.period(for: date(2026, 9, 24, 13), calendar: calendar), .afternoon)
        XCTAssertEqual(KitoAIGreeting.period(for: date(2026, 9, 24, 19), calendar: calendar), .evening)
        XCTAssertEqual(KitoAIGreeting.period(for: date(2026, 9, 24, 2), calendar: calendar), .evening)
    }

    func testGreetingUsesTheFirstName() {
        XCTAssertEqual(KitoAIGreeting.text(for: date(2026, 9, 24, 20), name: "Wycliff N", calendar: calendar), "Good evening, Wycliff")
        XCTAssertEqual(KitoAIGreeting.text(for: date(2026, 9, 24, 9), name: nil, calendar: calendar), "Good morning")
    }

    // MARK: Dates and grouping

    func testRowTimestamps() {
        let now = date(2026, 9, 24, 15)
        XCTAssertEqual(KitoAIDateFormat.rowTimestamp(for: date(2026, 9, 24, 14, 5), now: now, calendar: calendar, locale: locale), "14:05")
        XCTAssertEqual(KitoAIDateFormat.rowTimestamp(for: date(2026, 9, 23, 9), now: now, calendar: calendar, locale: locale), "Yesterday")
        XCTAssertEqual(KitoAIDateFormat.rowTimestamp(for: date(2026, 9, 21), now: now, calendar: calendar, locale: locale), "Mon")
        XCTAssertEqual(KitoAIDateFormat.rowTimestamp(for: date(2026, 8, 12), now: now, calendar: calendar, locale: locale), "12 Aug")
        XCTAssertEqual(KitoAIDateFormat.rowTimestamp(for: date(2025, 9, 12), now: now, calendar: calendar, locale: locale), "12/09/25")
    }

    func testConversationsAreGroupedByRecency() {
        let now = date(2026, 9, 24, 15)
        let conversations = [
            KitoAIConversation(id: "old", title: "Old", updatedAt: date(2025, 12, 1)),
            KitoAIConversation(id: "today", title: "Today", updatedAt: date(2026, 9, 24, 9)),
            KitoAIConversation(id: "pinned", title: "Pinned", updatedAt: date(2026, 1, 3), isPinned: true),
            KitoAIConversation(id: "march", title: "March", updatedAt: date(2026, 3, 10)),
            KitoAIConversation(id: "yesterday", title: "Yesterday", updatedAt: date(2026, 9, 23)),
            KitoAIConversation(id: "week", title: "Week", updatedAt: date(2026, 9, 20)),
            KitoAIConversation(id: "month", title: "Month", updatedAt: date(2026, 9, 10)),
            KitoAIConversation(id: "today2", title: "Today 2", updatedAt: date(2026, 9, 24, 14)),
        ]
        let sections = KitoAIConversationGrouping.sections(for: conversations, now: now, calendar: calendar, locale: locale)
        XCTAssertEqual(sections.map(\.title), ["Pinned", "Today", "Yesterday", "Previous 7 days", "Previous 30 days", "March", "December 2025"])
        XCTAssertEqual(sections[1].conversations.map(\.id), ["today2", "today"])
    }

    func testFilterMatchesTitleAndSnippet() {
        let diani = KitoAIConversation(title: "Diani weekend", messages: [.user("Plan it"), .assistant("Take the **SGR**")])
        let swahili = KitoAIConversation(messages: [.user("Teach me Swahili")])
        XCTAssertEqual(KitoAIConversationGrouping.filter([diani, swahili], query: "sgr").map(\.id), [diani.id])
        XCTAssertEqual(KitoAIConversationGrouping.filter([diani, swahili], query: "swahili").map(\.id), [swahili.id])
        XCTAssertEqual(KitoAIConversationGrouping.filter([diani, swahili], query: "  ").count, 2)
    }

    // MARK: Auto-scroll

    func testFollowsWhileContentGrows() {
        var policy = KitoAIAutoScrollPolicy()
        policy.observe(distanceFromBottom: 0, contentHeight: 1_000, viewportHeight: 700)
        policy.observe(distanceFromBottom: 120, contentHeight: 1_120, viewportHeight: 700)
        XCTAssertTrue(policy.isFollowing)
        XCTAssertFalse(policy.showsJumpToLatest)
    }

    func testPausesWhenTheReaderScrollsUp() {
        var policy = KitoAIAutoScrollPolicy()
        policy.observe(distanceFromBottom: 0, contentHeight: 1_000, viewportHeight: 700)
        policy.observe(distanceFromBottom: 300, contentHeight: 1_000, viewportHeight: 700)
        XCTAssertFalse(policy.shouldFollowContent)
        XCTAssertTrue(policy.showsJumpToLatest)
        policy.observe(distanceFromBottom: 420, contentHeight: 1_120, viewportHeight: 700)
        XCTAssertFalse(policy.isFollowing, "New content must not pull a reader who scrolled up")
    }

    func testKeyboardDoesNotCountAsScrollingUp() {
        var policy = KitoAIAutoScrollPolicy()
        policy.observe(distanceFromBottom: 0, contentHeight: 1_000, viewportHeight: 700)
        policy.observe(distanceFromBottom: 300, contentHeight: 1_000, viewportHeight: 400)
        XCTAssertTrue(policy.isFollowing)
    }

    func testResumesNearTheBottomOrOnJumpOrSend() {
        var policy = KitoAIAutoScrollPolicy()
        policy.observe(distanceFromBottom: 0, contentHeight: 1_000, viewportHeight: 700)
        policy.observe(distanceFromBottom: 300, contentHeight: 1_000, viewportHeight: 700)
        policy.observe(distanceFromBottom: 30, contentHeight: 1_000, viewportHeight: 700)
        XCTAssertTrue(policy.isFollowing)

        policy.observe(distanceFromBottom: 500, contentHeight: 1_000, viewportHeight: 700)
        policy.jumpToLatest()
        XCTAssertTrue(policy.isFollowing)

        policy.observe(distanceFromBottom: 900, contentHeight: 1_000, viewportHeight: 700)
        XCTAssertFalse(policy.isFollowing)
        policy.didSendMessage()
        XCTAssertTrue(policy.isFollowing)
    }

    func testFirstObservationNeverPauses() {
        var policy = KitoAIAutoScrollPolicy()
        policy.observe(distanceFromBottom: 2_000, contentHeight: 3_000, viewportHeight: 700)
        XCTAssertTrue(policy.isFollowing)
    }

    // MARK: Syntax

    func testSyntaxTokensJoinBackAndClassify() {
        let code = "let name = \"Amani\" // greet\nprint(name, 3_000)"
        let tokens = KitoAISyntaxHighlighter.tokens(in: code, language: "swift")
        XCTAssertEqual(tokens.map(\.text).joined(), code)
        XCTAssertTrue(tokens.contains(KitoAISyntaxToken("let", .keyword)))
        XCTAssertTrue(tokens.contains(KitoAISyntaxToken("\"Amani\"", .string)))
        XCTAssertTrue(tokens.contains(KitoAISyntaxToken("// greet", .comment)))
        XCTAssertTrue(tokens.contains(KitoAISyntaxToken("print", .function)))
        XCTAssertTrue(tokens.contains(KitoAISyntaxToken("3_000", .number)))
    }

    func testHashCommentsForScriptingLanguages() {
        let tokens = KitoAISyntaxHighlighter.tokens(in: "# fare\nfare = 1500", language: "python")
        XCTAssertEqual(tokens.first, KitoAISyntaxToken("# fare", .comment))
        XCTAssertTrue(tokens.contains(KitoAISyntaxToken("1500", .number)))
    }

    func testMarkupIsLeftPlain() {
        XCTAssertEqual(KitoAISyntaxHighlighter.tokens(in: "<b>hi</b>", language: "html"), [KitoAISyntaxToken("<b>hi</b>", .plain)])
    }
}
