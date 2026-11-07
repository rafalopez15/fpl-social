//
//  LaunchOptions.swift
//  FPL
//

import Foundation

/// Launch arguments the UI tests pass. Debug builds only: Release ignores them.
enum LaunchOptions {
    /// `-uiTesting`: start with no linked team and no notes, and keep nothing.
    static var isUITesting: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uiTesting")
        #else
        false
        #endif
    }

    /// `-FPLAPIBaseURL <url>`: replaces the build setting's base URL.
    static var baseURLOverride: URL? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "FPLAPIBaseURL").flatMap(URL.init(string:))
        #else
        nil
        #endif
    }

    /// Where the linked team and the notes cursor are saved: a suite emptied once
    /// per launch while UI testing.
    static func userDefaults() -> UserDefaults { defaults }

    // UserDefaults is thread-safe, but not marked Sendable.
    nonisolated(unsafe) private static let defaults: UserDefaults = {
        guard isUITesting, let defaults = UserDefaults(suiteName: "uiTesting") else { return .standard }
        defaults.removePersistentDomain(forName: "uiTesting")
        return defaults
    }()
}
