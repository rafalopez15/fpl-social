//
//  FPLAPIClient.swift
//  FPL
//

import Foundation
import OSLog

/// Client for the fplAPI backend, all routes under `/api`.
struct FPLAPIClient {
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
        case dataUnavailable(String)
        case http(status: Int, detail: String?)
        case invalidResponse
        case decoding(Error)

        var errorDescription: String? {
            switch self {
            case .notFound(let detail):
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

    /// `GET /api/events`: every gameweek of the season.
    func events() async throws -> [Event] {
        try await get("events")
    }

    // MARK: - Private

    private struct ErrorBody: Decodable {
        let detail: String
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var url = baseURL.appendingPathComponent(path)
        if !query.isEmpty { url.append(queryItems: query) }
        let route = Self.route(path)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            if (error as? URLError)?.code == .cancelled || error is CancellationError {
                Logger.network.debug("GET \(route, privacy: .public) cancelled")
            } else {
                Logger.network.error("GET \(route, privacy: .public) failed: \(error.logSummary, privacy: .public) \(error)")
            }
            throw error
        }

        guard let http = response as? HTTPURLResponse else {
            Logger.network.fault("GET \(route, privacy: .public) returned a response that isn't HTTP")
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let detail = try? JSONDecoder().decode(ErrorBody.self, from: data).detail
            // A 404 is an expected answer here (no team with that ID, no squad yet).
            Logger.network.log(level: http.statusCode == 404 ? .info : .error,
                               "GET \(route, privacy: .public) returned \(http.statusCode): \(detail ?? "no detail", privacy: .public)")
            switch http.statusCode {
            case 404: throw APIError.notFound(detail ?? "Not found")
            case 503: throw APIError.dataUnavailable(detail ?? "FPL data is currently unavailable")
            default: throw APIError.http(status: http.statusCode, detail: detail)
            }
        }

        do {
            let value = try JSONDecoder.fplAPI.decode(T.self, from: data)
            Logger.network.debug("GET \(route, privacy: .public) \(http.statusCode), \(data.count) bytes")
            return value
        } catch {
            Logger.network.error("""
                Couldn't decode \(String(describing: T.self), privacy: .public) from GET \(route, privacy: .public): \
                \(error.logSummary, privacy: .public)
                """)
            throw APIError.decoding(error)
        }
    }

    /// The path with the manager ID taken out, so it can be logged as public.
    static func route(_ path: String) -> String {
        path.replacingOccurrences(of: #"managers/\d+"#, with: "managers/{id}", options: .regularExpression)
    }
}
