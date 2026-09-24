//
//  KitoAIMarkdownTests.swift
//  KitoAIChat
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import XCTest
@testable import KitoAIChat

final class KitoAIMarkdownTests: XCTestCase {

    func testParagraphsAreSplitByBlankLines() {
        let blocks = KitoAIMarkdown.blocks(from: "Habari yako?\nNzuri sana.\n\nAsante!")
        XCTAssertEqual(blocks, [.paragraph("Habari yako?\nNzuri sana."), .paragraph("Asante!")])
    }

    func testHeadingsStripHashes() {
        let blocks = KitoAIMarkdown.blocks(from: "# Diani\n### Friday ###\n#hashtag")
        XCTAssertEqual(blocks, [.heading(level: 1, text: "Diani"), .heading(level: 3, text: "Friday"), .paragraph("#hashtag")])
    }

    func testClosedCodeFenceKeepsLanguageAndIndentation() {
        let markdown = "Try this:\n\n```swift\nfunc greet() {\n    print(\"Habari\")\n}\n```\nDone."
        let blocks = KitoAIMarkdown.blocks(from: markdown)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[1], .code(language: "swift", code: "func greet() {\n    print(\"Habari\")\n}", isClosed: true))
        XCTAssertEqual(blocks[2], .paragraph("Done."))
    }

    func testUnclosedFenceIsOpenCode() {
        let blocks = KitoAIMarkdown.blocks(from: "```python\nprint('hi')")
        XCTAssertEqual(blocks, [.code(language: "python", code: "print('hi')", isClosed: false)])
    }

    func testMarkdownInsideFenceIsNotParsed() {
        let blocks = KitoAIMarkdown.blocks(from: "~~~\n# not a heading\n- not a list\n~~~")
        XCTAssertEqual(blocks, [.code(language: nil, code: "# not a heading\n- not a list", isClosed: true)])
    }

    func testBulletListWithContinuationAndNesting() {
        let markdown = "- Simba\n  the lion\n- Tembo\n  - elephant calf\n* Twiga"
        guard case .list(let items) = KitoAIMarkdown.blocks(from: markdown).first else { return XCTFail("Expected a list") }
        XCTAssertEqual(items.map(\.text), ["Simba the lion", "Tembo", "elephant calf", "Twiga"])
        XCTAssertEqual(items.map(\.level), [0, 0, 1, 0])
        XCTAssertTrue(items.allSatisfy { !$0.isOrdered })
    }

    func testOrderedAndBulletListsAreSeparateBlocks() {
        let blocks = KitoAIMarkdown.blocks(from: "1. Book\n2) Pay\n- Pack")
        XCTAssertEqual(blocks.map(\.kind), ["list", "list"])
        guard case .list(let ordered) = blocks[0] else { return XCTFail("Expected a list") }
        XCTAssertEqual(ordered.map(\.number), [1, 2])
    }

    func testTaskItems() {
        guard case .list(let items) = KitoAIMarkdown.blocks(from: "- [x] Book SGR\n- [ ] Pack sunscreen").first else {
            return XCTFail("Expected a list")
        }
        XCTAssertEqual(items.map(\.isChecked), [true, false])
        XCTAssertEqual(items.map(\.text), ["Book SGR", "Pack sunscreen"])
    }

    func testListMarkersNumberSequentiallyPerLevel() {
        let items = [
            KitoAIMarkdownListItem(text: "a", number: 1),
            KitoAIMarkdownListItem(text: "b", number: 1),
            KitoAIMarkdownListItem(text: "c", level: 1),
            KitoAIMarkdownListItem(text: "d", number: 1),
        ]
        XCTAssertEqual(KitoAIMarkdownListView.markers(for: items), ["1.", "2.", "◦", "3."])
    }

    func testBlockQuoteJoinsLines() {
        let blocks = KitoAIMarkdown.blocks(from: "> Pole pole\n>\n> ndio mwendo")
        XCTAssertEqual(blocks, [.quote("Pole pole\n\nndio mwendo")])
    }

    func testTableWithAlignmentsAndRaggedRows() {
        let markdown = "| Item | KES |\n|:--|--:|\n| SGR | 3,000 |\n| Ferry |\n| a | b | extra |"
        guard case .table(let table) = KitoAIMarkdown.blocks(from: markdown).first else { return XCTFail("Expected a table") }
        XCTAssertEqual(table.header, ["Item", "KES"])
        XCTAssertEqual(table.alignments, [.leading, .trailing])
        XCTAssertEqual(table.rows, [["SGR", "3,000"], ["Ferry", ""], ["a", "b"]])
    }

    func testPipeLineWithoutSeparatorIsAParagraph() {
        XCTAssertEqual(KitoAIMarkdown.blocks(from: "| not a table\nstill text"), [.paragraph("| not a table\nstill text")])
    }

    func testRules() {
        XCTAssertEqual(KitoAIMarkdown.blocks(from: "Above\n\n---\n\n* * *\nBelow").map(\.kind), ["paragraph", "rule", "rule", "paragraph"])
    }

    func testCRLFIsNormalised() {
        XCTAssertEqual(KitoAIMarkdown.blocks(from: "# Hi\r\nThere"), [.heading(level: 1, text: "Hi"), .paragraph("There")])
    }

    func testPlainTextStripsSyntax() {
        let markdown = "## Plan\n**Take** the *SGR* — see [Kenya Railways](https://krc.co.ke) and `metickets`.\n- ~~Bus~~ Train"
        XCTAssertEqual(KitoAIMarkdown.plainText(markdown), "Plan\nTake the SGR — see Kenya Railways and metickets.\nBus Train")
    }
}
