//
//  NoteSyncTests.swift
//  FPLTests
//

import Foundation
import Testing
@testable import FPL

struct SyncedNoteJSONTests {
    static let created = Date(timeIntervalSince1970: 1_793_000_000.25)
    static let updated = Date(timeIntervalSince1970: 1_793_000_100.5)

    static func json(_ body: NoteBody) throws -> [String: Any] {
        let data = try JSONEncoder.fplAPI.encode(body)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func encodesSnakeCaseAndUTCDates() throws {
        let note = Note(text: "Captain Haaland", gameweek: 10, players: [NotePlayer(id: 7, webName: "Haaland")],
                        createdAt: Self.created)
        note.updatedAt = Self.updated
        let json = try Self.json(NoteBody(note))

        #expect(json["text"] as? String == "Captain Haaland")
        #expect(json["gameweek"] as? Int == 10)
        #expect((json["players"] as? [[String: Any]])?.first?["web_name"] as? String == "Haaland")
        #expect(json["created_at"] as? String == "2026-10-26T07:33:20.250Z")
        #expect(json["updated_at"] as? String == "2026-10-26T07:35:00.500Z")
        // Left out means null to the API.
        #expect(json["deleted_at"] == nil)
        #expect(json["transfer"] == nil)
    }

    @Test func encodesATransferNote() throws {
        let transfer = NoteTransfer(playerIn: NotePlayer(id: 1, webName: "Isak"),
                                    playerOut: NotePlayer(id: 2, webName: "Watkins"),
                                    cost: 86, outCost: 80, time: Self.created)
        let note = Note(text: "", gameweek: 9, transfer: transfer, managerID: 3039435, createdAt: Self.created)
        let json = try Self.json(NoteBody(note))

        #expect(json["manager_id"] as? Int == 3039435)
        let sent = try #require(json["transfer"] as? [String: Any])
        #expect((sent["player_in"] as? [String: Any])?["id"] as? Int == 1)
        #expect((sent["player_out"] as? [String: Any])?["web_name"] as? String == "Watkins")
        #expect(sent["out_cost"] as? Int == 80)
        #expect(sent["time"] as? String == "2026-10-26T07:33:20.250Z")
    }

    @Test func aTombstoneHasNoContent() throws {
        let note = Note(text: "Sell", gameweek: 9, players: [NotePlayer(id: 7, webName: "Haaland")],
                        createdAt: Self.created)
        let json = try Self.json(.tombstone(of: note, at: Self.updated))

        #expect(json["text"] as? String == "")
        #expect((json["players"] as? [Any])?.isEmpty == true)
        #expect(json["deleted_at"] as? String == "2026-10-26T07:35:00.500Z")
        #expect(json["updated_at"] as? String == json["deleted_at"] as? String)
    }

    @Test func decodesAPage() throws {
        let data = Data("""
            {"notes": [
              {"id": "6f9619ff-8b86-d011-b42d-00c04fc964ff", "text": "Hold", "gameweek": 10,
               "players": [{"id": 7, "web_name": "Haaland"}], "transfer": null, "manager_id": null,
               "created_at": "2026-10-26T07:33:20.250000Z", "updated_at": "2026-10-26T07:35:00.500123Z",
               "deleted_at": null},
              {"id": "7f9619ff-8b86-d011-b42d-00c04fc964ff", "text": "", "gameweek": null, "players": [],
               "transfer": null, "manager_id": 1, "created_at": "2026-10-26T07:33:20Z",
               "updated_at": "2026-10-26T07:35:00+00:00", "deleted_at": "2026-10-26T07:35:00+00:00"}
             ],
             "cursor": "abc", "more": false}
            """.utf8)
        let page = try JSONDecoder.fplAPI.decode(NotesPage.self, from: data)

        #expect(page.cursor == "abc")
        #expect(!page.more)
        #expect(page.notes[0].players == [NotePlayer(id: 7, webName: "Haaland")])
        #expect(abs(page.notes[0].updatedAt.timeIntervalSince(Self.updated)) < 0.001)
        #expect(page.notes[0].deletedAt == nil)
        #expect(page.notes[1].deletedAt != nil)
        #expect(page.notes[1].managerId == 1)
    }

    @Test func aStoredBodyRoundTrips() throws {
        let note = Note(text: "Hold", gameweek: 10, createdAt: Self.created)
        let body = NoteBody(note)
        let decoded = try JSONDecoder.fplAPI.decode(NoteBody.self, from: JSONEncoder.fplAPI.encode(body))
        #expect(decoded == body)
    }
}
