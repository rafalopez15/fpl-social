//
//  PointsLabel.swift
//  FPL
//

import SwiftUI

/// A transfer's net points: "+2 pts" in green, "−5 pts" in red, "0 pts" in grey.
struct PointsLabel: View {
    let points: Int

    var body: some View {
        Text(Self.text(points))
            .fontWeight(.semibold)
            .monospacedDigit()
            .foregroundStyle(Self.color(points))
            .accessibilityLabel(Self.description(points))
    }

    /// "+2 pts", "−5 pts" or "0 pts".
    static func text(_ points: Int) -> String {
        points > 0 ? "+\(points) pts" : points < 0 ? "\u{2212}\(-points) pts" : "0 pts"
    }

    /// "gained 2 points", "lost 5 points" or "no change in points", for VoiceOver.
    static func description(_ points: Int) -> String {
        let count = abs(points) == 1 ? "1 point" : "\(abs(points)) points"
        return points > 0 ? "gained \(count)" : points < 0 ? "lost \(count)" : "no change in points"
    }

    static func color(_ points: Int) -> Color {
        points > 0 ? Theme.accent : points < 0 ? Theme.danger : Theme.secondaryText
    }
}
