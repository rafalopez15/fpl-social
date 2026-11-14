//
//  MentionTests.swift
//  FPLTests
//

import Foundation
import SwiftUI
import Testing
@testable import FPL

/// Linking players with @ in a note: finding what's typed, suggesting, inserting and highlighting.
@MainActor
struct MentionTests {
    static func player(_ id: Int, _ webName: String, first: String = "", second: String = "",
                       points: Int? = 10, canSelect: Bool = true) throws -> Element {
        let points = points.map(String.init) ?? "null"
        let json = """
        {"id": \(id), "web_name": "\(webName)", "first_name": "\(first)", "second_name": "\(second)", "team": 1,
         "element_type": 3, "now_cost": 50, "status": "a", "total_points": \(points), "can_select": \(canSelect)}
        """
        return try JSONDecoder.fplAPI.decode(Element.self, from: Data(json.utf8))
    }

    static func candidates() throws -> [PlayerSuggestions.Candidate] {
        [try player(1, "Saka", first: "Bukayo", second: "Saka", points: 80),
         try player(2, "Ødegaard", first: "Martin", second: "Ødegaard", points: 60),
         try player(3, "Groß", first: "Pascal", second: "Groß", points: 70),
         try player(4, "Sakamoto", points: 5),
         try player(5, "Dewsbury-Hall", first: "Kiernan", second: "Dewsbury-Hall", points: 40),
         try player(6, "Salah", first: "Mohamed", second: "Salah", points: 90)]
            .map(PlayerSuggestions.Candidate.init)
    }

    /// `text` with "|" as the cursor.
    static func query(_ text: String) -> Mention.Query? {
        let cursor = text.firstIndex(of: "|")!
        return Mention.query(in: text.replacingOccurrences(of: "|", with: ""), cursor: cursor)
    }

    // MARK: What's being typed

    @Test func findsTheMentionBeforeTheCursor() {
        #expect(Self.query("Moving @sak|")?.text == "sak")
        #expect(Self.query("@|")?.text == "")
        #expect(Self.query("@Gabriel M|")?.text == "Gabriel M")
        #expect(Self.query("Line one\n@ode| and more")?.text == "ode")
    }

    @Test func ignoresAnythingThatIsntAMention() {
        #expect(Self.query("No mention here|") == nil)
        #expect(Self.query("mail me@example.com|") == nil)
        #expect(Self.query("@saka\nnext line|") == nil)
        #expect(Self.query("@saka is my captain this week, surely|") == nil)
        #expect(Self.query("|@saka") == nil)
    }

    // MARK: Inserting

    @Test func replacesWhatWasTypedWithTheName() throws {
        let text = "Moving @sak"
        let query = try #require(Mention.query(in: text, cursor: text.endIndex))
        let (result, cursor) = Mention.inserting("Saka", for: query, in: text)
        #expect(result == "Moving @Saka ")
        #expect(cursor == result.endIndex)
    }

    @Test func keepsTheTextAfterTheCursorAndOneSpace() throws {
        let text = "Moving @sa out"
        let cursor = try #require(text.range(of: "@sa")?.upperBound)
        let query = try #require(Mention.query(in: text, cursor: cursor))
        let (result, newCursor) = Mention.inserting("Saka", for: query, in: text)
        #expect(result == "Moving @Saka out")
        #expect(result[newCursor...] == "out")
    }

    // MARK: Suggestions

    @Test func suggestsByAnyNameIgnoringCaseAndAccents() throws {
        let all = try Self.candidates()
        func ids(_ query: String) -> [Int] {
            PlayerSuggestions.suggestions(for: query, in: all, squad: [], linked: []).map(\.id)
        }
        #expect(ids("sak") == [1, 4])
        #expect(ids("bukayo") == [1])
        #expect(ids("ode") == [2])
        #expect(ids("gross") == [3])
        #expect(ids("hall") == [5])
        #expect(ids("dewsbury-h") == [5])
        #expect(ids("akayo").isEmpty)
    }

    @Test func putsYourSquadFirstThenPoints() throws {
        let all = try Self.candidates()
        let shown = PlayerSuggestions.suggestions(for: "sa", in: all, squad: [4], linked: [])
        #expect(shown.map(\.id) == [4, 6, 1])
        // Just @: the squad, then the most points, five at most.
        let top = PlayerSuggestions.suggestions(for: "", in: all, squad: [5], linked: [6])
        #expect(top.map(\.id) == [5, 1, 3, 2, 4])
    }

    @Test func leavesOutPlayersWhoLeftTheLeague() async throws {
        let model = PlayerSuggestions { [try Self.player(9, "Gone", canSelect: false), try Self.player(1, "Saka")] }
        await model.loadIfNeeded()
        #expect(model.candidates.map(\.element.id) == [1])
    }

    // MARK: Loading

    @Test func usesProfilesPlayersWhenLoaded() async throws {
        var loads = 0
        let model = PlayerSuggestions { loads += 1; return [] }
        await model.loadIfNeeded(known: [1: try Self.player(1, "Saka")])
        #expect(loads == 0)
        #expect(model.state == .loaded)
        #expect(model.suggestions(for: "sa", squad: [], linked: []).map(\.id) == [1])
    }

    @Test func aFailureWaitsForRetry() async throws {
        var fails = true
        var loads = 0
        let saka = try Self.player(1, "Saka")
        let model = PlayerSuggestions {
            loads += 1
            if fails { throw URLError(.notConnectedToInternet) }
            return [saka]
        }
        await model.loadIfNeeded()
        #expect(model.state == .failed)
        // Typing on doesn't try again; Retry does.
        await model.loadIfNeeded()
        #expect(loads == 1)
        fails = false
        await model.reload()
        #expect(model.state == .loaded)
    }

    @Test func aCancelledLoadTriesAgainNextTime() async {
        let model = PlayerSuggestions { throw CancellationError() }
        await model.loadIfNeeded()
        #expect(model.state == .idle)
    }

    // MARK: Highlighting

    @Test func highlightsOnlyLinkedPlayersWholeNames() {
        let linked = [NotePlayer(id: 1, webName: "Saka"), NotePlayer(id: 7, webName: "Gabriel M."),
                      NotePlayer(id: 8, webName: "Gabriel")]
        let text = "@Saka over @Salah, @Sakas no. @Gabriel M. and @Gabriel."
        let found = Mention.ranges(in: text, linked: linked).map { String(text[$0]) }
        #expect(found == ["@Saka", "@Gabriel M.", "@Gabriel"])
    }

    @Test func highlightingColorsTheMention() throws {
        let attributed = Mention.highlighted("Captain @Saka", linked: [NotePlayer(id: 1, webName: "Saka")])
        let run = try #require(attributed.runs.first { $0.foregroundColor != nil })
        #expect(String(attributed[run.range].characters) == "@Saka")
        #expect(run.inlinePresentationIntent == .stronglyEmphasized)
        #expect(String(attributed.characters) == "Captain @Saka")
    }

    @Test func suggestionsReadNameTeamAndPosition() throws {
        let saka = try Self.player(1, "Saka")
        let arsenal = Team(id: 1, name: "Arsenal", shortName: "ARS")
        #expect(NoteEditorView.description(of: saka, team: arsenal) == "Saka, Arsenal, Midfielder")
        #expect(NoteEditorView.description(of: saka, team: nil) == "Saka, Midfielder")
    }
}
