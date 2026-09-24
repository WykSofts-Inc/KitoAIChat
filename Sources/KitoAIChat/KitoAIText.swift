//
//  KitoAIText.swift
//  KitoAIChat
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// Makes a short conversation title from its first message.
///
/// ```swift
/// KitoAITitle.make(from: "Hey, can you help me plan a weekend in Diani?")   // "Plan a weekend in Diani"
/// ```
public enum KitoAITitle {
    static let fillers = [
        "i would like you to", "i'd like you to", "i want you to", "i need you to",
        "could you please", "can you please", "would you please",
        "could you", "can you", "would you", "will you", "can u",
        "help me to", "help me", "please", "kindly",
        "hey there", "hello", "hey", "hi", "habari", "sasa", "yo",
    ]

    public static func make(from text: String, maxLength: Int = 40) -> String {
        let firstLine = KitoAIMarkdown.plainText(text)
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        var title = collapsingWhitespace(firstLine)
        title = removingFillers(from: title)
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: " ?!.,:;…-—"))
        guard let first = title.first else { return "New chat" }
        title = first.uppercased() + title.dropFirst()
        return truncated(title, to: maxLength)
    }

    static func collapsingWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func removingFillers(from text: String) -> String {
        var result = text
        var changed = true
        while changed {
            changed = false
            let lowered = result.lowercased()
            for filler in fillers where lowered.hasPrefix(filler) {
                let rest = result.dropFirst(filler.count)
                guard rest.isEmpty || rest.first == " " || rest.first == "," || rest.first == "!" else { continue }
                result = String(rest).trimmingCharacters(in: CharacterSet(charactersIn: " ,!"))
                changed = true
                break
            }
        }
        return result.isEmpty ? text : result
    }

    static func truncated(_ text: String, to maxLength: Int) -> String {
        guard text.count > maxLength, maxLength > 1 else { return text }
        let limit = text.prefix(maxLength - 1)
        let cut = limit.lastIndex(of: " ").map { limit[..<$0] } ?? limit
        return cut.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:-—")) + "…"
    }
}

/// Word and token counts for prompts and replies.
public enum KitoAITextStats {
    /// Words as a reader counts them — punctuation and markdown syntax don't count.
    public static func wordCount(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }

    /// A provider-neutral estimate of model tokens: roughly four characters or three quarters of a
    /// word each, whichever is larger. Use your provider's tokenizer when you need exact numbers.
    public static func estimatedTokens(_ text: String) -> Int {
        let characters = text.unicodeScalars.filter { !$0.properties.isWhitespace }.count
        guard characters > 0 else { return 0 }
        let byCharacters = (Double(text.count) / 4).rounded(.up)
        let byWords = (Double(wordCount(text)) * 4 / 3).rounded(.up)
        return Int(max(byCharacters, byWords, 1))
    }

    /// Minutes of reading at `wordsPerMinute`, at least a few seconds for any text.
    public static func readingTime(_ text: String, wordsPerMinute: Double = 230) -> TimeInterval {
        let words = Double(wordCount(text))
        guard words > 0 else { return 0 }
        return max(3, words / wordsPerMinute * 60)
    }
}

/// "Good morning", "Good afternoon" or "Good evening", with a first name.
public enum KitoAIGreeting {
    public enum Period: String, Hashable, Sendable {
        case morning, afternoon, evening
    }

    /// Morning from 5:00, afternoon from 12:00, evening from 17:00 until 5:00.
    public static func period(for date: Date, calendar: Calendar = .current) -> Period {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<12: return .morning
        case 12..<17: return .afternoon
        default: return .evening
        }
    }

    /// `"Good evening, Wycliff"` — the first word of `name` only.
    public static func text(for date: Date = Date(), name: String? = nil, calendar: Calendar = .current) -> String {
        let base = "Good \(period(for: date, calendar: calendar).rawValue)"
        guard let first = name?.split(separator: " ").first, !first.isEmpty else { return base }
        return "\(base), \(first)"
    }
}

/// Timestamps for conversation rows.
public enum KitoAIDateFormat {
    /// "14:05" today, "Yesterday", a weekday within the week, "12 Sep" this year, else "12/09/25".
    public static func rowTimestamp(for date: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return format(date, template: "jmm", calendar: calendar, locale: locale)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days > 0, days < 7 {
            return format(date, template: "EEE", calendar: calendar, locale: locale)
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return format(date, template: "dMMM", calendar: calendar, locale: locale)
        }
        return format(date, template: "ddMMyy", calendar: calendar, locale: locale)
    }

    static func format(_ date: Date, template: String, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}

/// A titled group of conversations in the sidebar.
public struct KitoAIConversationSection: Identifiable, Hashable, Sendable {
    public var title: String
    public var conversations: [KitoAIConversation]
    public var id: String { title }

    public init(title: String, conversations: [KitoAIConversation]) {
        self.title = title
        self.conversations = conversations
    }
}

/// Buckets conversations the way chat apps do: Pinned, Today, Yesterday, Previous 7 days,
/// Previous 30 days, then one section per month.
public enum KitoAIConversationGrouping {
    public static func sections(
        for conversations: [KitoAIConversation],
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> [KitoAIConversationSection] {
        let sorted = conversations.sorted { $0.updatedAt > $1.updatedAt }
        var sections: [KitoAIConversationSection] = []
        let pinned = sorted.filter(\.isPinned)
        if !pinned.isEmpty { sections.append(KitoAIConversationSection(title: "Pinned", conversations: pinned)) }
        for conversation in sorted where !conversation.isPinned {
            let title = bucket(for: conversation.updatedAt, now: now, calendar: calendar, locale: locale)
            if sections.last?.title == title {
                sections[sections.count - 1].conversations.append(conversation)
            } else {
                sections.append(KitoAIConversationSection(title: title, conversations: [conversation]))
            }
        }
        return sections
    }

    /// The section title for a date.
    public static func bucket(for date: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ...0: return "Today"
        case 1: return "Yesterday"
        case 2..<7: return "Previous 7 days"
        case 7..<30: return "Previous 30 days"
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            return KitoAIDateFormat.format(date, template: sameYear ? "LLLL" : "LLLLyyyy", calendar: calendar, locale: locale)
        }
    }

    /// Conversations whose title or latest text contains `query`.
    public static func filter(_ conversations: [KitoAIConversation], query: String) -> [KitoAIConversation] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return conversations }
        return conversations.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(trimmed) || $0.snippet.localizedCaseInsensitiveContains(trimmed)
        }
    }
}
