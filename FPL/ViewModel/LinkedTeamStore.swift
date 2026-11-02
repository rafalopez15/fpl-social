//
//  LinkedTeamStore.swift
//  FPL
//

import Foundation

/// The FPL team linked on this device. The link is stored in UserDefaults, so it
/// survives restarts without an account. Shared via the environment so other
/// features (transfer notes, FPL-12) can read the manager ID.
@MainActor
final class LinkedTeamStore: ObservableObject {
    /// The linked team, or nil when none is linked.
    @Published private(set) var linked: LinkedTeam?
    /// The latest details for the linked team (points, rank). Nil until refreshed.
    @Published private(set) var manager: Manager?
    /// Transfers made since the last check, waiting for the "why" prompt.
    @Published private(set) var pendingTransfers: [NamedTransfer] = []
    /// Every transfer this season, newest first, for Profile. Nil until loaded.
    @Published private(set) var transferHistory: [NamedTransfer]?
    /// Free transfers for the next deadline, worked out from the history. Nil until loaded.
    @Published private(set) var freeTransfers: Int?
    /// True when the last attempt to load `transferHistory` failed.
    @Published private(set) var transferHistoryFailed = false

    private let defaults: UserDefaults
    private let client: FPLAPIClient
    private static let key = "linkedTeam"
    /// Transfers made before this time have been prompted for, or predate the link.
    private static let seenKey = "transfersSeenUntil"
    private var isChecking = false
    /// Player names by id, kept from the last `/elements` load.
    private var names: [Int: String] = [:]
    /// The last history loaded, so new transfers can update `freeTransfers`.
    private var history: ManagerHistory?

    init(defaults: UserDefaults = .standard, client: FPLAPIClient = FPLAPIClient()) {
        self.defaults = defaults
        self.client = client
        if let data = defaults.data(forKey: Self.key) {
            linked = try? JSONDecoder().decode(LinkedTeam.self, from: data)
        }
        // Links made before transfer notes existed start watching from now.
        if linked != nil, transfersSeenUntil == nil { transfersSeenUntil = .now }
    }

    private var transfersSeenUntil: Date? {
        get { defaults.object(forKey: Self.seenKey) as? Date }
        set { defaults.set(newValue, forKey: Self.seenKey) }
    }

    /// Links a team the user has confirmed, replacing any linked before.
    func link(_ manager: Manager) {
        let team = LinkedTeam(manager)
        linked = team
        self.manager = manager
        defaults.set(try? JSONEncoder().encode(team), forKey: Self.key)
        // Only transfers made from now on get a prompt; the season so far doesn't.
        transfersSeenUntil = .now
        pendingTransfers = []
        transferHistory = nil
        transferHistoryFailed = false
        freeTransfers = nil
        history = nil
    }

    func unlink() {
        linked = nil
        manager = nil
        pendingTransfers = []
        transferHistory = nil
        transferHistoryFailed = false
        freeTransfers = nil
        history = nil
        defaults.removeObject(forKey: Self.key)
        defaults.removeObject(forKey: Self.seenKey)
    }

    /// Looks for transfers made since the last check and queues them for the
    /// prompt. Runs on launch and when the app returns to the foreground.
    /// Failures just wait for the next check.
    func checkForTransfers() async {
        guard let id = linked?.id, let seenUntil = transfersSeenUntil,
              pendingTransfers.isEmpty, !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        guard let transfers = try? await client.transfers(managerID: id) else { return }
        let new = Transfer.made(after: seenUntil, in: transfers)
        guard !new.isEmpty else { return }

        // Names for the prompt; without them, wait rather than show bare ids.
        guard await loadNames(including: new), linked?.id == id else { return }
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

    /// Fetches the linked team's latest points and rank. Failures keep what's
    /// shown: the saved names are enough to display the link.
    func refresh() async {
        guard let id = linked?.id else { return }
        async let fresh = try? client.manager(id: id)
        async let season = try? client.transfers(managerID: id)
        async let gameweeks = try? client.history(managerID: id)
        let (manager, transfers, history) = await (fresh, season, gameweeks)
        guard linked?.id == id else { return }
        if let manager { self.manager = manager }
        if let history { self.history = history }
        if let history, let transfers {
            freeTransfers = FreeTransfers.available(history: history, upcoming: transfers)
        }

        guard let transfers, await loadNames(including: transfers), linked?.id == id else {
            if transferHistory == nil { transferHistoryFailed = true }
            return
        }
        transferHistory = transfers.map { NamedTransfer($0, names: names) }
        transferHistoryFailed = false
    }

    /// Loads player names from `/elements` unless every player in `transfers`
    /// is already known. Returns false if they couldn't be loaded.
    private func loadNames(including transfers: [Transfer]) async -> Bool {
        let ids = transfers.flatMap { [$0.elementIn, $0.elementOut] }
        if ids.allSatisfy({ names[$0] != nil }) { return true }
        guard let elements = try? await client.elements() else { return false }
        names = Dictionary(elements.map { ($0.id, $0.webName) }, uniquingKeysWith: { first, _ in first })
        return true
    }
}

/// A transfer with player names resolved, for the prompt and Profile's list.
struct NamedTransfer: Identifiable, Hashable {
    let transfer: Transfer
    let noteTransfer: NoteTransfer

    var id: String { "\(transfer.time.timeIntervalSince1970)-\(transfer.elementIn)" }

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
