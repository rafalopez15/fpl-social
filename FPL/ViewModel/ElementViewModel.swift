//
//  ElementViewModel.swift
//  FPL
//
//  Created by Rafael Lopez on 12/3/24.
//

import Foundation

@MainActor
class ElementViewModel: ObservableObject {
    @Published private(set) var sortedElements: [Element] = []
    @Published private(set) var isLoading: Bool = true
    @Published private(set) var errorMessage: String? = nil
    @Published var searchQuery: String = ""

    /// The position being shown. The view refetches whenever this changes.
    @Published var position: Element.Position
    private let client: FPLAPIClient

    init(position: Element.Position = .forward, client: FPLAPIClient = FPLAPIClient()) {
        self.position = position
        self.client = client
    }

    func fetchElements() async {
        isLoading = true
        errorMessage = nil

        do {
            let elements = try await client.elements(position: position)
            // A newer fetch (e.g. the position changed) owns the state now.
            guard !Task.isCancelled else { return }
            sortedElements = elements.sorted { ($0.totalPoints ?? 0) > ($1.totalPoints ?? 0) }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    var filteredElements: [Element] {
        guard !searchQuery.isEmpty else { return sortedElements }
        return sortedElements.filter {
            $0.fullName.localizedCaseInsensitiveContains(searchQuery)
                || $0.webName.localizedCaseInsensitiveContains(searchQuery)
        }
    }
}
