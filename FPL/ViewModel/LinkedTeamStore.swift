//
//  LinkedTeamStore.swift
//  FPL
//

import Foundation
import OSLog

/// The FPL team linked on this device. The link is stored in UserDefaults, so it
/// survives restarts without an account. Shared via the environment so other
/// features (transfer notes, FPL-12) can read the manager ID.
@MainActor
final class LinkedTeamStore: ObservableObject {
    /// The linked team, or nil when none is linked.
    @Published private(set) var linked: LinkedTeam?
    /// The latest details for the linked team (points, rank). Nil until refreshed.
    @Published private(set) var manager: Manager?
    /// The details couldn't load and there are none to show.
    @Published private(set) var managerFailed = false
    /// Transfers made since the last check, waiting for the "why" prompt.
    @Published private(set) var pendingTransfers: [NamedTransfer] = []
    /// Every transfer this season, newest first, for Profile. Nil until loaded.
    @Published private(set) var transferHistory: [NamedTransfer]?
    /// Free transfers for the next deadline, worked out from the history. Nil until loaded.
    @Published private(set) var freeTransfers: Int?
    /// True when the last attempt to load `transferHistory` failed.
    @Published private(set) var transferHistoryFailed = false
    /// The squad as of the latest deadline, for Profile.
    @Published private(set) var squad: SquadState = .loading
    /// Points in the squad's gameweek, from `/events/{gw}/live`. Nil until loaded
    /// or when it failed, and the squad then shows without points.
    @Published private(set) var livePoints: LivePoints?
    /// Squads for gameweeks before the latest, by gameweek, loaded when Profile's
    /// gameweek stepper goes back. Kept for the session: past squads don't change.
    @Published private(set) var earlierSquads: [Int: SquadState] = [:]
    @Published private(set) var earlierPoints: [Int: LivePoints] = [:]
    /// Players by id from the last `/elements` load: names for transfers, and the
    /// squad's rows and stats popovers.
    @Published private(set) var players: [Int: Element] = [:]

    private let defaults: UserDefaults
    private let client: FPLAPIClient
    private let lookups: TeamsAndFixturesStore
    private static let key = "linkedTeam"
    /// Per team id: transfers made before this time have been prompted for, or
    /// predate the team's first link. Per team, so switching between teams keeps each one's.
    private static let seenKey = "transfersSeenUntilByTeam"
    private var isChecking = false
    /// The refresh running now and its team, which a second call for the same team
    /// waits for instead of starting another.
    private var runningRefresh: (teamID: Int, task: Task<Bool, Never>)?
    /// The same for loading players, which refresh and the transfer check both do.
    private var runningPlayersLoad: Task<Bool, Never>?
    /// The last transfers fetched, reused for 10 seconds: at launch the transfer check
    /// and Profile's refresh both want them, a moment apart. The server caches them for 60.
    private var recentTransfers: RecentTransfers?
    /// The transfers fetch running now, shared until it has saved its result.
    private var runningTransfers: (teamID: Int, task: Task<[Transfer], Error>)?

    private struct RecentTransfers {
        let teamID: Int
        let fetchedAt: Date
        let transfers: [Transfer]
    }
    /// The season so far: points and rank per gameweek for the Notes tab, and
    /// transfers per gameweek for `freeTransfers`. Nil until loaded.
    @Published private(set) var history: ManagerHistory?

    /// - Parameter lookups: Where live points get fixtures. The app passes the shared
    ///   one; nil makes a store of its own on `client`, as tests want.
    init(defaults: UserDefaults = .standard, client: FPLAPIClient = FPLAPIClient(),
         lookups: TeamsAndFixturesStore? = nil) {
        self.defaults = defaults
        self.client = client
        self.lookups = lookups ?? TeamsAndFixturesStore(client: client, gameweeks: GameweekStore(client: client))
        if let data = defaults.data(forKey: Self.key) {
            do {
                linked = try JSONDecoder().decode(LinkedTeam.self, from: data)
            } catch {
                Logger.linkedTeam.error("Couldn't read the saved team, showing none: \(error.logSummary, privacy: .public)")
            }
        }
        // Links made before transfer notes existed start watching from now.
        if linked != nil, transfersSeenUntil == nil { transfersSeenUntil = .now }
    }

    func transfersSeenUntil(for id: Int) -> Date? {
        defaults.dictionary(forKey: Self.seenKey)?[String(id)] as? Date
    }

    private func setTransfersSeenUntil(_ date: Date?, for id: Int) {
        var seen = defaults.dictionary(forKey: Self.seenKey) ?? [:]
        seen[String(id)] = date
        defaults.set(seen, forKey: Self.seenKey)
    }

    /// The linked team's.
    private var transfersSeenUntil: Date? {
        get { linked.flatMap { transfersSeenUntil(for: $0.id) } }
        set { if let id = linked?.id { setTransfersSeenUntil(newValue, for: id) } }
    }

    /// Links a team the user has confirmed, replacing any linked before.
    func link(_ manager: Manager) {
        link(LinkedTeam(manager), manager: manager)
    }

    /// Links a team known by name, such as another of your teams switched to from the
    /// account's list. `refresh()` loads the card's details if `manager` is nil.
    func link(_ team: LinkedTeam, manager: Manager? = nil) {
        save(team)
        self.manager = manager
        managerFailed = false
        Logger.linkedTeam.notice("Linked team \(team.id, privacy: .private)")
        // Only transfers made from now on get a prompt; the season so far doesn't.
        // A team linked before, such as one switched back to, keeps its time.
        if transfersSeenUntil == nil { transfersSeenUntil = .now }
        pendingTransfers = []
        transferHistory = nil
        transferHistoryFailed = false
        freeTransfers = nil
        history = nil
        squad = .loading
        livePoints = nil
        earlierSquads = [:]
        earlierPoints = [:]
    }

    func unlink() {
        if let id = linked?.id { setTransfersSeenUntil(nil, for: id) }
        linked = nil
        manager = nil
        managerFailed = false
        pendingTransfers = []
        transferHistory = nil
        transferHistoryFailed = false
        freeTransfers = nil
        history = nil
        squad = .loading
        livePoints = nil
        earlierSquads = [:]
        earlierPoints = [:]
        defaults.removeObject(forKey: Self.key)
        Logger.linkedTeam.notice("Unlinked team")
    }

    /// Looks for transfers made since the last check and queues them for the
    /// prompt. Runs on launch and when the app returns to the foreground.
    /// Failures just wait for the next check.
    func checkForTransfers() async {
        guard let id = linked?.id, let seenUntil = transfersSeenUntil,
              pendingTransfers.isEmpty, !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        guard let transfers = try? await transfers(managerID: id) else { return }
        let new = Transfer.made(after: seenUntil, in: transfers)
        guard !new.isEmpty else { return }
        guard !Transfer.hasUnmarkedChurn(new) else {
            Logger.linkedTeam.info("Holding the transfer prompt: \(new.count) new transfers include unmarked churn")
            return
        }

        // Names for the prompt; without them, wait rather than show bare ids.
        guard await loadPlayers(Transfer.players(in: new)), linked?.id == id else { return }
        Logger.linkedTeam.info("Prompting for \(new.count) new transfer(s)")
        pendingTransfers = new.map { NamedTransfer($0, names: names) }
        // Keep Profile in step with the prompt.
        transferHistory = transfers.map { NamedTransfer($0, names: names) }
        if let history { freeTransfers = FreeTransfers.available(history: history, upcoming: transfers) }
    }

    /// Called once the prompt is saved or put off: these transfers won't be asked about again.
    func finishPrompt() {
        if let latest = pendingTransfers.map(\.transfer.time).max() {
            transfersSeenUntil = max(latest, transfersSeenUntil ?? latest)
        }
        pendingTransfers = []
    }

    /// Fetches the linked team's latest points, rank, transfers and squad.
    /// Failures keep what's shown: the saved team name and ID are enough to display the link.
    /// Returns false if any of it failed (a squad 404, before the first deadline, isn't a failure).
    @discardableResult
    func refresh() async -> Bool {
        guard let id = linked?.id else { return true }
        if let runningRefresh, runningRefresh.teamID == id { return await runningRefresh.task.value }
        let refresh = Task { await refreshOnce() }
        runningRefresh = (id, refresh)
        let result = await refresh.value
        if runningRefresh?.task == refresh { runningRefresh = nil }
        return result
    }

    private func refreshOnce() async -> Bool {
        guard let id = linked?.id else { return true }
        // A retry after a failure shows the placeholder again while it loads.
        if squad == .failed { squad = .loading }
        async let fresh = try? client.manager(id: id)
        async let season = try? transfers(managerID: id)
        async let gameweeks = try? client.history(managerID: id)
        async let squadResult = fetchPicks(managerID: id)
        let (manager, transfers, history, picks) = await (fresh, season, gameweeks, squadResult)
        guard linked?.id == id else { return true }
        if let manager {
            self.manager = manager
            // A name from the account's list can be a day old, and teams get renamed.
            if manager.name != linked?.teamName { save(LinkedTeam(manager)) }
        }
        managerFailed = self.manager == nil
        if let history { self.history = history }
        if let history, let transfers {
            freeTransfers = FreeTransfers.available(history: history, upcoming: transfers)
        }

        let squadPicks = try? picks.get()
        // The gameweek the picks came back with, so points always match the squad.
        let gameweek = squadPicks?.entryHistory?.event
        async let live = fetchLivePoints(gameweek: gameweek)
        let ids = Transfer.players(in: transfers ?? []) + (squadPicks?.picks.map(\.element) ?? [])
        let playersLoaded = await loadPlayers(ids)
        let fetchedLive = await live
        guard linked?.id == id else { return true }

        if let transfers, playersLoaded {
            transferHistory = transfers.map { NamedTransfer($0, names: names) }
            transferHistoryFailed = false
        } else if transferHistory == nil {
            transferHistoryFailed = true
        }

        squad = SquadState(picks, playersLoaded: playersLoaded, previous: squad)
        // A failed call keeps points already shown for the same gameweek.
        if let fetchedLive {
            livePoints = fetchedLive
        } else if livePoints?.gameweek != gameweek {
            livePoints = nil
        }
        // No gameweek means no squad, which picks already reports.
        let pointsLoaded = gameweek == nil || fetchedLive != nil
        return manager != nil && transfers != nil && history != nil && playersLoaded && pointsLoaded
            && Self.isAnswer(picks)
    }

    /// Pull to refresh: the team card and latest squad, and the earlier gameweek
    /// being viewed if it is one. Returns false if any of it failed.
    func refresh(viewing selected: Int?) async -> Bool {
        // Known before refreshing, so both load at once.
        guard let earlier = earlierGameweek(selected) else { return await refresh() }
        async let latest = refresh()
        async let earlierLoaded = loadSquad(gameweek: earlier, reload: true)
        let (latestOK, earlierOK) = await (latest, earlierLoaded)
        return latestOK && earlierOK
    }

    /// The stepper's pick if it's an earlier gameweek; nil means the latest squad.
    func earlierGameweek(_ selected: Int?) -> Int? {
        guard let selected, let range = squadGameweeks,
              range.contains(selected), selected < range.upperBound else { return nil }
        return selected
    }

    /// A squad, or a 404 saying there's none: both are answers, not failures.
    private static func isAnswer(_ picks: Result<ManagerPicks, Error>) -> Bool {
        switch picks {
        case .success, .failure(FPLAPIClient.APIError.notFound): true
        case .failure: false
        }
    }

    /// Points gained or lost by transfers this season, minus hits; nil until known.
    var transferNet: Int? {
        transferHistory.flatMap { Transfer.net(of: $0.map(\.transfer), history: history) }
    }

    /// The gameweeks the squad stepper can show: from the one the manager joined
    /// to the latest squad's. Nil until the latest squad has loaded.
    var squadGameweeks: ClosedRange<Int>? {
        guard case .loaded(let picks) = squad, let latest = picks.entryHistory?.event else { return nil }
        return min(manager?.startedEvent ?? 1, latest)...latest
    }

    /// Loads the squad and points for an earlier gameweek, unless already loaded
    /// (`reload` loads it again, keeping it shown meanwhile). A failure shows Retry
    /// for that gameweek; a 404 shows that there's no squad. Returns false if it failed.
    ///
    /// Stepping past a gameweek cancels its load (the view's `.task(id:)`). A
    /// cancelled load writes nothing: its requests fail with a cancellation that
    /// isn't a real failure, and a newer load of the same gameweek may be running.
    @discardableResult
    func loadSquad(gameweek: Int, reload: Bool = false) async -> Bool {
        guard let id = linked?.id else { return true }
        let previous = earlierSquads[gameweek] ?? .loading
        if case .loaded = previous {
            guard reload else { return true }
        } else {
            earlierSquads[gameweek] = .loading
        }
        async let picks = fetchPicks(managerID: id, gameweek: gameweek)
        // Past gameweeks have no matches left to play, so fixtures aren't needed.
        async let live = try? client.livePoints(gameweek: gameweek)
        let (result, elements) = await (picks, live)
        let ids = (try? result.get())?.picks.map(\.element) ?? []
        let playersLoaded = await loadPlayers(ids)
        guard !Task.isCancelled, linked?.id == id else { return true }
        if let elements {
            earlierPoints[gameweek] = LivePoints(gameweek: gameweek, elements: elements, fixtures: nil)
        }
        earlierSquads[gameweek] = SquadState(result, playersLoaded: playersLoaded, previous: previous)
        // Points only count when there's a squad to show them on.
        let pointsLoaded = elements != nil || (try? result.get()) == nil
        return playersLoaded && pointsLoaded && Self.isAnswer(result)
    }

    /// Nil without a gameweek or if the live call fails. Fixtures failing only
    /// means nobody shows as yet to play.
    private func fetchLivePoints(gameweek: Int?) async -> LivePoints? {
        guard let gameweek else { return nil }
        async let elements = client.livePoints(gameweek: gameweek)
        async let fixtures = lookups.upcomingFixtures()
        guard let elements = try? await elements else { return nil }
        return LivePoints(gameweek: gameweek, elements: elements, fixtures: await fixtures)
    }

    private func fetchPicks(managerID: Int, gameweek: Int? = nil) async -> Result<ManagerPicks, Error> {
        do { return .success(try await client.picks(managerID: managerID, gameweek: gameweek)) } catch { return .failure(error) }
    }

    private var names: [Int: String] { players.mapValues(\.webName) }

    private func transfers(managerID id: Int) async throws -> [Transfer] {
        if let recentTransfers, recentTransfers.teamID == id, recentTransfers.fetchedAt.timeIntervalSinceNow > -10 {
            return recentTransfers.transfers
        }
        if let runningTransfers, runningTransfers.teamID == id { return try await runningTransfers.task.value }
        let fetch = Task { [client] in
            let transfers = try await client.transfers(managerID: id)
            recentTransfers = RecentTransfers(teamID: id, fetchedAt: .now, transfers: transfers)
            return transfers
        }
        runningTransfers = (id, fetch)
        defer { if runningTransfers?.task == fetch { runningTransfers = nil } }
        return try await fetch.value
    }

    /// Loads players from `/elements` unless every id is already known.
    /// Returns false if they couldn't be loaded.
    private func loadPlayers(_ ids: [Int]) async -> Bool {
        if ids.allSatisfy({ players[$0] != nil }) { return true }
        if let runningPlayersLoad { return await runningPlayersLoad.value }
        let load = Task { () -> Bool in
            guard let elements = try? await client.elements() else { return false }
            players = Dictionary(elements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return true
        }
        runningPlayersLoad = load
        defer { runningPlayersLoad = nil }
        return await load.value
    }
}

extension LinkedTeamStore {
    /// The latest squad's gameweek points. `events` say whether FPL has confirmed it.
    func gameweekPoints(events: [Event]) -> GameweekPoints? {
        guard case .loaded(let picks) = squad else { return nil }
        let event = events.first { $0.id == picks.entryHistory?.event }
        return picks.gameweekPoints(live: livePoints, event: event)
    }
}

/// Profile's squad section: loading, the squad, none yet, or failed.
enum SquadState: Equatable {
    case loading
    case loaded(ManagerPicks)
    /// 404: before the manager's first deadline, or the team no longer exists.
    case none
    /// FPL down (503), no connection, or the players couldn't load. Retry with `refresh()`.
    case failed

    /// The state after a fetch. A failure keeps a squad already on screen.
    init(_ result: Result<ManagerPicks, Error>, playersLoaded: Bool, previous: SquadState) {
        switch result {
        case .success(let picks) where playersLoaded:
            self = .loaded(picks)
        case .failure(FPLAPIClient.APIError.notFound):
            self = .none
        default:
            if case .loaded = previous { self = previous } else { self = .failed }
        }
    }
}

extension Transfer {
    /// Both players in each transfer, for loading names.
    static func players(in transfers: [Transfer]) -> [Int] {
        transfers.flatMap { [$0.elementIn, $0.elementOut] }
    }
}

/// A transfer with player names resolved, for the prompt and Profile's list.
struct NamedTransfer: Identifiable, Hashable {
    let transfer: Transfer
    let noteTransfer: NoteTransfer

    /// Time too: without churn marked, a chip week can repeat a swap.
    var id: String {
        "\(transfer.event)-\(transfer.elementIn)-\(transfer.elementOut)-\(transfer.time.timeIntervalSince1970)"
    }

    /// Groups transfers by gameweek, latest gameweek first and newest transfer
    /// first within each, for Profile's list.
    static func byGameweek(_ transfers: [NamedTransfer]) -> [(gameweek: Int, transfers: [NamedTransfer])] {
        Dictionary(grouping: transfers) { $0.transfer.event }
            .map { (gameweek: $0.key, transfers: $0.value.sorted { $0.transfer.time > $1.transfer.time }) }
            .sorted { $0.gameweek > $1.gameweek }
    }

    init(_ transfer: Transfer, names: [Int: String]) {
        self.transfer = transfer
        noteTransfer = NoteTransfer(
            playerIn: NotePlayer(id: transfer.elementIn, webName: names[transfer.elementIn] ?? "Unknown player"),
            playerOut: NotePlayer(id: transfer.elementOut, webName: names[transfer.elementOut] ?? "Unknown player"),
            cost: transfer.elementInCost,
            outCost: transfer.elementOutCost,
            time: transfer.time
        )
    }
}

private extension LinkedTeamStore {
    func save(_ team: LinkedTeam) {
        linked = team
        do {
            defaults.set(try JSONEncoder().encode(team), forKey: Self.key)
        } catch {
            Logger.linkedTeam.fault("Couldn't save the linked team: \(error.logSummary, privacy: .public)")
        }
    }
}
