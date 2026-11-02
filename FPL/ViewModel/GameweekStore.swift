//
//  GameweekStore.swift
//  FPL
//

import Foundation

/// The current gameweek, shared across tabs so new notes can be tagged with it.
@MainActor
final class GameweekStore: ObservableObject {
    /// Nil until loaded, or if loading failed. Call `loadIfNeeded()` to retry.
    @Published private(set) var current: Int?

    /// True when the last load failed, so the Notes tab can offer a retry.
    @Published private(set) var didFail = false

    private let client: FPLAPIClient
    private var isLoading = false

    init(client: FPLAPIClient = FPLAPIClient()) {
        self.client = client
    }

    func loadIfNeeded() async {
        guard current == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        didFail = false
        guard let events = try? await client.events() else {
            didFail = true
            return
        }
        current = Event.currentGameweek(in: events)
    }
}

extension Event {
    /// The gameweek in progress (or most recently started), or before the
    /// season starts, the first one.
    static func currentGameweek(in events: [Event]) -> Int? {
        events.first(where: \.isCurrent)?.id ?? events.first(where: \.isNext)?.id
    }
}
