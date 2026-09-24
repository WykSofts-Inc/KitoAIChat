//
//  KitoAIStreamAssemblerTests.swift
//  KitoAIChat
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import XCTest
@testable import KitoAIChat

final class KitoAIStreamAssemblerTests: XCTestCase {

    private func streaming(_ text: String) -> String {
        KitoAIStreamAssembler.displayText(for: text, isStreaming: true)
    }

    func testFinishedTextIsUnchanged() {
        let text = "## Diani\n\n| a |\n#"
        XCTAssertEqual(KitoAIStreamAssembler.displayText(for: text, isStreaming: false), text)
    }

    func testHoldsBackALoneHashUntilItsAHeading() {
        XCTAssertEqual(streaming("Intro\n#"), "Intro")
        XCTAssertEqual(streaming("Intro\n##"), "Intro")
        XCTAssertEqual(streaming("Intro\n## Pl"), "Intro\n## Pl")
    }

    func testHoldsBackListAndRuleMarkers() {
        XCTAssertEqual(streaming("Steps:\n-"), "Steps:")
        XCTAssertEqual(streaming("Steps:\n--"), "Steps:")
        XCTAssertEqual(streaming("Steps:\n- Bo"), "Steps:\n- Bo")
        XCTAssertEqual(streaming("Steps:\n1"), "Steps:")
        XCTAssertEqual(streaming("Steps:\n1."), "Steps:")
        XCTAssertEqual(streaming("Steps:\n1. Bo"), "Steps:\n1. Bo")
        XCTAssertEqual(streaming("Steps:\n10 people came"), "Steps:\n10 people came")
        XCTAssertEqual(streaming("Quote:\n>"), "Quote:")
    }

    func testHoldsTheFenceLineUntilItEnds() {
        XCTAssertEqual(streaming("Code:\n`"), "Code:")
        XCTAssertEqual(streaming("Code:\n```sw"), "Code:")
        let opened = KitoAIMarkdown.blocks(from: streaming("Code:\n```swift\n"))
        XCTAssertEqual(opened, [.paragraph("Code:"), .code(language: "swift", code: "", isClosed: false)])
    }

    func testMarkdownLookalikesInsideAFenceAreShownImmediately() {
        XCTAssertEqual(streaming("```bash\n# install\n-"), "```bash\n# install\n-")
        XCTAssertEqual(streaming("```bash\nls\n``"), "```bash\nls")
    }

    func testTableHeaderWaitsForItsSeparator() {
        XCTAssertEqual(streaming("Fares:\n| Item | KES"), "Fares:")
        XCTAssertEqual(streaming("Fares:\n| Item | KES |\n"), "Fares:")
        XCTAssertEqual(streaming("Fares:\n| Item | KES |\n|--"), "Fares:")
        let table = KitoAIMarkdown.blocks(from: streaming("Fares:\n| Item | KES |\n|--|--|\n"))
        XCTAssertEqual(table.map(\.kind), ["paragraph", "table"])
    }

    func testTableRowsArriveWhole() {
        let text = "| Item | KES |\n|--|--|\n| SGR | 3,000 |\n| Fer"
        guard case .table(let table) = KitoAIMarkdown.blocks(from: streaming(text)).first else { return XCTFail("Expected a table") }
        XCTAssertEqual(table.rows, [["SGR", "3,000"]])
    }

    func testClosesOpenInlineMarkers() {
        XCTAssertEqual(KitoAIStreamAssembler.closingOpenInlineMarkers(in: "Take the **SGR"), "Take the **SGR**")
        XCTAssertEqual(KitoAIStreamAssembler.closingOpenInlineMarkers(in: "Take the **"), "Take the ")
        XCTAssertEqual(KitoAIStreamAssembler.closingOpenInlineMarkers(in: "It's *fa"), "It's *fa*")
        XCTAssertEqual(KitoAIStreamAssembler.closingOpenInlineMarkers(in: "Use `let x"), "Use `let x`")
        XCTAssertEqual(KitoAIStreamAssembler.closingOpenInlineMarkers(in: "Use `a*b"), "Use `a*b`")
        XCTAssertEqual(KitoAIStreamAssembler.closingOpenInlineMarkers(in: "~~bus"), "~~bus~~")
        XCTAssertEqual(KitoAIStreamAssembler.closingOpenInlineMarkers(in: "- **Simba** — li"), "- **Simba** — li")
        XCTAssertEqual(KitoAIStreamAssembler.closingOpenInlineMarkers(in: "* item *ital"), "* item *ital*")
    }

    func testShowsAnUnfinishedLinkAsItsText() {
        XCTAssertEqual(KitoAIStreamAssembler.closingOpenInlineMarkers(in: "see [Kenya Rail"), "see Kenya Rail")
        XCTAssertEqual(KitoAIStreamAssembler.closingOpenInlineMarkers(in: "see [KR](https://krc"), "see KR")
        XCTAssertEqual(KitoAIStreamAssembler.closingOpenInlineMarkers(in: "see [KR](https://krc.co.ke) now"), "see [KR](https://krc.co.ke) now")
    }

    func testAssemblerAccumulatesTokens() {
        var assembler = KitoAIStreamAssembler()
        ["Hab", "ari ", "**Wy", "cliff**"].forEach { assembler.append($0) }
        XCTAssertEqual(assembler.text, "Habari **Wycliff**")
        XCTAssertEqual(assembler.blocks, [.paragraph("Habari **Wycliff**")])
        assembler.append("\n#")
        XCTAssertEqual(assembler.blocks.count, 1)
        assembler.finish()
        XCTAssertEqual(assembler.blocks.map(\.kind), ["paragraph", "heading"])
    }

    /// Streams a realistic reply one character at a time: blocks never disappear, and every block
    /// before the one being written already has its final kind — nothing flips as text arrives.
    func testStreamingCharacterByCharacterNeverFlickers() {
        let document = """
        ## Weekend in Diani

        Take the **SGR** from Nairobi — it's *fast*.

        1. Book on `metickets`
        2. Pack light
           - sunscreen
           - kikoi

        | Item | KES |
        |:--|--:|
        | SGR | 3,000 |

        > Tip: book early.

        ```swift
        let fare = 3_000
        ```

        ---
        Enjoy!
        """
        let final = KitoAIMarkdown.blocks(from: document)
        XCTAssertEqual(final.map(\.kind), ["heading", "paragraph", "list", "table", "quote", "code", "rule", "paragraph"])

        var assembler = KitoAIStreamAssembler()
        var previousCount = 0
        for character in document {
            assembler.append(String(character))
            let blocks = assembler.blocks
            XCTAssertGreaterThanOrEqual(blocks.count, previousCount, "A block vanished after \(assembler.text.debugDescription)")
            for index in 0..<max(0, blocks.count - 1) {
                XCTAssertEqual(blocks[index].kind, final[index].kind, "Block \(index) flipped after \(assembler.text.debugDescription)")
            }
            if let last = blocks.last, blocks.count <= final.count {
                XCTAssertEqual(last.kind, final[blocks.count - 1].kind, "The streaming block has the wrong kind after \(assembler.text.debugDescription)")
            }
            previousCount = blocks.count
        }
        assembler.finish()
        XCTAssertEqual(assembler.blocks, final)
    }

    func testMockChunksJoinBackIntoTheReply() {
        for reply in KitoMockAIStream.defaultReplies {
            let chunks = KitoMockAIStream.chunks(for: reply.text, seed: 42)
            XCTAssertEqual(chunks.map(\.text).joined(), reply.text)
            XCTAssertTrue(chunks.allSatisfy { $0.delay > 0 })
        }
    }

    func testMockChunksAreRepeatableForASeed() {
        let text = KitoMockAIStream.defaultReplies[0].text
        XCTAssertEqual(KitoMockAIStream.chunks(for: text, seed: 7), KitoMockAIStream.chunks(for: text, seed: 7))
        XCTAssertNotEqual(KitoMockAIStream.chunks(for: text, seed: 7), KitoMockAIStream.chunks(for: text, seed: 8))
    }

    func testMockPicksARepliesByKeyword() {
        let mock = KitoMockAIStream()
        XCTAssertTrue(mock.reply(for: "Teach me some SWAHILI").text.contains("Asante sana"))
        XCTAssertTrue(mock.reply(for: "M-Pesa STK push please").text.contains("```swift"))
        XCTAssertTrue(mock.reply(for: "What's the capital of Rwanda?").text.contains("KitoMockAIStream"))
    }
}
