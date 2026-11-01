//
//  Theme.swift
//  FPL
//

import SwiftUI

/// Floodlights, the app's dark-only theme: midnight navy surfaces, one green
/// accent, SF Pro type. Use these instead of literal colors in views.
enum Theme {
    /// Screen background.
    static let background = Color(hex: 0x0F0F23)
    /// Cards, list rows, the tab bar, popovers.
    static let surface = Color(hex: 0x1B1B30)
    /// Separators and borders on top of `surface`.
    static let border = Color(hex: 0x27273B)
    /// Primary text (18:1 on background).
    static let text = Color(hex: 0xF8FAFC)
    /// Secondary text (7.4:1 on background, 6.6:1 on surface).
    static let secondaryText = Color(hex: 0x94A3B8)
    /// Buttons, selection, links. Same value as `AccentColor` in the asset catalog.
    static let accent = Color.accentColor
    /// Text and icons drawn on top of `accent`.
    static let onAccent = Color(hex: 0x0F0F23)
    /// Doubtful players (some chance of playing).
    static let warning = Color(hex: 0xFBBF24)
    /// Players ruled out (0% chance). 6.8:1 on background, 6.1:1 on surface.
    static let danger = Color(hex: 0xF87171)

    static func color(for flag: Element.AvailabilityFlag) -> Color {
        switch flag {
        case .doubtful: warning
        case .out: danger
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension View {
    /// Applies the theme to a screen: navy background behind lists and forms.
    /// Text keeps the system `.primary`/`.secondary` styles; overriding them
    /// with `foregroundStyle(_:_:)` turns ContentUnavailableView descriptions white.
    func themedScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
    }

    /// Row styling for lists and forms on a themed screen.
    func themedRow() -> some View {
        self
            .listRowBackground(Theme.surface)
            .listRowSeparatorTint(Theme.border)
    }
}
