//
//  AccountTeam.swift
//  FPL
//

import Foundation

/// An FPL team on the signed-in account, from `GET /api/me/teams`.
struct AccountTeam: Codable, Equatable, Identifiable {
    enum Relation: String, Codable {
        /// A team you run; people often run several.
        case mine
        /// Anyone else's team. Its manager needn't have an account.
        case following
    }

    let managerId: Int
    let relation: Relation
    let createdAt: Date
    /// The team's name (never the manager's). Nil for teams added before the API sent it,
    /// until its hourly sync fills them in, or from an API without the field.
    var name: String?

    var id: Int { managerId }
}

/// The body of `PUT /api/me/teams/{id}`.
struct TeamRequest: Encodable {
    let relation: AccountTeam.Relation
}

/// Why a change to the account's teams failed, worded for Profile.
enum TeamError: Error, Equatable {
    /// 404, or 422 for an ID too big for the API: FPL has no such team.
    case notFound
    /// 409: the account's 1,000 teams, yours and followed ones together.
    case limitReached
    /// 429: 60 new teams within an hour, a limit meant for scripts.
    case tooManyAdds
    /// Following a team that's one of yours; the API would make it a followed team.
    case alreadyYours
    /// 503: FPL is down, and adding a team checks it there.
    case fplUnavailable
    case connection
    /// The session was rejected; the account card says so.
    case signedOut
    case unknown

    init(_ error: Error) {
        switch error {
        case let error as TeamError: self = error
        case FPLAPIClient.APIError.notFound, FPLAPIClient.APIError.http(status: 422, detail: _): self = .notFound
        case FPLAPIClient.APIError.http(status: 409, detail: _): self = .limitReached
        case FPLAPIClient.APIError.http(status: 429, detail: _): self = .tooManyAdds
        case FPLAPIClient.APIError.dataUnavailable: self = .fplUnavailable
        case SignInError.signedOut: self = .signedOut
        case SignInError.connection, is URLError: self = .connection
        default: self = .unknown
        }
    }

    var message: String {
        switch self {
        case .notFound: "No FPL team with that ID. Check the number and try again."
        case .limitReached: "You've reached the limit of 1,000 teams."
        case .tooManyAdds: "You've added a lot of teams in the last hour. Try again later."
        case .alreadyYours: "That's one of your teams."
        case .fplUnavailable: "FPL is down or updating, which is common around gameweek deadlines. Try again in a few minutes."
        case .connection: "Couldn't connect. Check your connection and try again."
        case .signedOut: "You were signed out. Sign in again."
        case .unknown: "Something went wrong. Try again."
        }
    }
}
