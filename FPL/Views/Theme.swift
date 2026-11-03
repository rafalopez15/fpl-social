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
    /// The squad pitch's grass and its lighter mowing stripe, darker than FPL's
    /// bright green so the pitch sits in the navy theme.
    static let pitch = Color(hex: 0x14532D)
    static let pitchStripe = Color(hex: 0x17603A)
    /// Shirts on the pitch until club colors arrive (FPL-38).
    static let shirt = Color(hex: 0x9CA3AF)

    /// Chip colors for FPL's 1–5 fixture difficulty, green (easy) to dark red (hard),
    /// following FPL's own scale. Each pairing passes 4.5:1.
    static func difficultyColors(_ difficulty: Int) -> (background: Color, foreground: Color) {
        switch difficulty {
        case ...1: (Color(hex: 0x15803D), text)
        case 2: (accent, onAccent)
        case 3: (Color(hex: 0xCBD5E1), onAccent)
        case 4: (danger, onAccent)
        default: (Color(hex: 0xB91C1C), text)
        }
    }

    static func color(for flag: Element.AvailabilityFlag) -> Color {
        switch flag {
        case .doubtful: warning
        case .out: danger
        }
    }
}

private struct ThemedScreen: ViewModifier {
    @Environment(\.tabBarClearance) private var tabBarClearance

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, tabBarClearance, for: .scrollContent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
    }
}

extension EnvironmentValues {
    /// Height of the tab bar above the home indicator. The bar's safe area inset
    /// doesn't reach lists inside each tab's NavigationStack, so themed screens
    /// add this as a bottom content margin instead.
    @Entry var tabBarClearance: CGFloat = 0
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

    /// "#EF0107" (or without the #, any case). Nil for nil or anything else.
    init?(hexString: String?) {
        guard let value = UInt32(hexValue: hexString) else { return nil }
        self.init(hex: value)
    }
}

extension UInt32 {
    /// Parses "#RRGGBB" or "RRGGBB"; nil for any other shape.
    init?(hexValue string: String?) {
        guard var string = string?.trimmingCharacters(in: .whitespaces) else { return nil }
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6, string.allSatisfy(\.isHexDigit), let value = UInt32(string, radix: 16) else { return nil }
        self = value
    }
}

extension View {
    /// Applies the theme to a screen: navy background behind lists and forms.
    /// Text keeps the system `.primary`/`.secondary` styles; overriding them
    /// with `foregroundStyle(_:_:)` turns ContentUnavailableView descriptions white.
    ///
    /// Also keeps lists' last rows clear of the tab bar (see `tabBarClearance`).
    func themedScreen() -> some View {
        modifier(ThemedScreen())
    }

    /// Row styling for lists and forms on a themed screen.
    func themedRow() -> some View {
        self
            .listRowBackground(Theme.surface)
            .listRowSeparatorTint(Theme.border)
    }
}
