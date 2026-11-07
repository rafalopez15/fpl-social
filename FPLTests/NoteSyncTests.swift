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
        /// Runs once, during the next PUT, to change things while it's sending.
        var duringPut: (@Sendable () async -> Void)?
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
        let duringPut = lock.withLock { state in
            defer { state.duringPut = nil }
            return state.duringPut
        }
        await duringPut?()
        return try lock.withLock { state in
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

        let restored = sync.restore(deleted, at: Self.date(3))
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

        sync.keepDeviceNotesInAccount()
        await sync.flush()
        #expect(try notes().allSatisfy { $0.accountID == FakeAuth.userID })
        #expect(api.state.puts.map(\.body.text) == ["One"])
    }

    @Test func noOfferWithoutDeviceNotes() async throws {
        await account.signOut()
        let sync = makeSync()
        try await account.verify(email: "a@b.co", code: "123456")
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

        await account.signOut()

        #expect(try notes().map(\.text) == ["Device only"])
        #expect(sync.pendingCount == 0)
        #expect(try context.fetch(FetchDescriptor<PendingNoteWrite>()).isEmpty)
        #expect(defaults.string(forKey: "notesSyncCursor") == nil)
    }

    @Test func aSessionThatEndsOnItsOwnAlsoRemovesThem() async throws {
        let sync = makeSync()
        _ = addNote("Synced", at: 1, to: sync)
        let observing = Task { await account.observeSession() }
        defer { observing.cancel() }
        auth.dropSession()
        for _ in 0..<1000 where account.state != .signedOut { await Task.yield() }
        #expect(account.state == .signedOut)
        #expect(try notes().isEmpty)
    }

    @Test func signingOutWarnsAboutUnsyncedChanges() {
        #expect(!AccountCard.signOutMessage(email: "a@b.co", unsynced: 0).contains("lost"))
        #expect(AccountCard.signOutMessage(email: "a@b.co", unsynced: 1).hasSuffix("1 change hasn't synced yet and will be lost."))
        #expect(AccountCard.signOutMessage(email: "a@b.co", unsynced: 3).contains("3 changes haven't"))
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

/// Syncing while the store or the account changes underneath it.
extension NoteSyncTests {
    @Test func aChangeAPullReplacesWhileFlushingIsntSent() async throws {
        api.update { $0.putError = URLError(.notConnectedToInternet) }
        let sync = makeSync()
        let first = addNote("First", at: 1, to: sync)
        let second = addNote("Second", at: 2, to: sync)
        let secondID = try #require(second.syncID)
        await sync.flush()

        // While the first one is sending, a pull brings a newer copy of the second.
        api.update {
            $0.putError = nil
            $0.pages = [NotesPage(notes: [.note(secondID, "From another iPhone", updated: NoteSyncTests.date(3))],
                                  cursor: "c1", more: false)]
            $0.duringPut = { await sync.pull() }
        }
        await sync.flush()

        #expect(api.state.puts.map(\.id) == [first.syncID])
        #expect(second.text == "From another iPhone")
        #expect(sync.pendingCount == 0)
    }

    @Test func aFlushAskedForByTheNextAccountRuns() async throws {
        let other = UUID()
        let userID = OSAllocatedUnfairLock(initialState: FakeAuth.userID)
        let account = AccountStore(auth: auth) { _ in Account(id: userID.withLock { $0 }, createdAt: .now) }
        let sync = NoteSync(container: container, account: account, api: api, defaults: defaults)
        _ = addNote("A's note", at: 1, to: sync)

        // While A's note is sending, A signs out, B signs in and writes a note.
        api.update { [container] in
            $0.duringPut = { @MainActor in
                await account.signOut()
                userID.withLock { $0 = other }
                try? await account.verify(email: "b@b.co", code: "123456")
                let note = Note(text: "B's note", gameweek: 10)
                container.mainContext.insert(note)
                sync.added(note)
                await sync.flush()
            }
        }
        await sync.flush()

        #expect(api.state.puts.map(\.body.text) == ["A's note", "B's note"])
        #expect(sync.pendingCount == 0)
    }

    @Test func undoAfterSigningOutKeepsTheNoteOnTheDevice() async throws {
        let sync = makeSync()
        let note = addNote("Hold", at: 1, to: sync)
        await sync.flush()
        let deleted = DeletedNote(note)
        sync.deleting(note)
        context.delete(note)
        await account.signOut()

        let restored = sync.restore(deleted)
        context.insert(restored)
        sync.changed(restored)

        #expect(restored.accountID == nil)
        #expect(restored.syncID == deleted.syncID)
        #expect(sync.pendingCount == 0)
    }
}

struct NoteTextLimitTests {
    @Test func capsByCodePointsWithoutSplittingACharacter() {
        // One character, five code points.
        let family = "👨‍👩‍👧"
        let letters = String(repeating: "a", count: Note.maxTextLength - 3)
        #expect((letters + family).count <= Note.maxTextLength)
        #expect(Note.capped(letters + family) == letters)

        let exact = String(repeating: "a", count: Note.maxTextLength)
        #expect(Note.capped(exact) == exact)
        #expect(Note.capped("Hold") == "Hold")
    }
}

/// Deleting the account, as it reaches the account's notes.
extension NoteSyncTests {
    func deletingAccount(failing failure: Error?) -> AccountStore {
        AccountStore(auth: auth, fetchAccount: { _ in AccountStoreTests.account },
                     deleteAccount: { _ in if let failure { throw failure } })
    }

    @Test func deletingTheAccountRemovesItsNotesOnly() async throws {
        let account = deletingAccount(failing: nil)
        let sync = NoteSync(container: container, account: account, api: api, defaults: defaults)
        _ = addNote("Synced", at: 1, to: sync)
        context.insert(Note(text: "Device only", gameweek: 10))
        context.saveNotes("test")

        await account.deleteAccount()

        #expect(try notes().map(\.text) == ["Device only"])
        #expect(try context.fetch(FetchDescriptor<PendingNoteWrite>()).isEmpty)
    }

    @Test func aFailedDeleteKeepsEverythingAndSendsWhatWaited() async throws {
        let account = deletingAccount(failing: FPLAPIClient.APIError.dataUnavailable("Couldn't delete your account right now"))
        let sync = NoteSync(container: container, account: account, api: api, defaults: defaults)
        api.update { $0.pages = [NotesPage(notes: [], cursor: "c1", more: false)] }
        await sync.pull()
        api.update { $0.putError = URLError(.notConnectedToInternet) }
        _ = addNote("Not synced yet", at: 1, to: sync)
        context.insert(Note(text: "Device only", gameweek: 10))
        context.saveNotes("test")
        await sync.flush()
        api.update { $0.putError = nil }

        await account.deleteAccount()
        // Sending what waited, then pulling.
        for _ in 0..<1000 where api.state.sinces.count < 2 { await Task.yield() }

        #expect(Set(try notes().map(\.text)) == ["Not synced yet", "Device only"])
        #expect(api.state.puts.map(\.body.text) == ["Not synced yet"])
        #expect(sync.uploadOffer == nil)
        // Picks up from the cursor rather than downloading every note again.
        #expect(api.state.sinces.last == "c1")
    }

    @Test func notesStayWhileDeleting() async throws {
        let delete = DeleteAccountTests.FakeDelete()
        let account = AccountStore(auth: auth, fetchAccount: { _ in AccountStoreTests.account },
                                   deleteAccount: { try await delete($0) })
        delete.store = account
        let sync = NoteSync(container: container, account: account, api: api, defaults: defaults)
        _ = addNote("Synced", at: 1, to: sync)
        let counted = OSAllocatedUnfairLock(initialState: -1)
        delete.onCall = { @MainActor [context] in
            let count = (try? context.fetch(FetchDescriptor<Note>()).count) ?? 0
            counted.withLock { $0 = count }
        }

        await account.deleteAccount()

        #expect(counted.withLock { $0 } == 1)
        #expect(try notes().isEmpty)
    }
}
