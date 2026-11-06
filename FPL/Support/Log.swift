//
//  Log.swift
//  FPL
//

import Foundation
import OSLog

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "rafael.lopez.FPL"

    /// Requests to fplAPI: failures, error statuses and decoding errors.
    static let network = Logger(subsystem: subsystem, category: "network")
    /// Saving and deleting notes in SwiftData.
    static let notes = Logger(subsystem: subsystem, category: "notes")
    /// Linking a team and checking it for transfers.
    static let linkedTeam = Logger(subsystem: subsystem, category: "linkedTeam")
    /// Signing in and out, and calls that need an account. Emails are never logged.
    static let account = Logger(subsystem: subsystem, category: "account")
}

extension Error {
    /// Safe to log as public: a decoding error's key path, or the domain and code.
    /// Never a value from the response or the user.
    var logSummary: String {
        if let decoding = self as? DecodingError { return decoding.summary }
        let error = self as NSError
        return "\(error.domain) \(error.code)"
    }
}

extension DecodingError {
    /// What failed and where, e.g. "missing key webName at [3]".
    var summary: String {
        switch self {
        case .keyNotFound(let key, let context):
            return "missing key \(key.stringValue) at \(context.path)"
        case .valueNotFound(let type, let context):
            return "null where \(type) was expected at \(context.path)"
        case .typeMismatch(let type, let context):
            return "expected \(type) at \(context.path): \(context.debugDescription)"
        case .dataCorrupted(let context):
            return "invalid data at \(context.path): \(context.debugDescription)"
        @unknown default:
            return String(describing: self)
        }
    }
}

private extension DecodingError.Context {
    /// "[3].stats.minutes", or "the top level" for an empty path.
    var path: String {
        let path = codingPath.map { key in key.intValue.map { "[\($0)]" } ?? ".\(key.stringValue)" }
            .joined()
        guard !path.isEmpty else { return "the top level" }
        return path.hasPrefix(".") ? String(path.dropFirst()) : path
    }
}
