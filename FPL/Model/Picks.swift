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
