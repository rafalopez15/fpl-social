//
//  ContentView.swift
//  FPL
//
//  Created by Rafael Lopez on 11/4/24.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ElementViewModel(position: .forward)
    @State private var showingFilters = false

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
                        ElementRow(element: element, sort: viewModel.sort)
                    }
                    .overlay {
                        if viewModel.filteredElements.isEmpty && viewModel.filter.isActive {
                            ContentUnavailableView {
                                Label("No matching players", systemImage: "line.3.horizontal.decrease.circle")
                            } description: {
                                Text("Try loosening the filters.")
                            } actions: {
                                Button("Clear filters") { viewModel.filter = ElementFilter() }
                            }
                        }
                    }
                    .refreshable { await viewModel.fetchElements() }
                }
            }
            // On the Group so the bottom bar keeps its layout while loading.
            .searchable(text: $viewModel.searchQuery,
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
                if #available(iOS 26, *) {
                    // Filters button sits just left of the bottom search bar.
                    ToolbarItem(placement: .bottomBar) { filterButton }
                    ToolbarSpacer(.fixed, placement: .bottomBar)
                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
                } else {
                    ToolbarItem(placement: .topBarTrailing) { filterButton }
                }
            }
            .sheet(isPresented: $showingFilters) {
                FilterView(viewModel: viewModel)
            }
        }
        // Runs on appear and again whenever the position changes,
        // cancelling any fetch still in flight.
        .task(id: viewModel.position) {
            await viewModel.fetchElements()
        }
    }

    private var filterButton: some View {
        Button {
            showingFilters = true
        } label: {
            Image(systemName: viewModel.filter.isActive
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Sort and filter")
    }
}

private struct ElementRow: View {
    let element: Element
    /// The right-hand stat follows the sort, so sorting by goals shows goals.
    let sort: ElementSort
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
            .accessibilityLabel("Stats for \(element.webName)")
            .popover(isPresented: $showingStats, arrowEdge: .leading) {
                ElementStatsView(element: element)
                    // Show as a popover bubble on iPhone instead of a full sheet.
                    .presentationCompactAdaptation(.popover)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(element.webName)
                    .font(.headline)
                if let news = element.currentNews {
                    Text(news)
                        .font(.caption)
                        .foregroundStyle(element.status == .available ? Color.secondary : Color.orange)
                }
            }
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
    ContentView()
}
