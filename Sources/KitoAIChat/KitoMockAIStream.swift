//
//  KitoMockAIStream.swift
//  KitoAIChat
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// A stand-in model for previews, demos and tests. It picks a canned reply by keyword and types it
/// out token by token with realistic jitter — quick bursts, pauses after sentences, the odd
/// hesitation — optionally running a tool first and citing sources.
///
/// ```swift
/// KitoAIChatView(stream: KitoMockAIStream())
/// KitoAIChatView(stream: KitoMockAIStream(failures: 1))    // the first reply fails, Retry works
/// ```
public struct KitoMockAIStream: KitoAIStream {
    /// A canned reply.
    public struct Reply: Hashable, Sendable {
        /// The reply is chosen when the prompt contains any of these (case-insensitive).
        public var keywords: [String]
        public var text: String
        /// Run before the text, each shown as running and then done with its `detail`.
        public var tools: [KitoAIToolCall]
        public var citations: [KitoAICitation]
        public var followUps: [String]

        public init(keywords: [String], text: String, tools: [KitoAIToolCall] = [], citations: [KitoAICitation] = [], followUps: [String] = []) {
            self.keywords = keywords
            self.text = text
            self.tools = tools
            self.citations = citations
            self.followUps = followUps
        }
    }

    /// One streamed piece of text and the pause before it.
    public struct Chunk: Hashable, Sendable {
        public var text: String
        public var delay: TimeInterval
    }

    public var replies: [Reply]
    /// Above 1 types faster, below 1 slower.
    public var speed: Double
    /// How long it "thinks" before the first token.
    public var thinkingDelay: TimeInterval
    /// Fixes the jitter so runs repeat exactly; nil varies it each time.
    public var seed: UInt64?
    private let failureBudget: FailureBudget

    /// - Parameter failures: how many replies fail part-way before replies start succeeding —
    ///   use it to try the error bubble and Retry.
    public init(
        replies: [Reply] = KitoMockAIStream.defaultReplies,
        speed: Double = 1,
        thinkingDelay: TimeInterval = 0.9,
        failures: Int = 0,
        seed: UInt64? = nil
    ) {
        self.replies = replies
        self.speed = speed
        self.thinkingDelay = thinkingDelay
        self.seed = seed
        self.failureBudget = FailureBudget(failures)
    }

    public func reply(to conversation: KitoAIConversation) -> AsyncThrowingStream<KitoAIStreamEvent, Error> {
        let prompt = conversation.lastUserMessage?.plainText ?? ""
        let reply = self.reply(for: prompt)
        let chunks = Self.chunks(for: reply.text, seed: seed ?? UInt64.random(in: 1...UInt64.max))
        let shouldFail = failureBudget.consume()
        let pace = max(0.05, speed)
        let thinking = thinkingDelay
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Self.pause(thinking / pace)
                    for tool in reply.tools {
                        continuation.yield(.toolCall(KitoAIToolCall(id: tool.id, name: tool.name, runningTitle: tool.runningTitle,
                                                                    doneTitle: tool.doneTitle, symbol: tool.symbol, status: .running)))
                        try await Self.pause(1.4 / pace)
                        continuation.yield(.toolCall(tool.with(status: .done)))
                        try await Self.pause(0.35 / pace)
                    }
                    let failAt = shouldFail ? max(1, chunks.count * 2 / 5) : Int.max
                    for (index, chunk) in chunks.enumerated() {
                        if index == failAt { throw KitoAIStreamError.networkLost }
                        try await Self.pause(chunk.delay / pace)
                        continuation.yield(.token(chunk.text))
                    }
                    if !reply.citations.isEmpty { continuation.yield(.citations(reply.citations)) }
                    if !reply.followUps.isEmpty { continuation.yield(.followUps(reply.followUps)) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The canned reply for a prompt: the first whose keywords match, else a general one.
    public func reply(for prompt: String) -> Reply {
        let lowered = prompt.lowercased()
        if let match = replies.first(where: { reply in reply.keywords.contains { lowered.contains($0.lowercased()) } }) {
            return match
        }
        return Self.fallback(for: prompt)
    }

    private static func pause(_ seconds: TimeInterval) async throws {
        guard seconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // MARK: Jitter

    /// Splits text into token-sized chunks with human-feeling delays. The chunks always join back
    /// into exactly `text`, and the same seed always gives the same chunks.
    public static func chunks(for text: String, seed: UInt64) -> [Chunk] {
        var random = SplitMix64(seed: seed)
        var chunks: [Chunk] = []
        var fences = 0
        var previous = ""
        for word in words(in: text) {
            let inCode = fences % 2 == 1
            for piece in split(word, random: &random) {
                chunks.append(Chunk(text: piece, delay: delay(after: previous, inCode: inCode, random: &random)))
                previous = piece
            }
            fences += word.components(separatedBy: "```").count - 1
        }
        return chunks
    }

    /// Words with their trailing whitespace attached.
    static func words(in text: String) -> [String] {
        var words: [String] = []
        var current = ""
        var inWhitespace = false
        for character in text {
            let isSpace = character.isWhitespace
            if !isSpace, inWhitespace, !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(character)
            inWhitespace = isSpace
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    private static func split(_ word: String, random: inout SplitMix64) -> [String] {
        guard word.count > 6, random.unit() < 0.7 else { return [word] }
        var pieces: [String] = []
        var rest = Substring(word)
        while rest.count > 5 {
            let size = 2 + Int(random.unit() * 4)
            pieces.append(String(rest.prefix(size)))
            rest = rest.dropFirst(size)
        }
        if !rest.isEmpty { pieces.append(String(rest)) }
        return pieces
    }

    private static func delay(after piece: String, inCode: Bool, random: inout SplitMix64) -> TimeInterval {
        var delay = 0.014 + random.unit() * 0.034
        if inCode { delay *= 0.55 }
        let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = trimmed.last, ".!?:".contains(last), piece.last?.isWhitespace == true {
            delay += 0.08 + random.unit() * 0.16
        }
        if piece.contains("\n\n") { delay += 0.1 + random.unit() * 0.2 }
        if random.unit() < 0.035 { delay += 0.25 + random.unit() * 0.35 }
        return delay
    }

    // MARK: Canned replies

    static func fallback(for prompt: String) -> Reply {
        let topic = KitoAITitle.make(from: prompt, maxLength: 60)
        let text = #"""
        Good question. Here's a short take on **“\#(topic)”**:

        - **The short version:** this is a demo reply from `KitoMockAIStream`, streamed token by token with realistic pauses.
        - **What it shows:** markdown, a streaming cursor, auto-scroll and the actions under each reply.
        - **Try asking about:** a weekend in Diani, M-Pesa STK push in Swift, Swahili phrases, or the SGR vs a matatu.

        Connect your own model by conforming to `KitoAIStream` — any provider and any SDK works.
        """#
        return Reply(keywords: [], text: text, followUps: ["Plan a weekend in Diani", "Show me M-Pesa STK push in Swift"])
    }

    /// The built-in replies: a Diani weekend (with a web search and sources), M-Pesa STK push in
    /// Swift (code), Swahili phrases (a table), SGR vs matatu, a chapati recipe and a polite
    /// message to a landlord.
    public static let defaultReplies: [Reply] = [diani, mpesa, swahili, sgr, chapati, landlord]

    static let diani = Reply(
        keywords: ["diani", "weekend", "beach", "coast"],
        text: #"""
        ## A relaxed weekend in Diani 🌴

        Diani is about **30 km south of Mombasa**. The easiest way there from Nairobi is the SGR to Mombasa, then a transfer across the Likoni ferry.

        ### Friday
        - Take the **Madaraka Express** from Nairobi Terminus in the morning.
        - Check in, then catch the sunset on *Galu Beach*.

        ### Saturday
        1. Snorkel at **Kisite-Mpunguti Marine Park** — dolphins are common before 10am.
        2. Lunch on Wasini Island: coconut rice and fresh crab.
        3. Dinner at a cave restaurant in Diani.

        ### Sunday
        - Visit **Colobus Conservation**, then head back on the afternoon train.

        | Item | Estimate (KES) |
        |:-----|------:|
        | SGR economy, return | 3,000 |
        | Transfers and ferry | 2,500 |
        | Guesthouse, 2 nights | 12,000 |
        | Snorkelling trip | 4,500 |
        | **Total** | **22,000** |

        > Tip: book the SGR a week ahead — weekend trains sell out, especially in August and December.
        """#,
        tools: [KitoAIToolCall(id: "mock.search.diani", name: "web_search", runningTitle: "Searching the web…",
                               doneTitle: "Searched the web", detail: "4 sources", symbol: "globe")],
        citations: [
            KitoAICitation(id: "c1", title: "Diani Beach", url: URL(string: "https://www.magicalkenya.com")),
            KitoAICitation(id: "c2", title: "Madaraka Express tickets", url: URL(string: "https://metickets.krc.co.ke")),
            KitoAICitation(id: "c3", title: "Kisite-Mpunguti Marine Park", url: URL(string: "https://www.kws.go.ke")),
            KitoAICitation(id: "c4", title: "Colobus Conservation", url: URL(string: "https://www.colobusconservation.org")),
        ],
        followUps: ["Make it a budget trip under KES 15,000", "What should I pack?", "Add a day on Wasini Island"]
    )

    static let mpesa = Reply(
        keywords: ["m-pesa", "mpesa", "daraja", "stk", "swift", "code"],
        text: #"""
        Here's a minimal **STK Push** request against the Daraja sandbox, using `URLSession` and `async`/`await`.

        ```swift
        struct STKPushRequest: Encodable {
            let BusinessShortCode: String
            let Password: String
            let Timestamp: String
            var TransactionType = "CustomerPayBillOnline"
            let Amount: Int
            let PartyA: String          // 2547XXXXXXXX
            let PartyB: String
            let PhoneNumber: String
            let CallBackURL: String
            let AccountReference: String
            let TransactionDesc: String
        }

        func sendSTKPush(_ body: STKPushRequest, token: String) async throws -> Data {
            guard let url = URL(string: "https://sandbox.safaricom.co.ke/mpesa/stkpush/v1/processrequest") else {
                throw URLError(.badURL)
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
            let (data, _) = try await URLSession.shared.data(for: request)
            return data
        }
        ```

        A few things to get right:

        - The `Password` is **Base64(Shortcode + Passkey + Timestamp)**, with the timestamp as `yyyyMMddHHmmss`.
        - Fetch the OAuth token from `/oauth/v1/generate` first — it expires after an hour.
        - Never ship your consumer secret in the app. Call Daraja from **your own backend** and let the app talk to that.

        The customer sees the M-Pesa prompt on their phone, and Safaricom posts the result to your `CallBackURL`.
        """#,
        tools: [KitoAIToolCall(id: "mock.docs.daraja", name: "read_docs", runningTitle: "Reading the Daraja docs…",
                               doneTitle: "Read the Daraja docs", detail: "STK Push", symbol: "book")],
        citations: [KitoAICitation(id: "d1", title: "Daraja API — M-Pesa Express", url: URL(string: "https://developer.safaricom.co.ke"))],
        followUps: ["How do I handle the callback?", "Show the password generation", "Write it with Alamofire"]
    )

    static let swahili = Reply(
        keywords: ["swahili", "kiswahili", "phrase", "translate"],
        text: #"""
        Here are **safari-ready Swahili phrases** — people will love that you tried. 😊

        | English | Swahili | Say it like |
        |:--|:--|:--|
        | How are you? | Habari yako? | ha-BAH-ree YAH-koh |
        | I'm fine | Nzuri | n-ZOO-ree |
        | Thank you very much | Asante sana | ah-SAHN-teh SAH-nah |
        | How much is this? | Hii ni bei gani? | hee nee BAY GAH-nee |
        | Slowly, slowly | Pole pole | POH-leh POH-leh |
        | Let's go! | Twende! | TWEN-deh |

        A few more for the game drive:

        - **Simba** — lion 🦁
        - **Tembo** — elephant 🐘
        - **Twiga** — giraffe 🦒
        - **Kiboko** — hippo

        > *Hakuna matata* is real Swahili, but in Kenya you'll hear **“hakuna shida”** far more often.
        """#,
        followUps: ["Quiz me on these", "Phrases for bargaining at a market", "Teach me numbers 1–10"]
    )

    static let sgr = Reply(
        keywords: ["sgr", "matatu", "madaraka", "compare"],
        text: #"""
        Both get you from Nairobi to Mombasa — the right one depends on what you value.

        | | SGR (Madaraka Express) | Bus or matatu |
        |:--|:--:|:--:|
        | Time | ~6 hours | 8–10 hours |
        | One way | KES 1,500 economy | KES 1,200–2,000 |
        | Comfort | Reserved seat, AC | Varies a lot |
        | Departures | 2–3 a day | Every hour |
        | Scenery | Tsavo from the window 🐘 | Mombasa Road traffic |

        **My pick:** the **SGR**, if you can book a day or two ahead. Take a bus if you need to leave at an odd hour or want to stop at Mtito Andei on the way.

        1. Book on the Kenya Railways portal and pay with M-Pesa.
        2. Arrive **an hour early** — security checks at the terminus take time.
        3. Carry your ID; it's checked against the ticket.
        """#,
        tools: [KitoAIToolCall(id: "mock.search.sgr", name: "web_search", runningTitle: "Checking schedules and fares…",
                               doneTitle: "Checked schedules and fares", detail: "2 sources", symbol: "tram.fill")],
        citations: [
            KitoAICitation(id: "s1", title: "Madaraka Express schedule", url: URL(string: "https://krc.co.ke")),
            KitoAICitation(id: "s2", title: "Booking and fares", url: URL(string: "https://metickets.krc.co.ke")),
        ],
        followUps: ["What about flying?", "Which side has the Tsavo views?"]
    )

    static let chapati = Reply(
        keywords: ["chapati", "recipe", "cook", "ugali", "pilau"],
        text: #"""
        ### Soft, layered chapati (makes 8)

        **You'll need**
        - 3 cups all-purpose flour
        - 1 tsp salt and 1 tbsp sugar
        - 1 cup warm water
        - 4 tbsp vegetable oil, plus more for the pan

        **Method**
        1. Mix the flour, salt and sugar, add the water and 2 tbsp oil, and knead for **10 minutes** until smooth.
        2. Cover and rest the dough for 30 minutes.
        3. Roll each ball flat, brush with oil, roll it into a rope and coil it like a snail. *This is where the layers come from.*
        4. Rest 10 more minutes, then roll out to about 20 cm.
        5. Cook on a hot pan for about a minute a side, brushing with a little oil, until golden spots appear.

        > Serve with ndengu or beef stew — and keep them stacked under a kitchen towel so they stay soft.
        """#,
        followUps: ["How do I make ndengu?", "Can I use whole wheat flour?"]
    )

    static let landlord = Reply(
        keywords: ["landlord", "email", "draft", "letter"],
        text: #"""
        Here's a polite, firm draft you can adapt:

        > **Subject:** Leaking kitchen tap — Apartment B4, Kilimani
        >
        > Hi Mr. Otieno,
        >
        > I hope you're well. The kitchen tap in B4 has been leaking since **Monday 21 September**, and it's getting worse — water now pools under the sink overnight.
        >
        > Could you arrange for a plumber this week? I'm home after 5pm on weekdays, or any time on Saturday.
        >
        > Thank you,
        > Wycliff

        Want it more formal, or shall I add a line asking for September's rent receipt?
        """#,
        followUps: ["Make it more formal", "Translate it to Swahili"]
    )
}

/// Counts down the failures a mock should simulate. Shared across copies of the stream.
private final class FailureBudget: @unchecked Sendable {
    private var remaining: Int
    private let lock = NSLock()

    init(_ count: Int) { remaining = max(0, count) }

    func consume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard remaining > 0 else { return false }
        remaining -= 1
        return true
    }
}

/// A small, fast, seedable random number generator.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value in 0..<1.
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
