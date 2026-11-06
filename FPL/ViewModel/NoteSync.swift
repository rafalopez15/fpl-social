//
//  NoteSync.swift
//  FPL
//

import Foundation
import Network
import OSLog
import SwiftData

/// Syncs the signed-in account's notes with `/api/me/notes`, shared via environment.
///
/// Notes are saved on the device first. A change to one of the account's notes
/// goes into the outbox (`PendingNoteWrite`) and is sent when it can be, so
/// nothing waits on the network. The newer `updatedAt` wins everywhere. Notes
/// with no `accountID` stay on this device, and only the signed-in account's
/// notes are kept: signing out removes them until you sign in again.
@MainActor
final class NoteSync: ObservableObject {
    /// How many device-only notes to offer to keep in the account, right after signing in.
    @Published private(set) var uploadOffer: Int?
    /// Changes to the account's notes that haven't reached the server yet.
    @Published private(set) var pendingCount = 0

    /// Held so the context stays usable: a context doesn't keep its container alive.
    let container: ModelContainer
    private let context: ModelContext
    private let account: AccountStore
    private let api: any NotesAPI
    private let defaults: UserDefaults
    private var isFlushing = false
    private var flushAgain = false
    private var isPulling = false

    private static let cursorKey = "notesSyncCursor"
    private static let cursorAccountKey = "notesSyncCursorAccount"

    /// Works in the container's main context, the one views get from the environment.
    init(container: ModelContainer, account: AccountStore, api: any NotesAPI = FPLAPIClient(),
         defaults: UserDefaults = .standard) {
        self.container = container
        context = container.mainContext
        self.account = account
        self.api = api
        self.defaults = defaults
        account.onStateChange = { [weak self] old, new in self?.accountChanged(from: old, to: new) }
        fillInSyncIDs()
        removeOtherAccountsNotes()
        refreshPendingCount()
    }

    // MARK: - Recording changes

    /// A note just inserted. Signed in, it joins the account and syncs.
    /// Call before saving the context.
    func added(_ note: Note) {
        guard let userID = account.userID else { return }
        note.accountID = userID
        record(NoteBody(note), for: note)
        scheduleFlush()
    }

    /// A note edited, or brought back by undo. Syncs if it's the account's.
    /// Call before saving the context.
    func changed(_ note: Note) {
        guard isSynced(note) else { return }
        record(NoteBody(note), for: note)
        scheduleFlush()
    }

    /// A note about to be deleted from the context. Syncs the deletion if it's the account's.
    func deleting(_ note: Note, at date: Date = .now) {
        guard isSynced(note) else { return }
        record(.tombstone(of: note, at: date), for: note)
        scheduleFlush()
    }

    // MARK: - Account changes

    /// Runs when the account's state changes. Signing out removes the account's
    /// notes; signing in offers to keep this device's notes in the account, then syncs.
    func accountChanged(from old: AccountStore.State, to new: AccountStore.State) {
        removeOtherAccountsNotes()
        guard case .signedIn = new else {
            uploadOffer = nil
            return
        }
        guard case .signedOut = old else { return }
        let deviceOnly = deviceOnlyNotes().count
        uploadOffer = deviceOnly > 0 ? deviceOnly : nil
        Task { await sync() }
    }

    /// The answer to `uploadOffer`: adds every device-only note to the account and syncs them.
    func keepDeviceNotesInAccount() {
        uploadOffer = nil
        guard let userID = account.userID else { return }
        let notes = deviceOnlyNotes()
        for note in notes {
            note.accountID = userID
            record(NoteBody(note), for: note)
        }
        context.saveNotes("Added \(notes.count) device note(s) to the account")
        scheduleFlush()
    }

    /// The other answer: they stay on this device.
    func keepDeviceNotesOnDevice() {
        uploadOffer = nil
        Logger.notes.info("Kept device notes out of the account")
    }

    // MARK: - Syncing

    /// Sends waiting changes, then pulls the server's.
    func sync() async {
        await flush()
        await pull()
    }

    /// Sends the outbox, oldest change first. Stops at the first failure that a
    /// retry could fix (offline, server down, signed out) and tries again later.
    func flush() async {
        guard let userID = account.userID else { return }
        guard !isFlushing else {
            flushAgain = true
            return
        }
        isFlushing = true
        defer {
            isFlushing = false
            refreshPendingCount()
        }
        repeat {
            flushAgain = false
            for write in pendingWrites(for: userID) {
                guard await send(write, userID: userID) else { return }
            }
        } while flushAgain && account.userID == userID
    }

    /// Pulls the server's changes since the stored cursor, page by page.
    func pull() async {
        guard let userID = account.userID, !isPulling else { return }
        isPulling = true
        defer { isPulling = false }
        var cursor = storedCursor(for: userID)
        var startedOver = false
        while true {
            let since = cursor
            do {
                let page = try await account.withAccessToken { [api] in
                    try await api.notes(since: since, accessToken: $0)
                }
                guard account.userID == userID else { return }
                if !page.notes.isEmpty {
                    let applied = page.notes.filter { apply($0) }.count
                    context.saveNotes("Pulled \(page.notes.count) note change(s), applied \(applied)")
                }
                storeCursor(page.cursor, for: userID)
                cursor = page.cursor
                guard page.more else { return }
            } catch FPLAPIClient.APIError.http(status: 422, detail: _) where since != nil && !startedOver {
                Logger.notes.notice("The notes cursor was rejected; pulling every note again")
                cursor = nil
                startedOver = true
            } catch {
                Logger.notes.notice("Couldn't pull notes: \(error.logSummary, privacy: .public)")
                return
            }
        }
    }

    /// Applies a note from the server. It wins only if it's newer than this
    /// device's copy and any change waiting to send; a deleted one is removed.
    /// Returns whether it changed anything.
    @discardableResult
    func apply(_ remote: RemoteNote) -> Bool {
        guard let userID = account.userID else { return false }
        let local = note(withSyncID: remote.id)
        let pending = pendingWrite(for: remote.id)
        if let known = [local?.updatedAt, pending?.updatedAt].compactMap(\.self).max(),
           remote.updatedAt <= known {
            return false
        }
        // The server already has something newer than the waiting change.
        if let pending {
            context.delete(pending)
            refreshPendingCount()
        }
        if remote.deletedAt != nil {
            if let local { context.delete(local) }
            return local != nil || pending != nil
        }
        let note = local ?? Note(text: remote.text, gameweek: remote.gameweek)
        if local == nil {
            note.syncID = remote.id
            context.insert(note)
        }
        note.text = remote.text
        note.gameweek = remote.gameweek
        note.players = remote.players
        note.transfer = remote.transfer
        note.managerID = remote.managerId
        note.createdAt = remote.createdAt
        note.updatedAt = remote.updatedAt
        note.accountID = userID
        return true
    }

    /// Sends waiting changes whenever the connection comes back, for as long as
    /// the caller's task runs.
    func syncWhenOnline() async {
        var wasOnline = true
        for await isOnline in Self.connectionChanges() {
            if isOnline && !wasOnline {
                Logger.notes.info("Back online; syncing notes")
                await sync()
            }
            wasOnline = isOnline
        }
    }

    // MARK: - Private

    private func isSynced(_ note: Note) -> Bool {
        note.accountID != nil && note.accountID == account.userID
    }

    /// Puts the change in the outbox, replacing one already waiting for the note.
    private func record(_ body: NoteBody, for note: Note) {
        guard let userID = account.userID, let noteID = note.syncID else { return }
        let data: Data
        do {
            data = try JSONEncoder.fplAPI.encode(body)
        } catch {
            Logger.notes.fault("Couldn't encode a note to sync: \(error.logSummary, privacy: .public)")
            return
        }
        if let pending = pendingWrite(for: noteID) {
            pending.body = data
            pending.updatedAt = body.updatedAt
            pending.accountID = userID
        } else {
            context.insert(PendingNoteWrite(noteID: noteID, accountID: userID, updatedAt: body.updatedAt, body: data))
        }
        refreshPendingCount()
    }

    private func scheduleFlush() {
        Task { await flush() }
    }

    /// Returns false to stop flushing.
    private func send(_ write: PendingNoteWrite, userID: UUID) async -> Bool {
        let noteID = write.noteID
        let sentAt = write.updatedAt
        let body: NoteBody
        do {
            body = try JSONDecoder.fplAPI.decode(NoteBody.self, from: write.body)
        } catch {
            Logger.notes.fault("Dropped a waiting note change that couldn't be decoded: \(error.logSummary, privacy: .public)")
            context.delete(write)
            context.saveNotes("Dropped a waiting note change")
            return true
        }
        do {
            let stored = try await account.withAccessToken { [api] in
                try await api.putNote(body, id: noteID, accessToken: $0)
            }
            // Signed out while it was sending: the account's notes are gone.
            guard account.userID == userID else { return false }
            removeWrite(for: noteID, sentAt: sentAt)
            // The server keeps a newer copy if it has one; then that's the note.
            apply(stored)
            context.saveNotes(body.deletedAt == nil ? "Synced a note" : "Synced a deleted note")
            return true
        } catch {
            guard Self.isRefused(error) else {
                Logger.notes.notice("Couldn't sync a note, will retry: \(error.logSummary, privacy: .public)")
                return false
            }
            // Sending it again won't help, and it would hold up the rest.
            Logger.notes.error("The API refused a note change; dropped it: \(error.logSummary, privacy: .public)")
            removeWrite(for: noteID, sentAt: sentAt)
            context.saveNotes("Dropped a refused note change")
            return true
        }
    }

    /// Removes the outbox row once its change is on the server, unless a newer
    /// change replaced it while it was sending.
    private func removeWrite(for noteID: UUID, sentAt: Date) {
        guard let write = pendingWrite(for: noteID), write.updatedAt == sentAt else { return }
        context.delete(write)
    }

    /// Removes notes, waiting changes and the cursor of any account but the signed-in one.
    private func removeOtherAccountsNotes() {
        let userID = account.userID
        let notes = allNotes().filter { $0.accountID != nil && $0.accountID != userID }
        let writes = allPendingWrites().filter { $0.accountID != userID }
        if let cursorAccount = defaults.string(forKey: Self.cursorAccountKey), cursorAccount != userID?.uuidString {
            defaults.removeObject(forKey: Self.cursorKey)
            defaults.removeObject(forKey: Self.cursorAccountKey)
        }
        guard !notes.isEmpty || !writes.isEmpty else { return }
        notes.forEach(context.delete)
        writes.forEach(context.delete)
        context.saveNotes("Removed \(notes.count) signed-out account note(s) and \(writes.count) waiting change(s)")
        refreshPendingCount()
    }

    /// Notes saved before syncing existed have no sync id.
    private func fillInSyncIDs() {
        let notes = allNotes().filter { $0.syncID == nil }
        guard !notes.isEmpty else { return }
        for note in notes { note.syncID = UUID() }
        context.saveNotes("Gave \(notes.count) note(s) a sync id")
    }

    private func deviceOnlyNotes() -> [Note] {
        allNotes().filter { $0.accountID == nil }
    }

    private func refreshPendingCount() {
        let userID = account.userID
        pendingCount = allPendingWrites().count(where: { $0.accountID == userID })
    }
}

extension NoteSync {
    /// For previews: signed out, in memory.
    static let preview: NoteSync = {
        do {
            let container = try ModelContainer(for: Note.self, PendingNoteWrite.self,
                                               configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            return NoteSync(container: container, account: AccountStore(auth: nil))
        } catch {
            fatalError("Couldn't create the preview notes store: \(error)")
        }
    }()
}

/// Lookups in the store and UserDefaults.
private extension NoteSync {
    // Notes number in the hundreds, so these filter in memory rather than
    // relying on SwiftData predicates over optionals.
    func allNotes() -> [Note] {
        (try? context.fetch(FetchDescriptor<Note>())) ?? []
    }

    func note(withSyncID id: UUID) -> Note? {
        allNotes().first { $0.syncID == id }
    }

    func allPendingWrites() -> [PendingNoteWrite] {
        (try? context.fetch(FetchDescriptor<PendingNoteWrite>(sortBy: [SortDescriptor(\.updatedAt)]))) ?? []
    }

    func pendingWrites(for userID: UUID) -> [PendingNoteWrite] {
        allPendingWrites().filter { $0.accountID == userID }
    }

    func pendingWrite(for noteID: UUID) -> PendingNoteWrite? {
        allPendingWrites().first { $0.noteID == noteID }
    }

    func storedCursor(for userID: UUID) -> String? {
        guard defaults.string(forKey: Self.cursorAccountKey) == userID.uuidString else { return nil }
        return defaults.string(forKey: Self.cursorKey)
    }

    func storeCursor(_ cursor: String, for userID: UUID) {
        defaults.set(cursor, forKey: Self.cursorKey)
        defaults.set(userID.uuidString, forKey: Self.cursorAccountKey)
    }

    nonisolated static func connectionChanges() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { continuation.yield($0.status == .satisfied) }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "NoteSync.connection"))
        }
    }

    /// A 404 (someone else's id) or 422 (a note the API won't take).
    nonisolated static func isRefused(_ error: Error) -> Bool {
        switch error {
        case FPLAPIClient.APIError.notFound, FPLAPIClient.APIError.http(status: 422, detail: _): true
        default: false
        }
    }
}
