//
//  ContentView.swift
//  FPL
//
//  Created by Rafael Lopez on 11/4/24.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ElementViewModel(position: .forward)

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
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
                        ElementRow(element: element)
                    }
                    .refreshable { await viewModel.fetchElements() }
                    .searchable(text: $viewModel.searchQuery,
                                prompt: "Search \(viewModel.position.title.lowercased())")
                }
            }
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
        }
        // Runs on appear and again whenever the position changes,
        // cancelling any fetch still in flight.
        .task(id: viewModel.position) {
            await viewModel.fetchElements()
        }
    }
}

private struct ElementRow: View {
    let element: Element

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(element.fullName)
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
                Text("\(element.totalPoints ?? 0) pts")
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
