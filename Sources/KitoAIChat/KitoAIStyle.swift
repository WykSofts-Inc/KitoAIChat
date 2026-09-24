//
//  KitoAIStyle.swift
//  KitoAIChat
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import UIKit
import KitoCore

/// The accent a view should use and the colour to put on it.
struct KitoAIAccent {
    /// Links, the orb, highlights.
    let tint: Color
    /// The send button: black in light mode, white in dark (the theme's text colour) unless a tint is given.
    let strong: Color
    let onStrong: Color

    init(tint: Color?, theme: KitoTheme, environment: EnvironmentValues) {
        if let tint {
            self.tint = tint
            self.strong = tint
            self.onStrong = tint.kitoAIContrasting(in: environment)
        } else {
            self.tint = theme.colors.primary
            self.strong = theme.colors.onBackground
            self.onStrong = theme.colors.background
        }
    }
}

extension Color {
    /// Black or white, whichever reads better on this colour in `environment`.
    func kitoAIContrasting(in environment: EnvironmentValues) -> Color {
        let resolved = resolve(in: environment)
        let luminance = 0.2126 * resolved.linearRed + 0.7152 * resolved.linearGreen + 0.0722 * resolved.linearBlue
        return luminance > 0.36 ? .black : .white
    }
}

/// The orb's palette for a tint: the tint plus a violet, a pink and a cyan that sit well around it.
enum KitoAIPalette {
    static func orbColors(tint: Color) -> [Color] {
        [
            tint,
            Color(red: 0.55, green: 0.36, blue: 0.98),
            Color(red: 0.98, green: 0.42, blue: 0.62),
            Color(red: 0.25, green: 0.84, blue: 0.93),
            tint,
        ]
    }
}

/// Shrinks a little while pressed.
struct KitoAIPressableStyle: ButtonStyle {
    var scale: CGFloat = 0.92

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

enum KitoAIMotion {
    static func spring(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.78)
    }

    static func snappy(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.28, dampingFraction: 0.72)
    }
}

/// A light sweep across the content — used on "Thinking…" and running tool chips. Still with
/// Reduce Motion.
struct KitoAIShimmer: ViewModifier {
    var isActive: Bool
    var duration: Double = 1.6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if isActive && !reduceMotion {
            content
                .overlay {
                    TimelineView(.animation) { timeline in
                        let phase = Self.phase(at: timeline.date, duration: duration)
                        GeometryReader { geometry in
                            Self.band(width: geometry.size.width, phase: phase)
                        }
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
        } else {
            content
        }
    }

    static func phase(at date: Date, duration: Double) -> Double {
        let time = date.timeIntervalSinceReferenceDate
        return time.truncatingRemainder(dividingBy: duration) / duration
    }

    static func band(width: CGFloat, phase: Double) -> some View {
        let bandWidth = max(40, width * 0.45)
        let travel = width + bandWidth * 2
        let offset = CGFloat(phase) * travel - bandWidth
        return LinearGradient(colors: [.white.opacity(0), .white.opacity(0.75), .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
            .frame(width: bandWidth)
            .offset(x: offset)
            .blendMode(.plusLighter)
    }
}

extension View {
    func kitoAIShimmer(_ isActive: Bool = true) -> some View {
        modifier(KitoAIShimmer(isActive: isActive))
    }
}

/// Lays chips out left to right, wrapping onto new lines.
struct KitoAIFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, width: bounds.width)
        for row in rows {
            for item in row.items {
                let point = CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y)
                subviews[item.index].place(at: point, proposal: ProposedViewSize(item.size))
            }
        }
    }

    private struct Item { let index: Int; let x: CGFloat; let size: CGSize }
    private struct Row { var items: [Item] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        var x: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0, x + size.width > width {
                let previous = rows[rows.count - 1]
                rows.append(Row(y: previous.y + previous.height + lineSpacing))
                x = 0
            }
            rows[rows.count - 1].items.append(Item(index: index, x: x, size: size))
            x += size.width + spacing
            rows[rows.count - 1].width = x - spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}

/// Decodes and caches a `KitoAIImage`, or loads it from its url.
struct KitoAIImageView: View {
    let image: KitoAIImage
    var contentMode: ContentMode = .fill

    @Environment(\.kitoTheme) private var theme
    @State private var decoded: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(theme.colors.surfaceMuted)
            if let decoded {
                Image(uiImage: decoded).resizable().aspectRatio(contentMode: contentMode)
            } else if let url = image.url {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                    if let loaded = phase.image {
                        loaded.resizable().aspectRatio(contentMode: contentMode).transition(.opacity)
                    } else if phase.error != nil {
                        Image(systemName: "photo").foregroundStyle(theme.colors.onSurface.opacity(0.4))
                    } else {
                        ProgressView()
                    }
                }
            }
        }
        .clipped()
        .accessibilityElement()
        .accessibilityLabel(image.altText ?? "Image")
        .accessibilityAddTraits(.isImage)
        .task(id: image.id) {
            guard let data = image.data else { return }
            decoded = UIImage(data: data)
        }
    }
}
