//
//  LiveTag.swift
//  FPL
//

import SwiftUI

/// "Live" next to gameweek points summed from live scores, which can still move.
struct LiveTag: View {
    var body: some View {
        Text("Live")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.6)))
            .accessibilityLabel("live")
    }
}

/// `content` with the tag beside it, or under it when they don't fit on one line.
struct LiveTagged<Content: View>: View {
    let isLive: Bool
    @ViewBuilder let content: Content

    var body: some View {
        if isLive {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    content.fixedSize()
                    LiveTag()
                }
                VStack(alignment: .leading, spacing: 4) {
                    content
                    LiveTag()
                }
            }
        } else {
            content
        }
    }
}
