//
//  KitoAIWelcome.swift
//  KitoAIChat
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// The hero on an empty conversation: a glowing orb over "Good evening, Wycliff" and a prompt.
/// The greeting follows the time of day.
///
/// ```swift
/// KitoAIWelcome(name: "Wycliff N")                         // "Good evening, Wycliff"
/// KitoAIWelcome(greeting: "Karibu tena!", subtitle: "Tuanze wapi leo?")
/// ```
public struct KitoAIWelcome: View {
    private let name: String?
    private let greeting: String?
    private let subtitle: String
    private let date: Date
    private let tint: Color?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown = false

    /// - Parameters:
    ///   - name: the first word is used, so "Wycliff N" greets "Wycliff".
    ///   - greeting: replaces the time-of-day greeting.
    public init(name: String? = nil, greeting: String? = nil, subtitle: String = "How can I help you today?", date: Date = Date(), tint: Color? = nil) {
        self.name = name
        self.greeting = greeting
        self.subtitle = subtitle
        self.date = date
        self.tint = tint
    }

    private var accent: Color { tint ?? theme.colors.primary }
    private var title: String { greeting ?? KitoAIGreeting.text(for: date, name: name) }

    public var body: some View {
        VStack(spacing: theme.spacing.xl) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.28))
                    .frame(width: 150, height: 150)
                    .blur(radius: 40)
                KitoAIOrb(size: 88, isActive: true, tint: tint)
            }
            .scaleEffect(isShown || reduceMotion ? 1 : 0.6)
            .opacity(isShown ? 1 : 0)
            .animation(appear(delay: 0), value: isShown)

            VStack(spacing: theme.spacing.xs + 2) {
                Text(title)
                    .font(theme.typography.displayMedium)
                    .foregroundStyle(titleStyle)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(theme.typography.titleMedium.weight(.regular))
                    .foregroundStyle(theme.colors.onSurface.opacity(0.55))
            }
            .multilineTextAlignment(.center)
            .offset(y: isShown || reduceMotion ? 0 : 10)
            .opacity(isShown ? 1 : 0)
            .animation(appear(delay: 0.12), value: isShown)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .onAppear { isShown = true }
    }

    private var titleStyle: LinearGradient {
        LinearGradient(colors: [theme.colors.onSurface, theme.colors.onSurface.opacity(0.85), accent], startPoint: .leading, endPoint: .trailing)
    }

    private func appear(delay: Double) -> Animation {
        guard !reduceMotion else { return .easeOut(duration: 0.25) }
        return .spring(response: 0.6, dampingFraction: 0.75).delay(delay)
    }
}
