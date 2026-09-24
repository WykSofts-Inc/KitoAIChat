//
//  KitoAIAutoScrollPolicy.swift
//  KitoAIChat
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import CoreGraphics

/// Decides when a streaming conversation should follow new text and when it should leave the
/// reader alone.
///
/// It follows while the bottom is in view. When the distance from the bottom grows by more than
/// the content (or a shrinking viewport, like the keyboard) explains, the reader scrolled up — so
/// it pauses and offers "Jump to latest". Scrolling back near the bottom, jumping, or sending a
/// message resumes following.
///
/// ```swift
/// var policy = KitoAIAutoScrollPolicy()
/// policy.observe(distanceFromBottom: 420, contentHeight: 2_000, viewportHeight: 700)
/// policy.isFollowing          // false — the reader scrolled up
/// policy.showsJumpToLatest    // true
/// ```
public struct KitoAIAutoScrollPolicy: Hashable, Sendable {
    /// Within this many points of the bottom counts as "at the bottom".
    public var threshold: CGFloat
    public private(set) var isFollowing: Bool
    public private(set) var distanceFromBottom: CGFloat
    private var contentHeight: CGFloat
    private var viewportHeight: CGFloat
    private var hasObserved: Bool

    public init(threshold: CGFloat = 56) {
        self.threshold = threshold
        isFollowing = true
        distanceFromBottom = 0
        contentHeight = 0
        viewportHeight = 0
        hasObserved = false
    }

    /// Call whenever the scroll position, content height or viewport height changes.
    public mutating func observe(distanceFromBottom distance: CGFloat, contentHeight newContentHeight: CGFloat, viewportHeight newViewportHeight: CGFloat) {
        defer {
            distanceFromBottom = distance
            contentHeight = newContentHeight
            viewportHeight = newViewportHeight
            hasObserved = true
        }
        if distance <= threshold {
            isFollowing = true
            return
        }
        guard hasObserved else { return }
        let explained = max(0, newContentHeight - contentHeight) + max(0, viewportHeight - newViewportHeight)
        let moved = distance - distanceFromBottom
        if moved > explained + 1 { isFollowing = false }
    }

    /// True when new content should scroll the conversation.
    public var shouldFollowContent: Bool { isFollowing }

    /// True when the "Jump to latest" pill should show.
    public var showsJumpToLatest: Bool { !isFollowing && distanceFromBottom > threshold }

    /// The reader tapped "Jump to latest".
    public mutating func jumpToLatest() { isFollowing = true }

    /// The reader sent a message — always bring it into view.
    public mutating func didSendMessage() { isFollowing = true }
}
