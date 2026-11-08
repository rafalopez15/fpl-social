//
//  CardOptionsMenu.swift
//  FPL
//

import SwiftUI

/// The `…` button in a card's top-right corner, holding the card's rarely used actions.
struct CardOptionsMenu<Content: View>: View {
    /// What VoiceOver calls it, e.g. "Team options".
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu(content: content) {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        // Pull the 44pt target into the card's padding so the icon lines up with the top-right corner.
        .padding(.top, -12)
        .padding(.trailing, -12)
    }
}
