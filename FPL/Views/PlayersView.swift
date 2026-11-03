//
//  PlayersView.swift
//  FPL
//
//  Created by Rafael Lopez on 11/4/24.
//

import SwiftUI

/// The Players tab: players for one position, with search, sort and a price filter.
struct PlayersView: View {
    @StateObject private var viewModel = ElementViewModel(position: .forward)

    var body: some View {
        NavigationStack {
            Group {
                // Full-screen spinner only when there's nothing to show yet;
                // pull-to-refresh keeps the list and uses the system spinner.
                if viewModel.isLoading && viewModel.elements.isEmpty {
                    ProgressView("Loading...")
                } else if let errorMessage = viewModel.errorMessage {
                    VStack(spacing: 12) {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await viewModel.fetchElements() }
                        }
                    }
                    .padding()
                } else {
                    List(viewModel.filteredElements) { element in
                        ElementRow(element: element,
                                   team: viewModel.teams[element.team],
                                   sort: viewModel.sort,
                                   fixtures: viewModel.schedule?.upcoming(for: element.team) ?? [],
                                   teams: viewModel.teams)
                            .themedRow()
                    }
                    .listStyle(.insetGrouped)
                    // Pull the list up under the search bar; the grouped style's
                    // default top inset left a large empty band.
                    .contentMargins(.top, 4, for: .scrollContent)
                    .refreshable { await viewModel.fetchElements() }
                }
            }
            .themedScreen()
            // On the Group so search stays put while loading. Always visible:
            // the tab bar owns the bottom of the screen, so search sits up top.
            .searchable(text: $viewModel.searchQuery,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search \(viewModel.position.title.lowercased())")
            .navigationTitle(viewModel.position.title)
            // Inline so the title menu is available without scrolling.
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleMenu {
                Picker("Position", selection: $viewModel.position) {
                    ForEach(Element.Position.allCases, id: \.self) { position in
                        Text(position.title).tag(position)
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    sortMenu
                    sortOrderButton
                }
            }
        }
        // Runs on appear and again whenever the position changes,
        // cancelling any fetch still in flight.
        .task(id: viewModel.position) {
            await viewModel.fetchElements()
        }
    }

    /// Dropdown of sort fields; the current one has a checkmark.
    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $viewModel.sort) {
                ForEach(ElementSort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
        .accessibilityLabel("Sort by")
        .accessibilityValue(viewModel.sort.title)
    }

    /// Flips between high-to-low and low-to-high.
    private var sortOrderButton: some View {
        Button {
            viewModel.sortAscending.toggle()
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort order")
        .accessibilityValue(viewModel.sortAscending ? "Low to high" : "High to low")
    }
}

private struct ElementRow: View {
    let element: Element
    let team: Team?
    /// The right-hand stat follows the sort, so sorting by goals shows goals.
    let sort: ElementSort
    /// Next 3 gameweeks for the stats popover; empty hides that section.
    let fixtures: [GameweekFixtures]
    /// All teams, for opponent names in the popover.
    let teams: [Int: Team]
    @State private var showingStats = false

    private var stat: String {
        switch sort {
        case .points, .price: "\(element.totalPoints ?? 0) pts"
        case .goals: "\(element.goalsScored ?? 0) G"
        case .assists: "\(element.assists ?? 0) A"
        case .selectedBy: String(format: "%.1f%%", element.selectedByPercent ?? 0)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                showingStats = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
            }
            // Borderless so only the icon is tappable, not the whole row.
            .buttonStyle(.borderless)
            .accessibilityLabel(element.currentNews == nil
                                ? "Stats for \(element.webName)"
                                : "Stats and news for \(element.webName)")
            .statsPopover(isPresented: $showingStats, element: element, team: team,
                          fixtures: fixtures, teams: teams)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let flag = element.availabilityFlag {
                    // Details live in the info popover.
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.color(for: flag))
                        .accessibilityLabel(element.availabilityDescription)
                }
                Text(element.webName)
                    .font(.headline)
                    .foregroundStyle(element.availabilityFlag.map(Theme.color(for:)) ?? Theme.text)
                if let team {
                    Text(team.shortName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            // Start the separator at this column, not at the name, so flagged
            // rows (icon before the name) line up with the rest.
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            Spacer()
            HStack(spacing: 12) {
                Text(String(format: "£%.1fm", element.price))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 52, alignment: .trailing)
                Text(stat)
                    .fontWeight(.semibold)
                    .frame(minWidth: 56, alignment: .trailing)
            }
            .font(.subheadline.monospacedDigit())
        }
    }
}

#Preview {
    PlayersView()
        .environmentObject(LinkedTeamStore())
        .modelContainer(for: Note.self, inMemory: true)
}
