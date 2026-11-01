//
//  ContentView.swift
//  FPL
//
//  Created by Rafael Lopez on 11/4/24.
//

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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloodlightsTabBar(selection: $selection)
        }
        .background(Theme.background.ignoresSafeArea())
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

/// Flat tab bar: a navy card with a solid green pill behind the selected tab.
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
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.border)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .background(Theme.background)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
    }
}

#Preview {
    ContentView()
}
