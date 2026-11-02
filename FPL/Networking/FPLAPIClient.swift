//
//  FPLAPIClient.swift
//  FPL
//

import Foundation

/// Client for the fplAPI backend, all routes under `/api`.
struct FPLAPIClient {
    /// Production fplAPI on Vercel. For a local backend, use `http://127.0.0.1:5000/api`.
    var baseURL: URL = URL(string: "https://fpl-api-six.vercel.app/api")!
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
        let (data, response) = try await session.data(from: url)

        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        guard (200..<300).contains(http.statusCode) else {
            let detail = try? JSONDecoder().decode(ErrorBody.self, from: data).detail
            switch http.statusCode {
            case 404: throw APIError.notFound(detail ?? "Not found")
            case 503: throw APIError.dataUnavailable(detail ?? "FPL data is currently unavailable")
            default: throw APIError.http(status: http.statusCode, detail: detail)
            }
        }

        do {
            return try JSONDecoder.fplAPI.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}
