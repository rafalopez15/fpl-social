//
//  FPLUITests.swift
//  FPLUITests
//

import XCTest

/// The key flows, against `FixtureServer` (manager 1, Gameweek 9) and starting
/// with no linked team and no notes.
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
    func testLinkingATeam() {
        linkManager1()
        XCTAssertTrue(app.buttons["Team options"].exists)
    }

    @MainActor
    func testViewingTheSquad() {
        linkManager1()
        XCTAssertTrue(element(labelled: "Gameweek 9 · 57 pts").waitForExistence(timeout: 10))
        XCTAssertTrue(element(labelled: "Haaland, ").waitForExistence(timeout: 10))
    }

    @MainActor
    func testWritingANote() {
        app.buttons["Notes"].firstMatch.tap()
        let add = app.buttons["Add note to Gameweek 9"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()

        let editor = app.textViews["Note"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("Haaland captain for the double")
        app.buttons["Save"].tap()

        let row = app.staticTexts["Haaland captain for the double"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    /// The first element whose label contains `text`: cards combine their texts into one label.
    @MainActor
    private func element(labelled text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Profile, type 1, Find team, then confirm.
    @MainActor
    private func linkManager1() {
        app.buttons["Profile"].firstMatch.tap()
        let field = app.textFields["Manager ID"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("1")
        app.buttons["Find team"].tap()

        let link = app.buttons["Link team"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        XCTAssertTrue(element(labelled: "Solio Moose").exists)
        link.tap()
        XCTAssertTrue(app.buttons["Team options"].waitForExistence(timeout: 10))
    }
}
