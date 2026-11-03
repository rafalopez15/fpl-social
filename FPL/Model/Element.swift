//
//  Element.swift
//  FPL
//
//  Created by Rafael Lopez on 12/3/24.
//

import Foundation

/// A player, as returned by the fplAPI `/api/elements` endpoints. FPL calls players "elements".
///
/// Only the first six properties are guaranteed by the API. Everything else may be
/// `null` or missing, so it is optional. Decode with `JSONDecoder.fplAPI`.
struct Element: Codable, Identifiable, Hashable {
    // Always present
    let id: Int
    let webName: String
    let team: Int
    let elementType: Int
    /// Price in tenths of a million: `62` means £6.2m. See `price`.
    let nowCost: Int
    let status: Status

    // Identity
    let code: Int?
    let firstName: String?
    let secondName: String?
    /// FPL team code, not the team id. Use `team` for the id.
    let teamCode: Int?
    /// Image filename only, e.g. `"154561.jpg"`.
    let photo: String?

    // Availability
    /// Empty string means no news.
    let news: String?
    let newsAdded: Date?
    let chanceOfPlayingNextRound: Int?
    let chanceOfPlayingThisRound: Int?
    /// FPL's `can_select`: false for players who can't be picked, e.g. they joined
    /// another club. See `isSelectable`.
    let canSelect: Bool?
    /// FPL's `can_transact`: whether the player can be transferred in or out.
    let canTransact: Bool?
    /// FPL's `removed`: true for players FPL has removed from the game.
    let removed: Bool?

    // Price changes and transfers (costs in tenths of a million)
    let costChangeEvent: Int?
    let costChangeStart: Int?
    let selectedByPercent: Double?
    let transfersInEvent: Int?
    let transfersOutEvent: Int?

    // Points
    let totalPoints: Int?
    let eventPoints: Int?
    let pointsPerGame: Double?
    let form: Double?
    let epNext: Double?

    // Season stats
    let minutes: Int?
    let starts: Int?
    let goalsScored: Int?
    let assists: Int?
    let cleanSheets: Int?
    let goalsConceded: Int?
    let saves: Int?
    let bonus: Int?
    let yellowCards: Int?
    let redCards: Int?

    // Advanced stats
    let expectedGoals: Double?
    let expectedAssists: Double?
    let expectedGoalInvolvements: Double?
    let expectedGoalsConceded: Double?
    let ictIndex: Double?
}

// MARK: - Status

extension Element {
    enum Status: String, Codable, Hashable {
        case available = "a"
        case doubtful = "d"
        case injured = "i"
        case suspended = "s"
        case unavailable = "u"
        case notEligible = "n"
        case unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Status(rawValue: raw) ?? .unknown
        }

        var title: String {
            switch self {
            case .available: "Available"
            case .doubtful: "Doubtful"
            case .injured: "Injured"
            case .suspended: "Suspended"
            case .unavailable: "Unavailable"
            case .notEligible: "Not eligible"
            case .unknown: "Unknown status"
            }
        }
    }
}

// MARK: - Position

extension Element {
    enum Position: Int, CaseIterable {
        case goalkeeper = 1
        case defender = 2
        case midfielder = 3
        case forward = 4

        var title: String {
            switch self {
            case .goalkeeper: "Goalkeepers"
            case .defender: "Defenders"
            case .midfielder: "Midfielders"
            case .forward: "Forwards"
            }
        }

        var singularTitle: String {
            switch self {
            case .goalkeeper: "Goalkeeper"
            case .defender: "Defender"
            case .midfielder: "Midfielder"
            case .forward: "Forward"
            }
        }

        /// FPL's abbreviation, e.g. on the squad's bench.
        var shortTitle: String {
            switch self {
            case .goalkeeper: "GKP"
            case .defender: "DEF"
            case .midfielder: "MID"
            case .forward: "FWD"
            }
        }
    }

    var position: Position? { Position(rawValue: elementType) }
}

// MARK: - Display helpers

extension Element {
    var fullName: String {
        let parts = [firstName, secondName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? webName : parts.joined(separator: " ")
    }

    /// Price in millions, e.g. `6.2`.
    var price: Double { Double(nowCost) / 10 }

    /// `news` with empty strings treated as no news.
    var currentNews: String? {
        guard let news, !news.isEmpty else { return nil }
        return news
    }
}

// MARK: - Availability

extension Element {
    /// How the list flags a player who might not play next round.
    enum AvailabilityFlag: Equatable {
        /// Some chance of playing (25, 50 or 75%). Shown in yellow.
        case doubtful
        /// No chance of playing: injured, suspended, or unknown return date. Shown in red.
        case out
    }

    /// Based on FPL's chance of playing next round: 1–99% is doubtful, 0% is out.
    /// Falls back to the status code when FPL sends no chance.
    var availabilityFlag: AvailabilityFlag? {
        if currentNews?.localizedCaseInsensitiveContains("unknown return date") == true {
            return .out
        }
        if let chance = chanceOfPlayingNextRound {
            switch chance {
            case ..<1: return .out
            case 1..<100: return .doubtful
            default: return nil
            }
        }
        switch status {
        case .available, .unknown: return nil
        case .doubtful: return .doubtful
        case .injured, .suspended, .unavailable, .notEligible: return .out
        }
    }

    /// Short availability text for VoiceOver and the news callout,
    /// e.g. "75% chance of playing" or "Suspended".
    var availabilityDescription: String {
        if let chance = chanceOfPlayingNextRound, chance < 100 {
            return "\(chance)% chance of playing"
        }
        return status.title
    }

    /// Whether the player can be picked in FPL. Players who left the league
    /// (joined another club, released, not in the squad) can't, and are hidden
    /// from the list. Missing fields count as selectable, so a player is only
    /// hidden when FPL says so.
    var isSelectable: Bool {
        canSelect != false && removed != true
    }
}

// MARK: - Decoding

extension JSONDecoder {
    /// Decoder configured for fplAPI responses: snake_case keys and ISO 8601 dates
    /// with fractional seconds (e.g. `news_added`).
    static var fplAPI: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return date }

            // Tolerate timestamps without fractional seconds too.
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) { return date }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO 8601 date: \(string)"
            )
        }
        return decoder
    }
}
