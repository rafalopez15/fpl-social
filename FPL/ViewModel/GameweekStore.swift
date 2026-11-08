//
//  GameweekStore.swift
//  FPL
//

import Foundation

/// The season's gameweeks and the current one, shared across tabs so notes can
/// be tagged with a gameweek and the Notes tab can show deadlines.
@MainActor
final class GameweekStore: ObservableObject {
    /// Nil until loaded, or if loading failed. Call `loadIfNeeded()` to retry.
    @Published private(set) var current: Int?
    /// Every gameweek, empty until loaded.
    @Published private(set) var events: [Event] = []

    /// True when the last load failed, so the Notes tab can offer a retry.
    @Published private(set) var didFail = false

    /// The app's gameweeks, shared with the stores that build fixture schedules.
    static let shared = GameweekStore()

    private let client: FPLAPIClient
    /// The load running now, which another call waits for instead of starting another.
    private var runningLoad: Task<Bool, Never>?

    init(client: FPLAPIClient = FPLAPIClient()) {
        self.client = client
    }

    /// Loads unless loaded; waits for a load already running.
    func loadIfNeeded() async {
        guard current == nil else { return }
        await reload()
    }

    /// Loads the gameweeks even if they've loaded, so the current gameweek and
    /// deadlines move on when the app stays open across a deadline. A failure keeps
    /// what's loaded. Returns false if it failed.
    @discardableResult
    func reload() async -> Bool {
        if let runningLoad { return await runningLoad.value }
        let load = Task { await loadOnce() }
        runningLoad = load
        defer { runningLoad = nil }
        return await load.value
    }

    private func loadOnce() async -> Bool {
        // With nothing to show, a retry shows the spinner again rather than the error.
        if events.isEmpty { didFail = false }
        guard let events = try? await client.events() else {
            didFail = self.events.isEmpty
            return false
        }
        didFail = false
        self.events = events
        current = Event.currentGameweek(in: events)
        return true
    }

    /// The gameweek's transfer deadline, if gameweeks have loaded.
    func deadline(for gameweek: Int) -> Date? {
        events.first { $0.id == gameweek }?.deadlineTime
    }
}

extension Event {
    /// The gameweek in progress (or most recently started), or before the
    /// season starts, the first one.
    static func currentGameweek(in events: [Event]) -> Int? {
        events.first(where: \.isCurrent)?.id ?? events.first(where: \.isNext)?.id
    }
}
