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

    let position: Element.Position
    private let client: FPLAPIClient

    init(position: Element.Position = .forward, client: FPLAPIClient = FPLAPIClient()) {
        self.position = position
        self.client = client
    }

    func fetchElements() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let elements = try await client.elements(position: position)
            sortedElements = elements.sorted { ($0.totalPoints ?? 0) > ($1.totalPoints ?? 0) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var filteredElements: [Element] {
        guard !searchQuery.isEmpty else { return sortedElements }
        return sortedElements.filter {
            $0.fullName.localizedCaseInsensitiveContains(searchQuery)
                || $0.webName.localizedCaseInsensitiveContains(searchQuery)
        }
    }
}
