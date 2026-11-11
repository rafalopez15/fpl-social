//
//  League.swift
//  FPL
//

import Foundation

/// One of a team's classic leagues, from `leagues` on `GET /api/managers/{id}`.
/// The API sends invitational leagues first, then FPL's own, each smallest first.
struct ManagerLeague: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        /// Created by a person: friends, work, a podcast.
        case invitational
        /// FPL's own: Overall, a country, a club, "Second Chance".
        case system
        case unknown

        init(from decoder: Decoder) throws {
            self = Kind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    let id: Int
    let name: String
    let kind: Kind
    /// How many teams it has.
    let size: Int?
    /// This team's rank; 0 until FPL first ranks a team that just joined.
    let rank: Int?
    /// The rank after the gameweek before; 0 for a team that just joined.
    let lastRank: Int?

    /// Positive when the team moved up.
    var rankChange: Int? { LeagueRank.change(rank: rank, lastRank: lastRank) }
}

/// A page of a classic league's standings, from `GET /api/leagues/{id}?page=`.
struct LeagueStandings: Codable {
    let id: Int
    let name: String
    /// When FPL last updated the standings.
    let lastUpdated: Date?
    let page: Int
    let hasNext: Bool
    let standings: [LeagueStanding]
    /// Teams that joined this gameweek, which FPL only ranks after its next update.
    /// The same on every page.
    let newEntries: [LeagueNewEntry]?
    let newEntriesHasNext: Bool?
}

/// A team in the standings. Only the team's name: the API never sends a person's.
struct LeagueStanding: Codable, Identifiable, Hashable {
    /// The team's manager ID.
    let entry: Int
    let entryName: String
    let rank: Int?
    let lastRank: Int?
    let total: Int?
    let eventTotal: Int?

    var id: Int { entry }
    var rankChange: Int? { LeagueRank.change(rank: rank, lastRank: lastRank) }
}

struct LeagueNewEntry: Codable, Identifiable, Hashable {
    let entry: Int
    let entryName: String

    var id: Int { entry }
}

/// How ranks read in leagues, which run from 2 teams to over 11 million.
enum LeagueRank {
    /// Nil when either rank is missing or 0, which FPL uses for "not ranked yet".
    static func change(rank: Int?, lastRank: Int?) -> Int? {
        guard let rank, let lastRank, rank > 0, lastRank > 0 else { return nil }
        return lastRank - rank
    }

    /// "3 of 23", or in a large league "1.86M of 11.2M". Nil until the team is ranked.
    static func text(rank: Int?, size: Int?) -> String? {
        guard let rank, rank > 0 else { return nil }
        guard let size, size > 0 else { return number(rank) }
        return "\(number(rank)) of \(number(size))"
    }

    /// Exact up to 99,999; after that, "338K" or "11.2M".
    static func number(_ value: Int) -> String {
        value < 100_000 ? value.formatted() : GameweekScore.compact(value)
    }

    /// Under a league cut off at its top teams: "Showing the top 50 of 11.2M teams".
    static func capNote(shown: Int, size: Int?) -> String {
        guard let size, size > shown else { return "Showing the top \(shown) teams" }
        return "Showing the top \(shown) of \(number(size)) teams"
    }

    /// For VoiceOver: "Rank 3 of 23, up 2 places".
    static func accessibilityText(rank: Int?, size: Int?, change: Int?) -> String {
        guard let rank, rank > 0 else { return "Not ranked yet" }
        var text = "Rank \(rank.formatted())"
        if let size, size > 0 { text += " of \(size.formatted())" }
        if let change, change != 0 {
            let places = abs(change) == 1 ? "place" : "places"
            text += ", \(change > 0 ? "up" : "down") \(abs(change).formatted()) \(places)"
        }
        return text
    }
}
