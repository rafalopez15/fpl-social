//
//  FPLUITests.swift
//  FPLUITests
//

import XCTest

/// The key flows, against `FixtureServer` (manager 1) and starting with no
/// linked team and no notes. Expected values come from the fixtures, so
/// refreshing them doesn't break the tests.
final class FPLUITests: XCTestCase {
    private var server: FixtureServer?
    private var app: XCUIApplication!

    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false
        let server = try FixtureServer()
        let baseURL = try server.start()
        self.server = server
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-FPLAPIBaseURL", baseURL.absoluteString]
        app.launch()
    }

    override func tearDown() {
        server?.stop()
        super.tearDown()
    }

    @MainActor
    func testLinkingATeam() throws {
        try linkManager1()
        XCTAssertTrue(app.buttons["Team options"].exists)
    }

    @MainActor
    func testViewingTheSquad() throws {
        let squad = try Fixtures.squad()
        try linkManager1()
        XCTAssertTrue(element(labelled: "Gameweek \(squad.gameweek) · \(squad.points) pts").waitForExistence(timeout: 10))
        XCTAssertTrue(element(labelled: "\(squad.captain), \(squad.captainTeam)").waitForExistence(timeout: 10))
    }

    @MainActor
    func testViewingALeague() throws {
        let league = try Fixtures.firstLeague()
        let leader = try Fixtures.leagueLeader()
        try linkManager1()

        let card = element(labelled: "Leagues, ")
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        let row = app.buttons[league].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(element(labelled: leader).waitForExistence(timeout: 10))
    }

    @MainActor
    func testOpeningAPlayerFromAllPlayers() throws {
        let player = try Fixtures.topPlayer()
        let allPlayers = app.buttons["All players"]
        XCTAssertTrue(allPlayers.waitForExistence(timeout: 10))
        // The list loads when it's opened, not at launch.
        XCTAssertEqual(playerListRequests, 0)
        allPlayers.tap()
        let info = app.buttons.matching(NSPredicate(format: "label IN %@",
                                                    ["Stats for \(player)", "Stats and news for \(player)"])).firstMatch
        XCTAssertTrue(info.waitForExistence(timeout: 10))
        XCTAssertEqual(playerListRequests, 1)
        XCTAssertTrue(app.searchFields.firstMatch.exists)
        XCTAssertTrue(app.navigationBars.buttons["Profile"].exists)
        info.tap()
        XCTAssertTrue(app.buttons["Add note about \(player)"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testViewingAGameweeksFixtures() throws {
        let gameweek = try Fixtures.openingGameweek()
        let match = try Fixtures.firstMatch()
        app.buttons["Gameweek"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Gameweek \(gameweek)"].waitForExistence(timeout: 10))
        XCTAssertTrue(element(labelled: match).waitForExistence(timeout: 10))

        app.buttons["Next gameweek"].tap()
        XCTAssertTrue(app.buttons["Gameweek \(gameweek + 1)"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(labelled: match).waitForExistence(timeout: 10))

        // The home team's name, in the row's left half, opens its next fixtures.
        element(labelled: match).coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        let sheet = NSPredicate(format: "label BEGINSWITH 'NEXT ' OR label == 'No upcoming fixtures.'")
        XCTAssertTrue(app.staticTexts.matching(sheet).firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testWritingAndDeletingANote() throws {
        let gameweek = try Fixtures.currentGameweek()
        app.buttons["Notes"].firstMatch.tap()
        let add = app.buttons["Add note to Gameweek \(gameweek)"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()

        let editor = app.textViews["Note"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("Captain for the double")
        app.buttons["Save"].tap()

        let row = app.staticTexts["Captain for the double"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        row.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(undo.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testLinkingAPlayerWithAnAtMention() throws {
        let gameweek = try Fixtures.currentGameweek()
        let player = try Fixtures.topPlayer(in: "elements")
        app.buttons["Notes"].firstMatch.tap()
        let add = app.buttons["Add note to Gameweek \(gameweek)"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()

        let editor = app.textViews["Note"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("Bringing in @\(player.prefix(3))")
        let suggestion = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Link \(player), ")).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10))
        suggestion.tap()

        XCTAssertTrue(app.buttons["Unlink \(player)"].waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "Bringing in @\(player) ")
    }

    private var playerListRequests: Int {
        server?.requestedPaths.filter { $0.hasPrefix("/api/elements/position/") }.count ?? 0
    }

    /// The first element whose label contains `text`: cards combine their texts into one label.
    @MainActor
    private func element(labelled text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// On Profile, where the app opens: type 1, Find team, check it's the fixture's team, then confirm.
    @MainActor
    private func linkManager1() throws {
        let teamName = try Fixtures.teamName()
        let field = app.textFields["Manager ID"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("1")
        app.buttons["Find team"].tap()

        let link = app.buttons["Link team"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        XCTAssertTrue(element(labelled: teamName).exists)
        link.tap()
        XCTAssertTrue(app.buttons["Team options"].waitForExistence(timeout: 10))
    }
}

/// What the app should show for the fixtures `FixtureServer` serves.
private enum Fixtures {
    struct Squad {
        let gameweek: Int
        let points: Int
        let captain: String
        let captainTeam: String
    }

    static func teamName() throws -> String {
        try XCTUnwrap(object("manager")["name"] as? String)
    }

    /// The first league on the Leagues page: the API lists them in order.
    static func firstLeague() throws -> String {
        try XCTUnwrap((object("manager")["leagues"] as? [[String: Any]])?.first?["name"] as? String)
    }

    /// The top team in the standings `FixtureServer` sends for every league.
    static func leagueLeader() throws -> String {
        try XCTUnwrap((object("league")["standings"] as? [[String: Any]])?.first?["entry_name"] as? String)
    }

    /// The first row of All players (one position), or with `elements` the first @
    /// suggestion with no team linked (everyone): most points, then by name.
    static func topPlayer(in file: String = "elements-position") throws -> String {
        let players = try array(file)
            .filter { $0["can_select"] as? Bool != false && $0["removed"] as? Bool != true }
            .map { (name: $0["web_name"] as? String ?? "", points: $0["total_points"] as? Int ?? 0) }
        let top = players.min { ($1.points, $0.name) < ($0.points, $1.name) }
        return try XCTUnwrap(top?.name)
    }

    /// The gameweek Notes treats as current: `is_current`, or `is_next` before the season.
    static func currentGameweek() throws -> Int {
        let events = try array("events")
        let event = events.first { $0["is_current"] as? Bool == true } ?? events.first { $0["is_next"] as? Bool == true }
        return try XCTUnwrap(event?["id"] as? Int)
    }

    /// The Gameweek tab opens on the current gameweek, or the next once the served
    /// matches (the same for every gameweek) are all over.
    static func openingGameweek() throws -> Int {
        let matches = try array("event-fixtures").filter { !($0["kickoff_time"] is NSNull) }
        let allPlayed = !matches.isEmpty && matches.allSatisfy {
            $0["finished_provisional"] as? Bool == true || $0["finished"] as? Bool == true
        }
        let next = try array("events").first { $0["is_next"] as? Bool == true }?["id"] as? Int
        let current = try currentGameweek()
        return allPlayed ? next ?? current : current
    }

    /// The start of a match row's label: "Arsenal v Chelsea" before kickoff, "Arsenal 2, Chelsea 1" after.
    static func firstMatch() throws -> String {
        let match = try XCTUnwrap(try array("event-fixtures").first { !($0["kickoff_time"] is NSNull) })
        let teams = try array("teams")
        func name(_ key: String) throws -> String {
            try XCTUnwrap(teams.first { $0["id"] as? Int == match[key] as? Int }?["name"] as? String)
        }
        guard match["started"] as? Bool == true else { return "\(try name("team_h")) v \(try name("team_a"))" }
        return "\(try name("team_h")) \(match["team_h_score"] as? Int ?? 0), \(try name("team_a")) \(match["team_a_score"] as? Int ?? 0)"
    }

    static func squad() throws -> Squad {
        let picks = try object("picks")
        let history = try XCTUnwrap(picks["entry_history"] as? [String: Any])
        let captainID = try XCTUnwrap((picks["picks"] as? [[String: Any]])?
            .first { $0["is_captain"] as? Bool == true }?["element"] as? Int)
        let captain = try XCTUnwrap(try array("elements").first { $0["id"] as? Int == captainID })
        let teamID = try XCTUnwrap(captain["team"] as? Int)
        let team = try XCTUnwrap(try array("teams").first { $0["id"] as? Int == teamID })
        return Squad(gameweek: try XCTUnwrap(history["event"] as? Int),
                     points: try XCTUnwrap(history["points"] as? Int),
                     captain: try XCTUnwrap(captain["web_name"] as? String),
                     captainTeam: try XCTUnwrap(team["name"] as? String))
    }

    private static func json(_ name: String) throws -> Any {
        let data = try Data(contentsOf: FixtureServer.fixtures.appendingPathComponent("\(name).json"))
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func object(_ name: String) throws -> [String: Any] {
        try XCTUnwrap(json(name) as? [String: Any], "\(name).json isn't an object")
    }

    private static func array(_ name: String) throws -> [[String: Any]] {
        try XCTUnwrap(json(name) as? [[String: Any]], "\(name).json isn't an array")
    }
}
