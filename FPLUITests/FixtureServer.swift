//
//  FixtureServer.swift
//  FPLUITests
//

import Foundation
import Network

/// A local HTTP server that answers fplAPI routes with the contract fixtures, so
/// UI tests run against fixed data. The app reaches it through `-FPLAPIBaseURL`.
final class FixtureServer: @unchecked Sendable {
    /// Read from the source tree: simulator processes can read the Mac's files.
    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("FPLTests/Fixtures")

    /// Path patterns under `/api`, in order, and the fixture each one gets.
    private static let routes: [(pattern: String, fixture: String)] = [
        (#"^/api/elements$"#, "elements"),
        (#"^/api/elements/position/\d$"#, "elements-position"),
        (#"^/api/elements/\d+$"#, "element"),
        (#"^/api/teams$"#, "teams"),
        (#"^/api/fixtures$"#, "fixtures"),
        (#"^/api/events$"#, "events"),
        (#"^/api/events/\d+/live$"#, "live"),
        (#"^/api/managers/\d+$"#, "manager"),
        (#"^/api/managers/\d+/transfers$"#, "transfers"),
        (#"^/api/managers/\d+/history$"#, "history"),
        (#"^/api/managers/\d+/picks$"#, "picks"),
        (#"^/api/leagues/\d+$"#, "league"),
    ]

    private let listener: NWListener
    private let queue = DispatchQueue(label: "FixtureServer")

    init() throws {
        let parameters = NWParameters.tcp
        // Loopback only: nothing off this Mac needs to reach it.
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
    }

    /// Starts listening on a free port and returns the base URL to pass the app.
    func start() throws -> URL {
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed, .cancelled: ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, let port = listener.port?.rawValue else {
            throw URLError(.cannotConnectToHost)
        }
        return URL(string: "http://127.0.0.1:\(port)/api")!
    }

    func stop() {
        listener.cancel()
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, _ in
            // "GET /api/teams?x=1 HTTP/1.1": the path, without the query.
            let requestLine = data.flatMap { String(data: $0, encoding: .utf8) }?.split(separator: " ")
            let target = requestLine.map { $0.count > 1 ? String($0[1]) : "/" } ?? "/"
            let path = String(target.split(separator: "?").first ?? "")
            let (status, body) = Self.response(for: path)
            let head = """
                HTTP/1.1 \(status) \(status == 200 ? "OK" : "Not Found")\r
                Content-Type: application/json\r
                Content-Length: \(body.count)\r
                Connection: close\r
                \r

                """
            connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private static func response(for path: String) -> (status: Int, body: Data) {
        let route = routes.first { path.range(of: $0.pattern, options: .regularExpression) != nil }
        guard let route,
              let body = try? Data(contentsOf: fixtures.appendingPathComponent("\(route.fixture).json")) else {
            return (404, Data(#"{"detail": "Not found"}"#.utf8))
        }
        return (200, body)
    }
}
