//
//  KitoAIOrb.swift
//  KitoAIChat
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// The assistant's presence: a glassy orb of slowly drifting colour that breathes while it works.
/// With Reduce Motion it holds still.
///
/// ```swift
/// KitoAIOrb(size: 96)
/// KitoAIOrb(size: 22, isActive: isGenerating, tint: .orange)
/// ```
public struct KitoAIOrb: View {
    private let size: CGFloat
    private let isActive: Bool
    private let animatesWhenIdle: Bool
    private let colors: [Color]?
    private let tint: Color?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - isActive: animates faster and breathes when true; drifts gently when false.
    ///   - animatesWhenIdle: pass false to hold still while not active — for many small orbs.
    ///   - colors: the orb's colours; by default the tint with violet, pink and cyan.
    public init(size: CGFloat = 64, isActive: Bool = true, animatesWhenIdle: Bool = true, colors: [Color]? = nil, tint: Color? = nil) {
        self.size = size
        self.isActive = isActive
        self.animatesWhenIdle = animatesWhenIdle
        self.colors = colors
        self.tint = tint
    }

    private var palette: [Color] {
        let base = colors ?? KitoAIPalette.orbColors(tint: tint ?? theme.colors.primary)
        return base.count >= 4 ? base : base + KitoAIPalette.orbColors(tint: tint ?? theme.colors.primary)
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: isPaused)) { timeline in
            orb(time: isPaused ? 0 : timeline.date.timeIntervalSinceReferenceDate)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var isPaused: Bool { reduceMotion || (!isActive && !animatesWhenIdle) }

    private var speed: Double { isActive ? 1 : 0.35 }

    private func orb(time: Double) -> some View {
        let colors = palette
        return ZStack {
            Circle().fill(AngularGradient(colors: colors, center: .center, angle: .degrees(rotation(time))))
            ForEach(0..<3, id: \.self) { index in
                blob(index: index, color: colors[(index + 1) % colors.count], time: time)
            }
            Circle().fill(highlight)
            Circle().strokeBorder(rim, lineWidth: max(0.75, size * 0.02))
        }
        .compositingGroup()
        .clipShape(Circle())
        .scaleEffect(breath(time))
        .shadow(color: colors[0].opacity(glowOpacity), radius: size * 0.2, y: size * 0.06)
    }

    private func blob(index: Int, color: Color, time: Double) -> some View {
        Circle()
            .fill(color)
            .frame(width: size * 0.62, height: size * 0.62)
            .offset(blobOffset(index: index, time: time))
            .blur(radius: size * 0.14)
            .opacity(0.9)
    }

    private var highlight: RadialGradient {
        RadialGradient(
            colors: [.white.opacity(0.7), .white.opacity(0)],
            center: UnitPoint(x: 0.3, y: 0.25),
            startRadius: 0,
            endRadius: size * 0.55
        )
    }

    private var rim: LinearGradient {
        LinearGradient(colors: [.white.opacity(0.65), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var glowOpacity: Double { isActive ? 0.5 : 0.3 }

    private func rotation(_ time: Double) -> Double {
        (time * 40 * speed).truncatingRemainder(dividingBy: 360)
    }

    private func breath(_ time: Double) -> CGFloat {
        guard isActive, !reduceMotion else { return 1 }
        return 1 + 0.045 * CGFloat(sin(time * 2.4))
    }

    private func blobOffset(index: Int, time: Double) -> CGSize {
        let phase = Double(index) * 2.1
        let rate = (0.9 + Double(index) * 0.35) * speed
        let radius = Double(size) * 0.22
        let x = cos(time * rate + phase) * radius
        let y = sin(time * rate * 1.3 + phase) * radius
        return CGSize(width: x, height: y)
    }
}

/// "Thinking…" with a small orb and a light sweep — shown before the first token arrives.
///
/// ```swift
/// KitoAIThinkingIndicator()
/// KitoAIThinkingIndicator("Reading your file")
/// ```
public struct KitoAIThinkingIndicator: View {
    private let label: String
    private let tint: Color?

    @Environment(\.kitoTheme) private var theme

    public init(_ label: String = "Thinking", tint: Color? = nil) {
        self.label = label
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: theme.spacing.sm) {
            KitoAIOrb(size: 22, isActive: true, tint: tint)
            Text("\(label)…")
                .font(theme.typography.label)
                .foregroundStyle(theme.colors.onSurface.opacity(0.55))
                .kitoAIShimmer()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label)…")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// The blinking bar that follows streamed text.
public struct KitoAIStreamingCursor: View {
    private let tint: Color?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDim = false

    public init(tint: Color? = nil) {
        self.tint = tint
    }

    public var body: some View {
        Capsule()
            .fill(tint ?? theme.colors.onSurface)
            .frame(width: 8, height: 16)
            .opacity(isDim ? 0.25 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { isDim = true }
            }
            .accessibilityHidden(true)
    }
}
