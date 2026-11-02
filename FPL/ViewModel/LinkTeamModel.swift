//
//  LinkTeamModel.swift
//  FPL
//

import Foundation

/// The link flow: type a manager ID, look the team up, then confirm it.
@MainActor
final class LinkTeamModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        /// Waiting for the user to confirm it's their team.
        case found(Manager)
        case failed(LinkError)
    }

    /// The text field, digits only.
    @Published var idText = "" {
        didSet {
            let digits = Self.digits(in: idText)
            if digits != idText { idText = digits }
            // Editing the ID after an error or a match starts over.
            if idText != oldValue, state != .loading { state = .idle }
        }
    }
    @Published private(set) var state: State = .idle

    private let client: FPLAPIClient

    init(client: FPLAPIClient = FPLAPIClient()) {
        self.client = client
    }

    /// The ID to look up, or nil while the field is empty or zero.
    var managerID: Int? {
        guard let id = Int(idText), id > 0 else { return nil }
        return id
    }

    func lookUp() async {
        guard let id = managerID else { return }
        state = .loading
        do {
            state = .found(try await client.manager(id: id))
        } catch {
            state = .failed(LinkError(error))
        }
    }

    /// "Not my team": back to the field, keeping the ID so it can be fixed.
    func reject() {
        state = .idle
    }

    /// Digits only, capped at 10 so a pasted URL or stray text can't make it overflow.
    nonisolated static func digits(in text: String) -> String {
        String(text.filter(\.isASCIIDigit).prefix(10))
    }
}

/// Why a lookup failed, worded for the link screen.
enum LinkError: Equatable {
    /// 404: no FPL team has that ID.
    case notFound
    /// 503: FPL is down or updating, common around deadlines.
    case fplUnavailable
    /// No connection or another failure.
    case other

    init(_ error: Error) {
        switch error {
        case FPLAPIClient.APIError.notFound: self = .notFound
        case FPLAPIClient.APIError.dataUnavailable: self = .fplUnavailable
        default: self = .other
        }
    }

    var message: String {
        switch self {
        case .notFound: "No FPL team with that ID. Check the number and try again."
        case .fplUnavailable: "FPL is down or updating, which is common around gameweek deadlines. Try again in a few minutes."
        case .other: "Couldn't reach the server. Check your connection and try again."
        }
    }

    /// A 404 won't change by retrying; the ID needs fixing instead.
    var canRetry: Bool { self != .notFound }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
