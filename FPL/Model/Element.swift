//
//  Element.swift
//  FPL
//
//  Created by Rafael Lopez on 12/3/24.
//

import Foundation

struct Element: Codable, Identifiable {
    let id: Int
    let elementType: Int
    let eventPoints: Int
    let firstName: String
    let form: String
    let news: String
    let nowCost: Int
    let pointsPerGame: String
    let secondName: String
    let selectedByPercent: String
    let status: String
    let team: Int
    let teamCode: Int
    let totalPoints: Int
    let webName: String
    
    enum CodingKeys: String, CodingKey {
        case id = "id"
        case elementType = "element_type"
        case eventPoints = "event_points"
        case firstName = "first_name"
        case form = "form"
        case news = "news"
        case nowCost = "now_cost"
        case pointsPerGame = "points_per_game"
        case secondName = "second_name"
        case selectedByPercent = "selected_by_percent"
        case status = "status"
        case team = "team"
        case teamCode = "team_code"
        case totalPoints = "total_points"
        case webName = "web_name"
    }
    
    var fullName: String {
        return "\(firstName) \(secondName)"
    }
}
