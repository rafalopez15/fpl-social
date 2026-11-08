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

    @Published var sort: ElementSort = .points
    @Published var sortAscending = false

    /// The position being shown. The view refetches whenever this changes.
    @Published var position: Element.Position {
        didSet {
            guard position != oldValue else { return }
            // Don't show the previous position's players under the new title.
            elements = []
        }
    }

    private let client: FPLAPIClient
    /// Teams and fixtures, shared with Profile's squad so they load once; the view reads
    /// them from the shared store.
    private let lookups: TeamsAndFixturesStore
    /// Incremented per fetch so only the most recent one updates state.
    private var fetchGeneration = 0

    init(position: Element.Position = .forward, client: FPLAPIClient = FPLAPIClient(),
         lookups: TeamsAndFixturesStore = .shared) {
        self.position = position
        self.client = client
        self.lookups = lookups
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
            // Teams and fixtures load alongside the players. A failure there just
            // hides team names or fixtures, and they're retried on the next fetch.
            async let lookupsLoaded: Void = lookups.loadIfNeeded()
            let elements = try await client.elements(position: position)
            await lookupsLoaded
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

    /// Selectable players matching the search, in the chosen sort order.
    /// Players who left the league are hidden (see `Element.isSelectable`).
    var filteredElements: [Element] {
        elements
            .filter { $0.isSelectable && matchesSearch($0) }
            .sorted { a, b in
                let lhs = sort.value(for: a), rhs = sort.value(for: b)
                if lhs != rhs { return sortAscending ? lhs < rhs : lhs > rhs }
                // Ties: higher points first, then name, so the order is stable.
                if a.totalPoints != b.totalPoints { return (a.totalPoints ?? 0) > (b.totalPoints ?? 0) }
                return a.webName < b.webName
            }
    }

    private func matchesSearch(_ element: Element) -> Bool {
        searchQuery.isEmpty
            || element.fullName.localizedCaseInsensitiveContains(searchQuery)
            || element.webName.localizedCaseInsensitiveContains(searchQuery)
    }
}
