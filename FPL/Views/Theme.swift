//
//  Theme.swift
//  FPL
//

import SwiftUI

/// Floodlights, the app's dark-only theme: midnight navy surfaces, one green
/// accent, SF Pro type. Use these instead of literal colors in views.
enum Theme {
    /// Screen background.
    static let background = Color(hex: backgroundHex)
    static let backgroundHex: UInt32 = 0x0F0F23
    /// Cards, list rows, the tab bar, the stats popover.
    static let surface = Color(hex: 0x1B1B30)
    /// A popover lighter than `surface`, so it stands apart from the row it opens on.
    /// `border` doesn't show on it.
    static let raised = Color(hex: 0x2A2A44)
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
    /// Your team's row in a list of other teams (league standings): a green tint over the screen's background.
    static let yourRow = accent.opacity(0.15)
    /// The squad pitch's grass and its lighter mowing stripe, darker than FPL's
    /// bright green so the pitch sits in the navy theme.
    static let pitch = Color(hex: pitchHex)
    static let pitchHex: UInt32 = 0x14532D
    static let pitchStripe = Color(hex: 0x17603A)
    /// Shirts for clubs with no colors.
    static let shirt = Color(hex: shirtHex)
    static let shirtHex: UInt32 = 0x9CA3AF
    /// Every goalkeeper's shirt, since the API has no keeper kits. Pink matches no
    /// club and no theme color; yellow clashed with the doubtful flag.
    static let goalkeeperShirt = Color(hex: goalkeeperShirtHex)
    static let goalkeeperShirtHex: UInt32 = 0xF472B6

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
}

extension UInt32 {
    /// Parses "#RRGGBB" or "RRGGBB"; nil otherwise.
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

/// A shirt's colors as hex, for the contrast check.
struct KitColors: Equatable {
    let primary: UInt32
    let secondary: UInt32?

    static let goalkeeper = KitColors(primary: Theme.goalkeeperShirtHex, secondary: nil)

    /// Grey when the club has no colors.
    init(primary: String?, secondary: String?) {
        if let value = UInt32(hexValue: primary) {
            self.primary = value
            self.secondary = UInt32(hexValue: secondary)
        } else {
            self.primary = Theme.shirtHex
            self.secondary = nil
        }
    }

    init(primary: UInt32, secondary: UInt32?) {
        self.primary = primary
        self.secondary = secondary
    }

    /// True below 3:1 against the pitch or bench, e.g. Newcastle's black.
    var needsHairline: Bool {
        min(Self.contrast(primary, Theme.pitchHex), Self.contrast(primary, Theme.backgroundHex)) < 3
    }

    /// WCAG contrast ratio between two sRGB colors.
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    static func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let c = Double((hex >> shift) & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }
}
