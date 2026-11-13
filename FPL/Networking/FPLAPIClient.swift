//
//  FPLAPIClient.swift
//  FPL
//

import Foundation
import OSLog

/// The notes routes, a protocol so `NoteSync` tests can stand in for the server.
protocol NotesAPI: Sendable {
    func notes(since cursor: String?, accessToken: String) async throws -> NotesPage
    func putNote(_ note: NoteBody, id: UUID, accessToken: String) async throws -> RemoteNote
}

/// The account's teams and the team lookup, a protocol so `TeamSync` tests can
/// stand in for the server.
protocol TeamsAPI: Sendable {
    func myTeams(accessToken: String) async throws -> [AccountTeam]
    func putTeam(id: Int, relation: AccountTeam.Relation, accessToken: String) async throws -> AccountTeam
    func deleteTeam(id: Int, accessToken: String) async throws
    func manager(id: Int) async throws -> Manager
}

/// Client for the fplAPI backend, all routes under `/api`.
struct FPLAPIClient: NotesAPI, TeamsAPI {
    /// From the `FPL_API_BASE_URL` build setting (via `FPLAPIBaseURL` in Info.plist),
    /// or in Debug the `-FPLAPIBaseURL` launch argument. A local backend is `http://127.0.0.1:5000/api`.
    var baseURL: URL = Self.configuredBaseURL

    static let productionBaseURL = URL(string: "https://fpl-api-six.vercel.app/api")!

    /// Falls back to production if the setting is missing or isn't a URL.
    static var configuredBaseURL: URL {
        LaunchOptions.baseURLOverride ?? (Bundle.main.object(forInfoDictionaryKey: "FPLAPIBaseURL") as? String)
            .flatMap { $0.isEmpty ? nil : URL(string: $0) } ?? productionBaseURL
    }
    var session: URLSession = .shared

    enum APIError: LocalizedError {
        case notFound(String)
        /// 401 from an account route: no token, or an invalid or expired one.
        case unauthorized(String)
        case dataUnavailable(String)
        case http(status: Int, detail: String?)
        case invalidResponse
        case decoding(Error)

        var errorDescription: String? {
            switch self {
            case .notFound(let detail), .unauthorized(let detail):
                return detail
            case .dataUnavailable(let detail):
                return detail
            case .http(let status, let detail):
                return detail ?? "Server returned status \(status)"
            case .invalidResponse:
                return "Invalid response from server"
            case .decoding(let error):
                return "Error decoding response: \(error.localizedDescription)"
            }
        }
    }

    /// `GET /api/elements`
    func elements() async throws -> [Element] {
        try await get("elements")
    }

    /// `GET /api/elements/{id}`
    func element(id: Int) async throws -> Element {
        try await get("elements/\(id)")
    }

    /// `GET /api/elements/position/{element_type}`. A 404 (no players) is returned as `[]`.
    func elements(position: Element.Position) async throws -> [Element] {
        do {
            return try await get("elements/position/\(position.rawValue)")
        } catch APIError.notFound {
            return []
        }
    }

    /// `GET /api/teams`
    func teams() async throws -> [Team] {
        try await get("teams")
    }

    /// `GET /api/fixtures?started=false`: matches still to be played, ordered by kickoff.
    func upcomingFixtures() async throws -> [Fixture] {
        try await get("fixtures", query: [URLQueryItem(name: "started", value: "false")])
    }

    /// `GET /api/managers/{id}`: an FPL manager's team. 404 when no team has that ID;
    /// 503 when FPL is down or updating.
    func manager(id: Int) async throws -> Manager {
        try await get("managers/\(id)")
    }

    /// `GET /api/managers/{id}/transfers`: the manager's transfers this season,
    /// newest first, without churn (swaps undone while planning a chip week).
    func transfers(managerID: Int) async throws -> [Transfer] {
        let rows: [Transfer] = try await get("managers/\(managerID)/transfers")
        return rows.filter { $0.isChurn != true }
    }

    /// `GET /api/managers/{id}/history`: points per gameweek and chips used this season.
    func history(managerID: Int) async throws -> ManagerHistory {
        try await get("managers/\(managerID)/history")
    }

    /// `GET /api/managers/{id}/picks?event={gw}`: the squad as of the latest deadline,
    /// or for `gameweek`. 404 before the manager's first deadline or for a gameweek
    /// before they joined; 503 when FPL is down or updating.
    func picks(managerID: Int, gameweek: Int? = nil) async throws -> ManagerPicks {
        try await get("managers/\(managerID)/picks",
                      query: gameweek.map { [URLQueryItem(name: "event", value: "\($0)")] } ?? [])
    }

    /// `GET /api/events/{gw}/live`: every player's points and minutes in a gameweek,
    /// summed across both matches in a double. Empty before the gameweek starts.
    func livePoints(gameweek: Int) async throws -> [LiveElement] {
        try await get("events/\(gameweek)/live")
    }

    /// `GET /api/events/{gw}/fixtures`: a gameweek's matches by kickoff, live from FPL,
    /// with scores and minutes during play. 404 for a gameweek FPL has no matches for;
    /// 503 when FPL is down with no saved copy.
    func fixtures(gameweek: Int) async throws -> [Fixture] {
        try await get("events/\(gameweek)/fixtures")
    }

    /// `GET /api/leagues/{id}?page=`: a classic league's standings, 50 teams a page.
    /// 404 for an unknown or head-to-head league; 503 when FPL is down or updating.
    func league(id: Int, page: Int = 1) async throws -> LeagueStandings {
        try await get("leagues/\(id)", query: [URLQueryItem(name: "page", value: "\(page)")])
    }

    /// `GET /api/events`: every gameweek of the season.
    func events() async throws -> [Event] {
        try await get("events")
    }

    /// `GET /api/me`: the signed-in user's account, created on the first call.
    /// 401 when the token is rejected, 503 when sign-in is unavailable.
    func me(accessToken: String) async throws -> Account {
        try await get("me", accessToken: accessToken)
    }

    /// `DELETE /api/me`: deletes the account, its synced notes and its teams. 204,
    /// also when it's already gone; 503 when nothing could be deleted.
    func deleteMe(accessToken: String) async throws {
        _ = try await data("DELETE", "me", accessToken: accessToken)
    }

    /// `GET /api/me/teams`: the account's FPL teams, newest first.
    func myTeams(accessToken: String) async throws -> [AccountTeam] {
        try await get("me/teams", accessToken: accessToken)
    }

    /// `PUT /api/me/teams/{id}`: adds a team or switches its relation. 404 for a team
    /// FPL doesn't have, 409 at the account's 10 teams, 503 when FPL is down.
    func putTeam(id: Int, relation: AccountTeam.Relation, accessToken: String) async throws -> AccountTeam {
        try await send("PUT", "me/teams/\(id)", body: JSONEncoder.fplAPI.encode(TeamRequest(relation: relation)),
                       accessToken: accessToken)
    }

    /// `DELETE /api/me/teams/{id}`: 204, also when it wasn't on the account.
    func deleteTeam(id: Int, accessToken: String) async throws {
        _ = try await data("DELETE", "me/teams/\(id)", accessToken: accessToken)
    }

    /// `GET /api/me/notes?since={cursor}`: the signed-in user's notes changed since
    /// the cursor, oldest first, deletions included. 422 for a cursor it didn't issue.
    func notes(since cursor: String?, accessToken: String) async throws -> NotesPage {
        try await send("GET", "me/notes", query: cursor.map { [URLQueryItem(name: "since", value: $0)] } ?? [],
                       accessToken: accessToken)
    }

    /// `PUT /api/me/notes/{id}`: creates, updates or deletes a note, unless the stored
    /// one is as new or newer. Returns the stored note either way. 404 if the id is
    /// someone else's, 422 for a note the API won't take.
    func putNote(_ note: NoteBody, id: UUID, accessToken: String) async throws -> RemoteNote {
        try await send("PUT", "me/notes/\(id.uuidString.lowercased())", body: JSONEncoder.fplAPI.encode(note),
                       accessToken: accessToken)
    }

    /// Account routes are `me` and everything under it. Only they get the token:
    /// FPL routes ignore it, and it shouldn't travel where it isn't needed.
    static func isAccountRoute(_ path: String) -> Bool {
        path == "me" || path.hasPrefix("me/")
    }

    func request(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil,
                 accessToken: String? = nil) -> URLRequest {
        var url = baseURL.appendingPathComponent(path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let accessToken, Self.isAccountRoute(path) {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    // MARK: - Private

    private struct ErrorBody: Decodable {
        let detail: String
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [],
                                   accessToken: String? = nil) async throws -> T {
        try await send("GET", path, query: query, accessToken: accessToken)
    }

    private func send<T: Decodable>(_ method: String, _ path: String, query: [URLQueryItem] = [],
                                    body: Data? = nil, accessToken: String? = nil) async throws -> T {
        let data = try await data(method, path, query: query, body: body, accessToken: accessToken)
        do {
            return try JSONDecoder.fplAPI.decode(T.self, from: data)
        } catch {
            Logger.network.error("""
                Couldn't decode \(String(describing: T.self), privacy: .public) from \
                \(method, privacy: .public) \(Self.route(path), privacy: .public): \(error.logSummary, privacy: .public)
                """)
            throw APIError.decoding(error)
        }
    }

    /// Sends the request and returns the body of a 2xx response; other statuses throw `APIError`.
    private func data(_ method: String, _ path: String, query: [URLQueryItem] = [],
                      body: Data? = nil, accessToken: String? = nil) async throws -> Data {
        let route = "\(method) \(Self.route(path))"

        let data: Data
        let response: URLResponse
        var shared = false
        do {
            let request = request(path, method: method, query: query, body: body, accessToken: accessToken)
            // Stores that load the same list at the same moment share one request. Only these
            // lists: a shared request isn't cancelled with its caller, and these are the ones
            // that duplicate at launch.
            if method == "GET", InFlightRequests.sharedPaths.contains(path) {
                let answer = try await InFlightRequests.shared.data(for: request, session: session)
                (data, response, shared) = (answer.data, answer.response, answer.shared)
            } else {
                (data, response) = try await session.data(for: request)
            }
        } catch {
            if (error as? URLError)?.code == .cancelled || error is CancellationError {
                Logger.network.debug("\(route, privacy: .public) cancelled")
            } else {
                Logger.network.error("\(route, privacy: .public) failed: \(error.logSummary, privacy: .public) \(error)")
            }
            throw error
        }

        guard let http = response as? HTTPURLResponse else {
            Logger.network.fault("\(route, privacy: .public) returned a response that isn't HTTP")
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let detail = try? JSONDecoder().decode(ErrorBody.self, from: data).detail
            // A 404 is an expected answer here (no team with that ID, no squad yet), and
            // a 401 is handled by refreshing the session.
            let level: OSLogType = switch http.statusCode {
            case 404: .info
            case 401: .default
            default: .error
            }
            Logger.network.log(level: level,
                               "\(route, privacy: .public) returned \(http.statusCode): \(detail ?? "no detail", privacy: .public)")
            switch http.statusCode {
            case 401: throw APIError.unauthorized(detail ?? "Not signed in")
            case 404: throw APIError.notFound(detail ?? "Not found")
            case 503: throw APIError.dataUnavailable(detail ?? "FPL data is currently unavailable")
            default: throw APIError.http(status: http.statusCode, detail: detail)
            }
        }

        // "shared": another caller's request, so it isn't counted as a request of its own.
        Logger.network.debug("\(route, privacy: .public) \(http.statusCode), \(data.count) bytes\(shared ? " (shared)" : "")")
        return data
    }

    /// The path with manager, league and note IDs taken out, so it can be logged as public.
    static func route(_ path: String) -> String {
        path.replacingOccurrences(of: #"managers/\d+"#, with: "managers/{id}", options: .regularExpression)
            .replacingOccurrences(of: #"notes/[0-9a-fA-F-]{36}"#, with: "notes/{id}", options: .regularExpression)
            .replacingOccurrences(of: #"teams/\d+"#, with: "teams/{id}", options: .regularExpression)
            .replacingOccurrences(of: #"leagues/\d+"#, with: "leagues/{id}", options: .regularExpression)
    }
}

/// Identical GET requests in flight at the same time share one network request.
/// One made after the first finishes goes out again, so a refresh is always fresh.
actor InFlightRequests {
    static let shared = InFlightRequests()
    /// The routes that share; no account route is among them.
    static let sharedPaths: Set<String> = ["teams", "events", "fixtures", "elements"]

    /// Per session too, so clients on different sessions (tests' stubs) never share.
    private struct Key: Hashable {
        let url: URL
        let session: ObjectIdentifier
    }

    private var running: [Key: Task<(Data, URLResponse), Error>] = [:]

    struct Answer {
        let data: Data
        let response: URLResponse
        /// True when another caller's request answered this one.
        let shared: Bool
    }

    func data(for request: URLRequest, session: URLSession) async throws -> Answer {
        guard let url = request.url else {
            let (data, response) = try await session.data(for: request)
            return Answer(data: data, response: response, shared: false)
        }
        let key = Key(url: url, session: ObjectIdentifier(session))
        if let task = running[key] {
            let (data, response) = try await task.value
            return Answer(data: data, response: response, shared: true)
        }
        let task = Task { try await session.data(for: request) }
        running[key] = task
        defer { running[key] = nil }
        let (data, response) = try await task.value
        return Answer(data: data, response: response, shared: false)
    }
}
