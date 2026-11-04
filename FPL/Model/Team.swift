//
//  Team.swift
//  FPL
//

import Foundation

/// A Premier League team from `GET /api/teams`. Only the fields the app uses are decoded.
struct Team: Codable, Identifiable, Hashable {
    /// FPL team id (1–20), matching `Element.team`.
    let id: Int
    /// e.g. "Arsenal"
    let name: String
    /// e.g. "ARS"
    let shortName: String
    /// Traditional home colors as "#RRGGBB", not exact kit shades. Nil for a
    /// club the backend doesn't know yet.
    var primaryColor: String? = nil
    var secondaryColor: String? = nil
}
