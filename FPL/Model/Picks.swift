//
//  Picks.swift
//  FPL
//

import Foundation

/// A manager's squad for one gameweek from `GET /api/managers/{id}/picks`.
/// FPL only publishes picks after the deadline, so this is the squad as of the
/// latest deadline. Only `element` and `position` are guaranteed on each pick.
struct ManagerPicks: Decodable, Equatable {
    /// `wildcard`, `freehit`, `bboost`, `3xc`, or nil.
    var activeChip: String? = nil
    let picks: [Pick]
    var automaticSubs: [AutomaticSub]? = nil
    var entryHistory: EntryHistory? = nil

    /// Positions 1–11, in order.
    var starters: [Pick] { picks.filter { $0.position <= 11 }.sorted { $0.position < $1.position } }

    /// Positions 12–15 in substitution order (12 is the backup goalkeeper).
    var bench: [Pick] { picks.filter { $0.position > 11 }.sorted { $0.position < $1.position } }

    /// The starting XI grouped GK, DEF, MID, FWD. `players` fills in the
    /// position when a pick has no `element_type`; a pick with neither is left out.
    func startingLines(players: [Int: Element]) -> [(position: Element.Position, picks: [Pick])] {
        let grouped = Dictionary(grouping: starters) { pick in
            (pick.elementType ?? players[pick.element]?.elementType).flatMap(Element.Position.init(rawValue:))
        }
        return Element.Position.allCases.compactMap { position in
            guard let picks = grouped[position], !picks.isEmpty else { return nil }
            return (position, picks)
        }
    }

    /// Players FPL brought on automatically, and the players they replaced.
    var subbedIn: Set<Int> { Set((automaticSubs ?? []).compactMap(\.elementIn)) }
    var subbedOut: Set<Int> { Set((automaticSubs ?? []).compactMap(\.elementOut)) }

    /// e.g. "Bench Boost". Nil without a chip.
    var chipTitle: String? {
        guard let activeChip, !activeChip.isEmpty else { return nil }
        switch activeChip {
        case "wildcard": return "Wildcard"
        case "freehit": return "Free Hit"
        case "bboost": return "Bench Boost"
        case "3xc": return "Triple Captain"
        default: return activeChip.capitalized
        }
    }

    struct Pick: Decodable, Equatable, Identifiable {
        /// `Element.id`.
        let element: Int
        /// 1–11 starting, 12–15 bench.
        let position: Int
        /// 0 on the bench, 1 playing, 2 captain, 3 triple captain.
        var multiplier: Int? = nil
        var isCaptain: Bool? = nil
        var isViceCaptain: Bool? = nil
        /// 1 GK, 2 DEF, 3 MID, 4 FWD.
        var elementType: Int? = nil

        var id: Int { element }

        /// "TC", "C" or "V", nil for everyone else.
        var badge: String? {
            if isCaptain == true { return multiplier == 3 ? "TC" : "C" }
            if isViceCaptain == true { return "V" }
            return nil
        }

        /// The player's gameweek points as they count for the team: doubled for
        /// the captain, tripled for a triple captain. Bench players show their
        /// own points, as FPL does.
        func points(from eventPoints: Int?) -> Int? {
            eventPoints.map { $0 * max(multiplier ?? 1, 1) }
        }
    }

    struct AutomaticSub: Decodable, Equatable {
        var elementIn: Int? = nil
        var elementOut: Int? = nil
        var event: Int? = nil
    }

    /// The team's gameweek. Only the fields the app shows are decoded.
    struct EntryHistory: Decodable, Equatable {
        /// Which gameweek these picks are for.
        var event: Int? = nil
        var points: Int? = nil
        var pointsOnBench: Int? = nil
    }
}

/// A team's points in one gameweek.
struct GameweekPoints: Equatable {
    let gameweek: Int
    let points: Int
    var bench: Int? = nil
    /// The live sum, which can still move. False for FPL's numbers.
    let isLive: Bool
}

extension ManagerPicks {
    /// Each pick's live points times his multiplier, and the bench's (multiplier 0)
    /// own points. Unknown points count 0. Nil if a pick has no multiplier.
    func liveTotals(_ live: LivePoints) -> (points: Int, bench: Int)? {
        var points = 0, bench = 0
        for pick in picks {
            guard let multiplier = pick.multiplier else { return nil }
            let own = live.points[pick.element] ?? 0
            if multiplier == 0 { bench += own } else { points += own * multiplier }
        }
        return (points, bench)
    }

    /// The live sum until FPL confirms the gameweek, then FPL's numbers, which lag
    /// during matches. FPL's too without live points or the picks' `event`.
    func gameweekPoints(live: LivePoints?, event: Event?) -> GameweekPoints? {
        guard let gameweek = entryHistory?.event else { return nil }
        if let live, live.gameweek == gameweek, let event, event.id == gameweek, !event.isConfirmed,
           let totals = liveTotals(live) {
            return GameweekPoints(gameweek: gameweek, points: totals.points, bench: totals.bench, isLive: true)
        }
        guard let points = entryHistory?.points else { return nil }
        return GameweekPoints(gameweek: gameweek, points: points, bench: entryHistory?.pointsOnBench, isLive: false)
    }
}

/// One player's gameweek from `GET /api/events/{gw}/live`. Nulls mean unknown, not 0.
struct LiveElement: Decodable, Equatable {
    /// `Element.id`.
    let id: Int
    /// Summed across both matches in a double gameweek.
    var totalPoints: Int? = nil
    var minutes: Int? = nil
}

/// Each player's points in the squad's gameweek, for the squad's cards.
struct LivePoints: Equatable {
    let gameweek: Int
    /// By `Element.id`. Players FPL sent null for are missing (unknown).
    let points: [Int: Int]
    let minutes: [Int: Int]
    /// Teams with a match this gameweek that hasn't kicked off. Nil when
    /// fixtures couldn't load, so nobody shows as yet to play.
    let teamsYetToPlay: Set<Int>?

    /// - Parameter fixtures: Matches not started yet (`/fixtures?started=false`), or nil if they failed.
    init(gameweek: Int, elements: [LiveElement], fixtures: [Fixture]?) {
        self.gameweek = gameweek
        points = Dictionary(elements.compactMap { e in e.totalPoints.map { (e.id, $0) } }, uniquingKeysWith: { a, _ in a })
        minutes = Dictionary(elements.compactMap { e in e.minutes.map { (e.id, $0) } }, uniquingKeysWith: { a, _ in a })
        teamsYetToPlay = fixtures.map { fixtures in
            Set(fixtures.filter { $0.event == gameweek && !$0.started }.flatMap { [$0.teamH, $0.teamA] })
        }
    }

    /// What a pick's card shows. `team` is the player's `Element.team`.
    ///
    /// "Yet to play" when his team still has a match this gameweek and he has no
    /// minutes: FPL's 0 minutes looks the same before and after a match. In a
    /// double where he played the first match, his points so far show instead.
    func score(for pick: ManagerPicks.Pick, team: Int?) -> PickScore? {
        if let team, teamsYetToPlay?.contains(team) == true, (minutes[pick.element] ?? 0) == 0 {
            return .yetToPlay
        }
        return pick.points(from: points[pick.element]).map(PickScore.points)
    }
}

/// A squad card's points: as they count for the team (captain doubled), or "–".
enum PickScore: Equatable {
    case points(Int)
    case yetToPlay

    /// "12" or "–"
    var text: String {
        switch self {
        case .points(let points): "\(points)"
        case .yetToPlay: "–"
        }
    }

    /// "12 points" or "yet to play"
    var accessibilityDescription: String {
        switch self {
        case .points(let points): points == 1 ? "1 point" : "\(points) points"
        case .yetToPlay: "yet to play"
        }
    }
}
