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
