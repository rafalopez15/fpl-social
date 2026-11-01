//
//  ElementFilter.swift
//  FPL
//

import Foundation

/// Range filters applied to the player list. Default values mean "no filter".
struct ElementFilter: Equatable {
    /// Maximum price in millions, e.g. `7.5`. `nil` means no limit.
    var maxPrice: Double? = nil

    var isActive: Bool { self != ElementFilter() }

    func matches(_ element: Element) -> Bool {
        // Small tolerance so £7.5m isn't excluded by a 7.5 limit due to rounding.
        guard let maxPrice else { return true }
        return element.price <= maxPrice + 0.001
    }
}

/// What the player list is sorted by.
enum ElementSort: String, CaseIterable, Identifiable {
    case points, price, goals, assists, selectedBy

    var id: Self { self }

    var title: String {
        switch self {
        case .points: "Points"
        case .price: "Price"
        case .goals: "Goals"
        case .assists: "Assists"
        case .selectedBy: "Selected by"
        }
    }

    func value(for element: Element) -> Double {
        switch self {
        case .points: Double(element.totalPoints ?? 0)
        case .price: element.price
        case .goals: Double(element.goalsScored ?? 0)
        case .assists: Double(element.assists ?? 0)
        case .selectedBy: element.selectedByPercent ?? 0
        }
    }
}
