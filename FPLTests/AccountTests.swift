//
//  AccountTests.swift
//  FPLTests
//

import Foundation
import os
import Testing
@testable import FPL

/// Stands in for Supabase: hands out tokens and records what was called.
final class FakeAuth: AuthService, @unchecked Sendable {
    /// Every fake session's user, and `AccountStoreTests.account`'s id.
    static let userID = UUID(uuidString: "0B6C2A4E-6F1D-4A43-9D1B-3C9F0F6E2A10")!

    private let lock = OSAllocatedUnfairLock(initialState: State())

    struct State {
        var email: String?
        var token = "first"
        var refreshes = 0
        var signOuts = 0
        var verifyError: SignInError?
        var refreshError: SignInError?
        /// Runs inside `signOut()`, before the SDK's event, to look at the store at that moment.
        var onSignOut: (@Sendable () async -> Void)?
    }

    let sessionEnded: AsyncStream<Void>
    private let ended: AsyncStream<Void>.Continuation

    init(email: String? = nil) {
        (sessionEnded, ended) = AsyncStream.makeStream()
        lock.withLock { $0.email = email }
    }

    /// What the SDK does when it drops the session on its own.
    func dropSession() {
        update { $0.email = nil }
        ended.yield()
    }

    var state: State { lock.withLock { $0 } }
    func update(_ change: @Sendable (inout State) -> Void) { lock.withLock { change(&$0) } }

    var storedEmail: String? { state.email }
    var storedUserID: UUID? { state.email == nil ? nil : Self.userID }

    func sendCode(to email: String) async throws {}

    func verify(email: String, code: String) async throws -> String {
        if let error = state.verifyError { throw error }
        update { $0.email = email }
        return email
    }

    func accessToken() async throws -> String {
        guard state.email != nil else { throw SignInError.signedOut }
        return state.token
    }

    func refreshedAccessToken() async throws -> String {
        if let error = state.refreshError { throw error }
        update { $0.refreshes += 1; $0.token = "fresh" }
        return "fresh"
    }

    func signOut() async {
        await state.onSignOut?()
        update { $0.email = nil; $0.signOuts += 1 }
        ended.yield()
    }
}

struct AccountRequestTests {
    let client = FPLAPIClient(baseURL: URL(string: "https://stub.test/api")!)

    @Test func addsTheTokenOnlyToAccountRoutes() {
        for path in ["me", "me/notes", "me/teams/1"] {
            #expect(client.request(path, accessToken: "abc").value(forHTTPHeaderField: "Authorization") == "Bearer abc")
        }
        for path in ["elements", "managers/1", "managers/1/picks", "events/9/live", "media", "meta/me"] {
            #expect(client.request(path, accessToken: "abc").value(forHTTPHeaderField: "Authorization") == nil)
        }
        #expect(client.request("me").value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func keepsTheQuery() {
        let request = client.request("fixtures", query: [URLQueryItem(name: "started", value: "false")])
        #expect(request.url?.absoluteString == "https://stub.test/api/fixtures?started=false")
    }

    @Test func putsANoteAsJSON() throws {
        let id = try #require(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        let request = client.request("me/notes/\(id.uuidString.lowercased())", method: "PUT",
                                     body: Data("{}".utf8), accessToken: "abc")
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.absoluteString == "https://stub.test/api/me/notes/6f9619ff-8b86-d011-b42d-00c04fc964ff")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
    }

    @Test func decodesTheAccount() throws {
        let data = Data(#"{"id": "0b6c2a4e-6f1d-4a43-9d1b-3c9f0f6e2a10", "created_at": "2026-11-06T02:13:32.123456Z"}"#.utf8)
        let account = try JSONDecoder.fplAPI.decode(Account.self, from: data)
        #expect(account.id == UUID(uuidString: "0B6C2A4E-6F1D-4A43-9D1B-3C9F0F6E2A10"))
        #expect(account.createdAt.timeIntervalSince1970.rounded() == 1_793_931_212)
    }
}

extension StubbedNetworkTests {
    struct AccountStatusTests {
        let client = FPLAPIClient(baseURL: URL(string: "https://stub.test/api")!, session: StubURLProtocol.session)

        @Test func mapsA401ToUnauthorized() async {
            StubURLProtocol.responses = ["/api/me": (401, #"{"detail": "Not signed in"}"#)]
            await #expect {
                try await client.me(accessToken: "abc")
            } throws: { error in
                guard case FPLAPIClient.APIError.unauthorized("Not signed in") = error else { return false }
                return true
            }
        }

        @Test func anInvalidCursorIsA422() async {
            StubURLProtocol.responses = ["/api/me/notes": (422, #"{"detail": "Invalid cursor"}"#)]
            await #expect {
                try await client.notes(since: "bad", accessToken: "abc")
            } throws: { error in
                guard case FPLAPIClient.APIError.http(status: 422, detail: "Invalid cursor") = error else { return false }
                return true
            }
        }

        @Test func decodesTheStoredNote() async throws {
            let id = try #require(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
            StubURLProtocol.responses = ["/api/me/notes/6f9619ff-8b86-d011-b42d-00c04fc964ff": (200, """
                {"id": "6f9619ff-8b86-d011-b42d-00c04fc964ff", "text": "Hold", "gameweek": 10, "players": [],
                 "transfer": null, "manager_id": null, "created_at": "2026-10-26T07:33:20Z",
                 "updated_at": "2026-10-26T07:35:00.5Z", "deleted_at": null}
                """)]
            let body = NoteBody(text: "Hold", gameweek: 10, players: [], createdAt: .now, updatedAt: .now)
            let stored = try await client.putNote(body, id: id, accessToken: "abc")
            #expect(stored.id == id)
            #expect(stored.text == "Hold")
        }

        @Test func mapsA503ToUnavailable() async {
            StubURLProtocol.responses = ["/api/me": (503, #"{"detail": "Sign-in is unavailable right now"}"#)]
            await #expect {
                try await client.me(accessToken: "abc")
            } throws: { error in
                AccountStore.signInError(error) == .unavailable
            }
        }
    }
}

@MainActor
struct AccountStoreTests {
    nonisolated static let account = Account(id: FakeAuth.userID, createdAt: .now)

    /// `GET /me` that only accepts `token`, counting calls.
    final class FakeMe: @unchecked Sendable {
        private let calls = OSAllocatedUnfairLock(initialState: 0)
        let accepted: String?
        init(accepting accepted: String?) { self.accepted = accepted }
        var count: Int { calls.withLock { $0 } }

        func callAsFunction(_ token: String) async throws -> Account {
            calls.withLock { $0 += 1 }
            guard token == accepted else { throw FPLAPIClient.APIError.unauthorized("Not signed in") }
            return AccountStoreTests.account
        }
    }

    @Test func noSignInWithoutConfiguration() async {
        let store = AccountStore(auth: nil)
        #expect(store.state == .unavailable)
        await #expect(throws: SignInError.unavailable) { try await store.sendCode(to: "a@b.co") }
    }

    @Test func startsFromTheSavedSession() {
        #expect(AccountStore(auth: FakeAuth(email: "a@b.co")).state == .signedIn(email: "a@b.co", userID: FakeAuth.userID))
        #expect(AccountStore(auth: FakeAuth()).state == .signedOut)
    }

    @Test func signingInCallsMeOnce() async throws {
        let me = FakeMe(accepting: "first")
        let store = AccountStore(auth: FakeAuth()) { try await me($0) }
        try await store.verify(email: "a@b.co", code: "123456")
        #expect(store.state == .signedIn(email: "a@b.co", userID: FakeAuth.userID))
        #expect(me.count == 1)
    }

    @Test func a401RefreshesOnceAndRetries() async throws {
        let auth = FakeAuth(email: "a@b.co")
        let me = FakeMe(accepting: "fresh")
        let store = AccountStore(auth: auth) { try await me($0) }
        let account = try await store.withAccessToken { try await me($0) }
        #expect(account == Self.account)
        #expect(auth.state.refreshes == 1)
        #expect(me.count == 2)
        #expect(store.state == .signedIn(email: "a@b.co", userID: FakeAuth.userID))
    }

    @Test func aSecond401SignsOut() async {
        let auth = FakeAuth(email: "a@b.co")
        let me = FakeMe(accepting: nil)
        let store = AccountStore(auth: auth) { try await me($0) }
        let recorded = stateAtSignOut(of: auth, store)
        await #expect(throws: SignInError.signedOut) { try await store.withAccessToken { try await me($0) } }
        #expect(recorded.withLock { $0 } == .signedOut)
        #expect(store.state == .signedOut)
        #expect(store.signedOutReason == .signedOut)
        #expect(auth.state.refreshes == 1)
        #expect(auth.state.signOuts == 1)
        #expect(me.count == 2)
    }

    @Test func aFailedRefreshSignsOut() async {
        let auth = FakeAuth(email: "a@b.co")
        auth.update { $0.refreshError = .signedOut }
        let me = FakeMe(accepting: nil)
        let store = AccountStore(auth: auth) { try await me($0) }
        await #expect(throws: SignInError.signedOut) { try await store.withAccessToken { try await me($0) } }
        #expect(store.state == .signedOut)
    }

    @Test func noConnectionWhileRefreshingKeepsYouSignedIn() async {
        let auth = FakeAuth(email: "a@b.co")
        auth.update { $0.refreshError = .connection }
        let me = FakeMe(accepting: nil)
        let store = AccountStore(auth: auth) { try await me($0) }
        await #expect(throws: SignInError.connection) { try await store.withAccessToken { try await me($0) } }
        #expect(store.state == .signedIn(email: "a@b.co", userID: FakeAuth.userID))
        #expect(auth.state.signOuts == 0)
    }

    @Test func anAPIThatCantTakeTheSessionLeavesYouSignedOut() async {
        let auth = FakeAuth()
        let store = AccountStore(auth: auth) { _ in throw FPLAPIClient.APIError.dataUnavailable("Sign-in is unavailable right now") }
        await #expect(throws: SignInError.unavailable) { try await store.verify(email: "a@b.co", code: "123456") }
        #expect(store.state == .signedOut)
        #expect(store.signedOutReason == nil)
        #expect(auth.state.signOuts == 1)

        // A rejected fresh session is the API's problem too, not "you were signed out".
        let rejecting = AccountStore(auth: FakeAuth()) { _ in throw FPLAPIClient.APIError.unauthorized("Not signed in") }
        await #expect(throws: SignInError.unavailable) { try await rejecting.verify(email: "a@b.co", code: "123456") }
    }

    @Test func callsWhileSignedOutDontSayYouWereSignedOut() async {
        let auth = FakeAuth()
        let me = FakeMe(accepting: "first")
        let store = AccountStore(auth: auth) { try await me($0) }
        await #expect(throws: SignInError.signedOut) { try await store.withAccessToken { try await me($0) } }
        #expect(store.signedOutReason == nil)
        #expect(auth.state.signOuts == 0)
        #expect(me.count == 0)
    }

    /// Waits for the store's session observer to catch up.
    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func aSessionTheSDKDropsSignsOut() async throws {
        let auth = FakeAuth(email: "a@b.co")
        let store = AccountStore(auth: auth)
        let observing = Task { await store.observeSession() }
        defer { observing.cancel() }

        auth.dropSession()
        try await waitUntil { store.state == .signedOut }
        #expect(store.state == .signedOut)
        #expect(store.signedOutReason == .signedOut)
    }

    /// The store's state when it called `auth.signOut()`.
    func stateAtSignOut(of auth: FakeAuth, _ store: AccountStore) -> OSAllocatedUnfairLock<AccountStore.State?> {
        let recorded = OSAllocatedUnfairLock<AccountStore.State?>(initialState: nil)
        auth.update { $0.onSignOut = { let state = await store.state; recorded.withLock { $0 = state } } }
        return recorded
    }

    @Test func signingOutYourselfDoesntSayYouWereSignedOut() async throws {
        let auth = FakeAuth(email: "a@b.co")
        let store = AccountStore(auth: auth)
        let recorded = stateAtSignOut(of: auth, store)
        let observing = Task { await store.observeSession() }
        defer { observing.cancel() }

        await store.signOut()
        // Already signed out when the SDK hears about it, so its event changes nothing.
        #expect(recorded.withLock { $0 } == .signedOut)
        #expect(store.state == .signedOut)
        #expect(store.signedOutReason == nil)
    }

    @Test func aDroppedSessionAfterSigningInAgainSignsOutAgain() async throws {
        let auth = FakeAuth()
        let store = AccountStore(auth: auth) { _ in AccountStoreTests.account }
        let observing = Task { await store.observeSession() }
        defer { observing.cancel() }

        try await store.verify(email: "a@b.co", code: "123456")
        #expect(store.state == .signedIn(email: "a@b.co", userID: FakeAuth.userID))
        auth.dropSession()
        try await waitUntil { store.state == .signedOut }
        #expect(store.signedOutReason == .signedOut)
    }

    @Test func signingOut() async throws {
        let auth = FakeAuth(email: "a@b.co")
        let store = AccountStore(auth: auth)
        await store.signOut()
        #expect(store.state == .signedOut)
        #expect(auth.state.signOuts == 1)
    }
}

@MainActor
struct SignInModelTests {
    @Test func checksTheEmail() async {
        let model = SignInModel(account: AccountStore(auth: FakeAuth()))
        model.emailText = "not an email"
        await model.sendCode()
        #expect(model.error == .invalidEmail)
        #expect(model.step == .email)

        model.emailText = "  Someone@Example.COM "
        await model.sendCode()
        #expect(model.error == nil)
        #expect(model.step == .code(email: "someone@example.com"))
    }

    @Test func keepsOnlySixDigits() {
        let model = SignInModel(account: AccountStore(auth: FakeAuth()))
        model.codeText = "12a 34-5678"
        #expect(model.codeText == "123456")
        #expect(model.isCodeComplete)
    }

    @Test func resendWaitsForTheCooldown() async {
        var now = Date(timeIntervalSince1970: 0)
        let model = SignInModel(account: AccountStore(auth: FakeAuth())) { now }
        model.emailText = "a@b.co"
        await model.sendCode()
        #expect(!model.canResend)
        now += SignInModel.resendCooldown
        #expect(model.canResend)
    }

    @Test func aWrongCodeClearsTheField() async {
        let auth = FakeAuth()
        auth.update { $0.verifyError = .wrongCode }
        let model = SignInModel(account: AccountStore(auth: auth))
        model.emailText = "a@b.co"
        await model.sendCode()
        model.codeText = "123456"
        #expect(await model.verify() == false)
        #expect(model.error == .wrongCode)
        #expect(model.codeText.isEmpty)
    }

    @Test func aSpentCodeIsClearedWhenTheAPIFails() async {
        let account = AccountStore(auth: FakeAuth()) { _ in
            throw FPLAPIClient.APIError.dataUnavailable("Sign-in is unavailable right now")
        }
        let model = SignInModel(account: account)
        model.emailText = "a@b.co"
        await model.sendCode()
        model.codeText = "123456"
        #expect(await model.verify() == false)
        #expect(model.error == .unavailable)
        #expect(model.codeText.isEmpty)
    }

    @Test func aRightCodeSignsIn() async {
        let account = AccountStore(auth: FakeAuth()) { _ in AccountStoreTests.account }
        let model = SignInModel(account: account)
        model.emailText = "a@b.co"
        await model.sendCode()
        model.codeText = "123456"
        #expect(await model.verify())
        #expect(account.state == .signedIn(email: "a@b.co", userID: FakeAuth.userID))
    }
}
