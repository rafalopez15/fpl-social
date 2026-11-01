//
//  ElementViewModel.swift
//  FPL
//
//  Created by Rafael Lopez on 12/3/24.
//

import Foundation

@MainActor
class ElementViewModel: ObservableObject {
    @Published private(set) var elements: [Element] = []
    @Published private(set) var isLoading: Bool = true
    @Published private(set) var errorMessage: String? = nil
    @Published var searchQuery: String = ""

    @Published var filter = ElementFilter()
    @Published var sort: ElementSort = .points
    @Published var sortAscending = false

    /// The position being shown. The view refetches whenever this changes.
    @Published var position: Element.Position {
        didSet {
            guard position != oldValue else { return }
            // Price ranges differ a lot between positions, so drop the price limit.
            filter.maxPrice = nil
            // Don't show the previous position's players under the new title.
            elements = []
        }
    }

    private let client: FPLAPIClient
    /// Incremented per fetch so only the most recent one updates state.
    private var fetchGeneration = 0

    init(position: Element.Position = .forward, client: FPLAPIClient = FPLAPIClient()) {
        self.position = position
        self.client = client
    }

    func fetchElements() async {
        fetchGeneration += 1
        let generation = fetchGeneration
        isLoading = true
        errorMessage = nil
        // Always clear loading when the latest fetch ends, including when it's
        // cancelled, so the spinner can never get stuck.
        defer { if generation == fetchGeneration { isLoading = false } }

        do {
            let elements = try await client.elements(position: position)
            // A newer fetch (e.g. the position changed) owns the state now.
            guard generation == fetchGeneration else { return }
            self.elements = elements
        } catch {
            guard generation == fetchGeneration, !Self.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    func resetFilters() {
        filter = ElementFilter()
        sort = .points
        sortAscending = false
    }

    /// Players matching the search and filters, in the chosen sort order.
    var filteredElements: [Element] {
        elements
            .filter { filter.matches($0) && matchesSearch($0) }
            .sorted { a, b in
                let lhs = sort.value(for: a), rhs = sort.value(for: b)
                if lhs != rhs { return sortAscending ? lhs < rhs : lhs > rhs }
                // Ties: higher points first, then name, so the order is stable.
                if a.totalPoints != b.totalPoints { return (a.totalPoints ?? 0) > (b.totalPoints ?? 0) }
                return a.webName < b.webName
            }
    }

    // MARK: - Bounds for the filter controls

    /// Cheapest to most expensive price in the loaded players, or `nil` if there's no spread.
    var priceRange: ClosedRange<Double>? {
        let prices = elements.map(\.price)
        guard let low = prices.min(), let high = prices.max(), low < high else { return nil }
        return low...high
    }

    private func matchesSearch(_ element: Element) -> Bool {
        searchQuery.isEmpty
            || element.fullName.localizedCaseInsensitiveContains(searchQuery)
            || element.webName.localizedCaseInsensitiveContains(searchQuery)
    }
}
