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
        let server = try FixtureServer(overrides: name.contains("testALiveGameweek") ? Fixtures.liveGameweek() : [:])
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

    /// With the gameweek unconfirmed and FPL's numbers behind, every screen shows
    /// the sum of the cards, marked live.
    @MainActor
    func testALiveGameweek() throws {
        let squad = try Fixtures.squad()
        let live = try Fixtures.liveSum()
        try linkManager1()

        let header = element(labelled: "Gameweek \(squad.gameweek) · \(live.points) pts")
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertTrue(header.label.contains("live"), header.label)
        XCTAssertTrue(header.label.contains("\(live.bench) pts on the bench"), header.label)

        let stat = element(labelled: "GW\(squad.gameweek) points")
        XCTAssertTrue(stat.label.contains("\(live.points)") && stat.label.contains("live"), stat.label)

        app.buttons["Notes"].firstMatch.tap()
        XCTAssertTrue(element(labelled: "\(live.points) points, live").waitForExistence(timeout: 10))
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
    func testWritingANote() throws {
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
    }

    /// The first element whose label contains `text`: cards combine their texts into one label.
    @MainActor
    private func element(labelled text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Profile, type 1, Find team, check it's the fixture's team, then confirm.
    @MainActor
    private func linkManager1() throws {
        let teamName = try Fixtures.teamName()
        app.buttons["Profile"].firstMatch.tap()
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

    /// The gameweek Notes treats as current: `is_current`, or `is_next` before the season.
    static func currentGameweek() throws -> Int {
        let events = try array("events")
        let event = events.first { $0["is_current"] as? Bool == true } ?? events.first { $0["is_next"] as? Bool == true }
        return try XCTUnwrap(event?["id"] as? Int)
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

    /// Live points times multiplier, and the bench's own.
    static func liveSum() throws -> (points: Int, bench: Int) {
        let live = Dictionary(try array("live").compactMap { row in
            (row["id"] as? Int).map { ($0, row["total_points"] as? Int ?? 0) }
        }, uniquingKeysWith: { first, _ in first })
        var points = 0, bench = 0
        for pick in try XCTUnwrap(object("picks")["picks"] as? [[String: Any]]) {
            let own = live[try XCTUnwrap(pick["element"] as? Int)] ?? 0
            let multiplier = try XCTUnwrap(pick["multiplier"] as? Int)
            if multiplier == 0 { bench += own } else { points += own * multiplier }
        }
        return (points, bench)
    }

    /// The squad's gameweek unconfirmed, and the manager, picks and history each
    /// behind the live points by a different amount.
    static func liveGameweek() throws -> [String: Data] {
        let gameweek = try squad().gameweek
        let events = try array("events").map { event -> [String: Any] in
            guard event["id"] as? Int == gameweek else { return event }
            return event.merging(["finished": false, "data_checked": false]) { $1 }
        }

        var manager = try object("manager")
        manager["summary_event_points"] = try liveSum().points - 12

        var picks = try object("picks")
        var entry = try XCTUnwrap(picks["entry_history"] as? [String: Any])
        entry["points"] = try liveSum().points - 7
        entry["points_on_bench"] = try liveSum().bench + 5
        picks["entry_history"] = entry

        var history = try object("history")
        history["current"] = try XCTUnwrap(history["current"] as? [[String: Any]]).map { row -> [String: Any] in
            guard row["event"] as? Int == gameweek else { return row }
            return row.merging(["points": try liveSum().points - 3]) { $1 }
        }

        return try ["events": events, "manager": manager, "picks": picks, "history": history]
            .mapValues { try JSONSerialization.data(withJSONObject: $0) }
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
