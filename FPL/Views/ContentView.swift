//
//  ContentView.swift
//  FPL
//
//  Created by Rafael Lopez on 11/4/24.
//

import SwiftData
import SwiftUI

/// The app's top-level tabs. Each tab owns its own NavigationStack.
enum AppTab: CaseIterable, Identifiable {
    case feed, players, notes, profile

    var id: Self { self }

    var title: String {
        switch self {
        case .feed: "Feed"
        case .players: "Players"
        case .notes: "Notes"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .feed: "house"
        case .players: "tshirt"
        case .notes: "note.text"
        case .profile: "person.crop.circle"
        }
    }
}

/// Root view: the four tabs plus the custom tab bar.
///
/// Uses a ZStack instead of TabView so the theme's flat tab bar replaces the
/// iOS 26 glass one. Every tab stays alive, so switching keeps scroll position
/// and loaded data, and the switch itself is instant.
struct ContentView: View {
    @State private var selection: AppTab = .feed
    /// Shared so a note written from any tab is tagged with the current gameweek.
    @StateObject private var gameweeks = GameweekStore()
    /// Measured tab bar height, passed to screens so lists scroll clear of it.
    @State private var tabBarHeight: CGFloat = 0

    var body: some View {
        ZStack {
            ForEach(AppTab.allCases) { tab in
                let isSelected = tab == selection
                content(for: tab)
                    .opacity(isSelected ? 1 : 0)
                    .allowsHitTesting(isSelected)
                    .accessibilityHidden(!isSelected)
            }
        }
        .environment(\.tabBarClearance, tabBarHeight)
        .modifier(TabBarPlacement(selection: $selection, height: $tabBarHeight))
        .background(Theme.background.ignoresSafeArea())
        .environmentObject(gameweeks)
        .task { await gameweeks.loadIfNeeded() }
        // Notes live on the device.
        .modelContainer(for: Note.self)
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .feed: FeedView()
        case .players: PlayersView()
        case .notes: NotesView()
        case .profile: ProfileView()
        }
    }
}

/// Tab bar: a rounded card with a solid green pill behind the selected tab.
/// The card is Liquid Glass on iOS 26 and solid navy on earlier versions.
private struct FloodlightsTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = tab == selection
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(height: 22)
                        Text(tab.title)
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(isSelected ? Theme.onAccent : Theme.secondaryText)
                    .background(isSelected ? Theme.accent : .clear,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(6)
        .modifier(TabBarBackground())
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
    }
}

/// Pins the tab bar to the bottom on a soft edge: rows fade and blur into navy
/// as they pass under it, like the scroll edge effect under the search bar.
/// (The system effect from `safeAreaBar` didn't reach the tabs' lists.)
private struct TabBarPlacement: ViewModifier {
    @Binding var selection: AppTab
    /// Set to the bar's height, including the fade above it.
    @Binding var height: CGFloat

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            FloodlightsTabBar(selection: $selection)
                // Start the fade 16pt above the bar so rows soften before they
                // reach it. The space counts toward the height, so a list's last
                // row scrolls fully clear of the fade.
                .padding(.top, 16)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                .background {
                    SoftEdge()
                        .ignoresSafeArea(edges: .bottom)
                }
        }
    }
}

/// A blur and navy tint that ramp up from clear at the top to solid at the bottom.
private struct SoftEdge: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask {
                    LinearGradient(colors: [.clear, .black, .black],
                                   startPoint: .top, endPoint: .bottom)
                }
            LinearGradient(stops: [
                .init(color: Theme.background.opacity(0), location: 0),
                .init(color: Theme.background.opacity(0.7), location: 0.45),
                .init(color: Theme.background.opacity(0.9), location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        .allowsHitTesting(false)
    }
}

/// Liquid Glass on iOS 26, the flat navy card before that.
private struct TabBarBackground: ViewModifier {
    private let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(Theme.surface, in: shape)
                .overlay { shape.strokeBorder(Theme.border) }
        }
    }
}

#Preview {
    ContentView()
}
