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

    private let load: (_ gameweek: Int) async throws -> [Fixture]
    /// Gameweeks loaded this session, shown at once when stepping back to one.
    private var loaded: [Int: [Fixture]] = [:]
    /// Counts selections, so only the newest one's answer is shown.
    private var selection = 0

    init(client: FPLAPIClient = FPLAPIClient()) {
        load = { try await client.fixtures(gameweek: $0) }
    }

    /// For tests: fixtures from `load` instead of the API.
    init(load: @escaping (_ gameweek: Int) async throws -> [Fixture]) {
        self.load = load
    }

    /// Picks the gameweek to start on, once: `current`, or `next` when every match
    /// of `current` has been played.
    func open(current: Int, next: Int?) async {
        guard gameweek == nil else { return }
        await select(current)
        guard gameweek == current, state == .loaded else { return }
        let opening = Fixture.gameweekToOpen(current: current, next: next, currentFixtures: fixtures)
        if opening != current { await select(opening) }
    }

    /// Shows `gameweek`: what was loaded before straight away, then the latest.
    func select(_ gameweek: Int) async {
        selection += 1
        self.gameweek = gameweek
        fixtures = loaded[gameweek] ?? []
        state = loaded[gameweek] == nil ? .loading : .loaded
        await fetch(gameweek, selection: selection)
    }

    /// Loads the gameweek shown again. False if it failed, which keeps what's shown.
    @discardableResult
    func reload() async -> Bool {
        guard let gameweek else { return true }
        if state == .failed { state = .loading }
        return await fetch(gameweek, selection: selection)
    }

    @discardableResult
    private func fetch(_ gameweek: Int, selection: Int) async -> Bool {
        do {
            show(try await load(gameweek), for: gameweek, selection: selection)
            return true
        } catch {
            if selection == self.selection, loaded[gameweek] == nil { state = .failed }
            return false
        }
    }

    private func show(_ fixtures: [Fixture], for gameweek: Int, selection: Int) {
        loaded[gameweek] = fixtures
        guard selection == self.selection else { return }
        self.fixtures = fixtures
        state = .loaded
    }
}
