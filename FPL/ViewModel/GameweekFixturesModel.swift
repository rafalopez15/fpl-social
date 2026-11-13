//
//  GameweekFixturesModel.swift
//  FPL
//

import Foundation

/// The Gameweek tab's matches: one gameweek at a time, live from the API.
@MainActor
final class GameweekFixturesModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded
        /// Failed with nothing to show for this gameweek.
        case failed
    }

    /// The gameweek shown; nil until `open` has picked one.
    @Published private(set) var gameweek: Int?
    @Published private(set) var state: State = .loading
    @Published private(set) var fixtures: [Fixture] = []
    /// When the fixtures shown were fetched, if they're the API's saved copy from
    /// while FPL is down. Nil when they're fresh.
    @Published private(set) var staleAsOf: Date?

    /// True when the latest load failed and an earlier one's fixtures are still shown.
    @Published private(set) var couldntUpdate = false

    /// How often the gameweek shown reloads itself: the endpoint's cache time.
    nonisolated static let refreshInterval: TimeInterval = 60

    /// True while the fixtures shown can change by the minute: a match is live, or
    /// they're a saved copy that FPL coming back replaces.
    var refreshesItself: Bool {
        staleAsOf != nil || fixtures.contains { if case .live = $0.matchState { true } else { false } }
    }

    /// Seconds until the gameweek shown should reload: `refreshInterval` after its last
    /// load started, 0 if that's past. Nil when it doesn't reload itself.
    func refreshDelay(now: Date = .now) -> TimeInterval? {
        guard refreshesItself else { return nil }
        guard let lastFetch else { return 0 }
        return max(0, Self.refreshInterval - now.timeIntervalSince(lastFetch))
    }

    private let now: () -> Date
    /// When the newest load started.
    private var lastFetch: Date?
    private let load: (_ gameweek: Int) async throws -> Fetched<[Fixture]>
    /// Gameweeks loaded this session, shown at once when stepping back to one.
    private var loaded: [Int: Fetched<[Fixture]>] = [:]
    /// Counts selections, so only the newest one's answer is shown.
    private var selection = 0
    /// False until `open` has finished without being cancelled.
    private var hasOpened = false

    private enum Outcome {
        case loaded, failed, cancelled
    }

    init(client: FPLAPIClient = FPLAPIClient()) {
        load = { try await client.fixtures(gameweek: $0) }
        now = { .now }
    }

    /// For tests: fixtures from `load` instead of the API, as a saved copy from
    /// `staleAsOf` when that gives a time.
    init(staleAsOf: @escaping (_ gameweek: Int) -> Date? = { _ in nil }, now: @escaping () -> Date = { .now },
         load: @escaping (_ gameweek: Int) async throws -> [Fixture]) {
        self.now = now
        self.load = { Fetched(value: try await load($0), staleAsOf: staleAsOf($0)) }
    }

    /// Picks the gameweek to start on, once: `current`, or `next` when every match
    /// of `current` has been played. A cancelled call starts again on the next one.
    func open(current: Int, next: Int?) async {
        guard !hasOpened else { return }
        var target = current
        var outcome = await show(current)
        if outcome == .loaded, gameweek == current {
            target = Fixture.gameweekToOpen(current: current, next: next, currentFixtures: fixtures)
            if target != current { outcome = await show(target) }
        }
        // Cancelled with its gameweek still shown, so nothing else is loading it.
        hasOpened = outcome != .cancelled || gameweek != target
    }

    /// Shows `gameweek`: what was loaded before straight away, then the latest.
    func select(_ gameweek: Int) async {
        await show(gameweek)
    }

    @discardableResult
    private func show(_ gameweek: Int) async -> Outcome {
        selection += 1
        self.gameweek = gameweek
        fixtures = loaded[gameweek]?.value ?? []
        staleAsOf = loaded[gameweek]?.staleAsOf
        couldntUpdate = false
        state = loaded[gameweek] == nil ? .loading : .loaded
        return await fetch(gameweek, selection: selection)
    }

    /// Loads the gameweek shown again. False if it failed, which keeps what's shown.
    @discardableResult
    func reload() async -> Bool {
        guard let gameweek else { return true }
        if state == .failed { state = .loading }
        return await fetch(gameweek, selection: selection) != .failed
    }

    private func fetch(_ gameweek: Int, selection: Int) async -> Outcome {
        lastFetch = now()
        do {
            show(try await load(gameweek), for: gameweek, selection: selection)
            return .loaded
        } catch where error is CancellationError || (error as? URLError)?.code == .cancelled {
            // Not an answer about the gameweek: it stays as it was.
            return .cancelled
        } catch {
            if selection == self.selection {
                if loaded[gameweek] == nil { state = .failed } else { couldntUpdate = true }
            }
            return .failed
        }
    }

    private func show(_ fetched: Fetched<[Fixture]>, for gameweek: Int, selection: Int) {
        loaded[gameweek] = fetched
        guard selection == self.selection else { return }
        fixtures = fetched.value
        staleAsOf = fetched.staleAsOf
        couldntUpdate = false
        state = .loaded
    }
}
