//
//  NoteSyncTests.swift
//  FPLTests
//

import Foundation
import os
import SwiftData
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

/// Stands in for `/api/me/notes`: keeps the newer `updatedAt` per note, like the
/// server, and pages through scripted responses.
final class FakeNotesAPI: NotesAPI, @unchecked Sendable {
    struct State {
        var stored: [UUID: RemoteNote] = [:]
        /// Successful PUTs, in order.
        var puts: [(id: UUID, body: NoteBody)] = []
        var putError: Error?
        /// Each GET returns the next page; `since` values are recorded.
        var pages: [NotesPage] = []
        var sinces: [String?] = []
        /// A cursor the API rejects with 422.
        var rejectedCursor: String?
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())
    var state: State { lock.withLock { $0 } }
    func update(_ change: @Sendable (inout State) -> Void) { lock.withLock { change(&$0) } }

    func notes(since cursor: String?, accessToken: String) async throws -> NotesPage {
        try lock.withLock { state in
            if cursor != nil, cursor == state.rejectedCursor {
                throw FPLAPIClient.APIError.http(status: 422, detail: "Invalid cursor")
            }
            state.sinces.append(cursor)
            return state.pages.isEmpty ? NotesPage(notes: [], cursor: cursor ?? "start", more: false)
                                       : state.pages.removeFirst()
        }
    }

    func putNote(_ note: NoteBody, id: UUID, accessToken: String) async throws -> RemoteNote {
        try lock.withLock { state in
            if let error = state.putError { throw error }
            state.puts.append((id, note))
            if let stored = state.stored[id], stored.updatedAt >= note.updatedAt { return stored }
            let stored = RemoteNote(note, id: id)
            state.stored[id] = stored
            return stored
        }
    }
}

extension RemoteNote {
    init(_ body: NoteBody, id: UUID) {
        self.init(id: id, text: body.text, gameweek: body.gameweek, players: body.players, transfer: body.transfer,
                  managerId: body.managerId, createdAt: body.createdAt, updatedAt: body.updatedAt,
                  deletedAt: body.deletedAt)
    }

    static func note(_ id: UUID, _ text: String, updated: Date, deleted: Bool = false) -> RemoteNote {
        RemoteNote(id: id, text: text, gameweek: 10, players: [], transfer: nil, managerId: nil,
                   createdAt: NoteSyncTests.date(0), updatedAt: updated, deletedAt: deleted ? updated : nil)
    }
}

@MainActor
struct NoteSyncTests {
    let container: ModelContainer
    let context: ModelContext
    let api = FakeNotesAPI()
    let auth = FakeAuth(email: "a@b.co")
    let account: AccountStore
    let defaults: UserDefaults

    init() throws {
        container = try ModelContainer(for: Note.self, PendingNoteWrite.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
        account = AccountStore(auth: auth) { _ in AccountStoreTests.account }
        defaults = try #require(UserDefaults(suiteName: "NoteSyncTests.\(UUID().uuidString)"))
    }

    nonisolated static func date(_ minutes: Double) -> Date {
        Date(timeIntervalSince1970: 1_793_000_000 + minutes * 60)
    }

    func makeSync() -> NoteSync {
        NoteSync(container: container, account: account, api: api, defaults: defaults)
    }

    func notes() throws -> [Note] {
        try context.fetch(FetchDescriptor<Note>())
    }

    /// A note added while signed in, at `minutes`.
    func addNote(_ text: String, at minutes: Double, to sync: NoteSync) -> Note {
        let note = Note(text: text, gameweek: 10, createdAt: Self.date(minutes))
        context.insert(note)
        sync.added(note)
        context.saveNotes("test")
        return note
    }

    @Test func aNewNoteJoinsTheAccountAndSyncs() async throws {
        let sync = makeSync()
        let note = addNote("Captain Haaland", at: 1, to: sync)
        await sync.flush()

        #expect(note.accountID == FakeAuth.userID)
        #expect(api.state.puts.map(\.id) == [note.syncID])
        #expect(api.state.puts.first?.body.text == "Captain Haaland")
        #expect(sync.pendingCount == 0)
    }

    @Test func signedOutNotesStayOnTheDevice() async throws {
        await account.signOut()
        let sync = makeSync()
        let note = addNote("Hold", at: 1, to: sync)
        await sync.flush()

        #expect(note.accountID == nil)
        #expect(api.state.puts.isEmpty)
        #expect(sync.pendingCount == 0)
    }

    @Test func onlyTheNewestChangeIsSentAfterBeingOffline() async throws {
        api.update { $0.putError = URLError(.notConnectedToInternet) }
        let sync = makeSync()
        let note = addNote("Hold", at: 1, to: sync)
        await sync.flush()
        note.text = "Sell"
        note.updatedAt = Self.date(2)
        sync.changed(note)
        await sync.flush()
        #expect(sync.pendingCount == 1)

        api.update { $0.putError = nil }
        await sync.flush()
        #expect(api.state.puts.map(\.body.text) == ["Sell"])
        #expect(sync.pendingCount == 0)
    }

    @Test func aRefusedChangeIsDroppedAndTheRestStillSend() async throws {
        api.update { $0.putError = FPLAPIClient.APIError.http(status: 422, detail: "Too long") }
        let sync = makeSync()
        _ = addNote("Too long", at: 1, to: sync)
        await sync.flush()
        #expect(sync.pendingCount == 0)

        api.update { $0.putError = nil }
        _ = addNote("Fine", at: 2, to: sync)
        await sync.flush()
        #expect(api.state.puts.map(\.body.text) == ["Fine"])
    }

    @Test func theNewerUpdateWins() throws {
        let sync = makeSync()
        let note = addNote("Mine", at: 5, to: sync)
        let id = try #require(note.syncID)
        context.delete(try #require(try context.fetch(FetchDescriptor<PendingNoteWrite>()).first))

        #expect(!sync.apply(.note(id, "Older", updated: Self.date(4))))
        #expect(!sync.apply(.note(id, "Same time", updated: Self.date(5))))
        #expect(note.text == "Mine")
        #expect(sync.apply(.note(id, "Newer", updated: Self.date(6))))
        #expect(note.text == "Newer")
        #expect(note.updatedAt == Self.date(6))
    }

    @Test func aWaitingChangeCountsAsNewer() throws {
        api.update { $0.putError = URLError(.notConnectedToInternet) }
        let sync = makeSync()
        let note = addNote("Hold", at: 1, to: sync)
        let id = try #require(note.syncID)
        // Deleted here at minute 7, not sent yet.
        sync.deleting(note, at: Self.date(7))
        context.delete(note)

        #expect(!sync.apply(.note(id, "From the other phone", updated: Self.date(6))))
        #expect(try notes().isEmpty)
        #expect(sync.pendingCount == 1)
    }

    @Test func aDeletionFromTheServerRemovesTheNote() throws {
        let sync = makeSync()
        let note = addNote("Hold", at: 1, to: sync)
        #expect(sync.apply(.note(try #require(note.syncID), "", updated: Self.date(2), deleted: true)))
        #expect(try notes().isEmpty)
        #expect(sync.pendingCount == 0)
    }

    @Test func aPulledNoteIsAdded() throws {
        let sync = makeSync()
        let id = UUID()
        #expect(sync.apply(.note(id, "From the other phone", updated: Self.date(3))))
        let note = try #require(try notes().first)
        #expect(note.syncID == id)
        #expect(note.accountID == FakeAuth.userID)
        #expect(note.text == "From the other phone")
    }

    @Test func aLosingWriteTakesTheServersCopy() async throws {
        let sync = makeSync()
        let note = addNote("Mine", at: 1, to: sync)
        let id = try #require(note.syncID)
        api.update { $0.stored[id] = .note(id, "Theirs", updated: NoteSyncTests.date(9)) }
        await sync.flush()

        #expect(note.text == "Theirs")
        #expect(note.updatedAt == Self.date(9))
        #expect(sync.pendingCount == 0)
    }

    @Test func undoAfterADeleteBringsTheNoteBack() async throws {
        let sync = makeSync()
        let note = addNote("Hold", at: 1, to: sync)
        let id = try #require(note.syncID)
        await sync.flush()

        let deleted = DeletedNote(note)
        sync.deleting(note, at: Self.date(2))
        context.delete(note)
        await sync.flush()
        #expect(api.state.stored[id]?.deletedAt == Self.date(2))

        let restored = deleted.restored(at: Self.date(3))
        context.insert(restored)
        sync.changed(restored)
        await sync.flush()
        #expect(api.state.stored[id]?.deletedAt == nil)
        #expect(api.state.stored[id]?.text == "Hold")
        #expect(try notes().map(\.syncID) == [id])
    }

    @Test func pullsEveryPageAndStoresTheCursor() async throws {
        let first = UUID(), second = UUID()
        api.update {
            $0.pages = [
                NotesPage(notes: [.note(first, "One", updated: NoteSyncTests.date(1))], cursor: "c1", more: true),
                NotesPage(notes: [.note(second, "Two", updated: NoteSyncTests.date(2))], cursor: "c2", more: false),
            ]
        }
        let sync = makeSync()
        await sync.pull()
        #expect(Set(try notes().compactMap(\.syncID)) == [first, second])
        #expect(api.state.sinces == [nil, "c1"])

        await sync.pull()
        #expect(api.state.sinces == [nil, "c1", "c2"])
    }

    @Test func anInvalidCursorPullsEverythingAgain() async throws {
        api.update { $0.pages = [NotesPage(notes: [], cursor: "old", more: false)] }
        let sync = makeSync()
        await sync.pull()
        api.update { $0.rejectedCursor = "old" }
        await sync.pull()
        #expect(api.state.sinces == [nil, nil])
    }

    @Test func offersThisDevicesNotesOnceWhenSigningIn() async throws {
        await account.signOut()
        let sync = makeSync()
        _ = addNote("One", at: 1, to: sync)
        _ = addNote("Two", at: 2, to: sync)

        try await account.verify(email: "a@b.co", code: "123456")
        sync.accountChanged(from: .signedOut, to: account.state)
        #expect(sync.uploadOffer == 2)
        sync.keepDeviceNotesOnDevice()
        #expect(sync.uploadOffer == nil)

        // Not again on the next launch.
        #expect(makeSync().uploadOffer == nil)
        #expect(try notes().allSatisfy { $0.accountID == nil })
    }

    @Test func keepingThisDevicesNotesUploadsThem() async throws {
        await account.signOut()
        let sync = makeSync()
        _ = addNote("One", at: 1, to: sync)
        try await account.verify(email: "a@b.co", code: "123456")
        sync.accountChanged(from: .signedOut, to: account.state)

        sync.keepDeviceNotesInAccount()
        await sync.flush()
        #expect(try notes().allSatisfy { $0.accountID == FakeAuth.userID })
        #expect(api.state.puts.map(\.body.text) == ["One"])
    }

    @Test func noOfferWithoutDeviceNotes() async throws {
        await account.signOut()
        let sync = makeSync()
        try await account.verify(email: "a@b.co", code: "123456")
        sync.accountChanged(from: .signedOut, to: account.state)
        #expect(sync.uploadOffer == nil)
    }

    @Test func signingOutRemovesTheAccountsNotesOnly() async throws {
        api.update { $0.putError = URLError(.notConnectedToInternet) }
        let sync = makeSync()
        _ = addNote("Synced", at: 1, to: sync)
        context.insert(Note(text: "Device only", gameweek: 10))
        context.saveNotes("test")
        api.update { $0.putError = nil; $0.pages = [NotesPage(notes: [], cursor: "c1", more: false)] }
        await sync.pull()

        let signedIn = account.state
        await account.signOut()
        sync.accountChanged(from: signedIn, to: account.state)

        #expect(try notes().map(\.text) == ["Device only"])
        #expect(sync.pendingCount == 0)
        #expect(try context.fetch(FetchDescriptor<PendingNoteWrite>()).isEmpty)
        #expect(defaults.string(forKey: "notesSyncCursor") == nil)
    }

    @Test func notesSavedBeforeSyncingGetASyncID() throws {
        let note = Note(text: "Old", gameweek: 3)
        note.syncID = nil
        context.insert(note)
        context.saveNotes("test")
        _ = makeSync()
        #expect(note.syncID != nil)
    }
}
