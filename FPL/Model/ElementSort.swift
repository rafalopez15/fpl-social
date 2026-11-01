//
//  ElementSort.swift
//  FPL
//

import Foundation

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
