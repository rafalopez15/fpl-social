//
//  AccountStore.swift
//  FPL
//

import Foundation
import OSLog

/// Whether you're signed in, shared via environment. Signing in is optional:
/// nothing that works signed out ever waits on this.
@MainActor
final class AccountStore: ObservableObject {
    enum State: Equatable {
        /// No sign-in configured for this build (Release until production has accounts).
        case unavailable
        case signedOut
        /// `userID` is `Account.id`, which owns synced notes.
        case signedIn(email: String, userID: UUID)
        /// `DELETE /api/me` is running. Not signed in, so syncing pauses, but the
        /// account's notes stay until it's gone.
        case deleting(email: String, userID: UUID)
    }

    @Published private(set) var state: State {
        didSet { if state != oldValue { stateObservers.forEach { $0(oldValue, state) } } }
    }
    private var stateObservers: [(_ old: State, _ new: State) -> Void] = []

    /// Runs `observer` as the state changes, before views update, so `NoteSync`
    /// and `TeamSync` have the account's data ready when a screen shows the new state.
    func onStateChange(_ observer: @escaping (_ old: State, _ new: State) -> Void) {
        stateObservers.append(observer)
    }
    /// Set when a session ended on its own (not from Sign out), shown until the next sign-in.
    @Published private(set) var signedOutReason: SignInError?
    /// Set once the account is deleted, shown until the next sign-in.
    @Published private(set) var accountDeleted = false
    /// Why the last delete failed; you're still signed in.
    @Published private(set) var deleteError: DeleteAccountError?

    private let auth: (any AuthService)?
    private let fetchAccount: @Sendable (String) async throws -> Account
    private let deleteAccountRequest: @Sendable (String) async throws -> Void

    init(auth: (any AuthService)?,
         fetchAccount: @escaping @Sendable (String) async throws -> Account = { try await FPLAPIClient().me(accessToken: $0) },
         deleteAccount: @escaping @Sendable (String) async throws -> Void = { try await FPLAPIClient().deleteMe(accessToken: $0) }) {
        self.auth = auth
        self.fetchAccount = fetchAccount
        deleteAccountRequest = deleteAccount
        if let auth {
            if let email = auth.storedEmail, let userID = auth.storedUserID {
                state = .signedIn(email: email, userID: userID)
            } else {
                state = .signedOut
            }
        } else {
            state = .unavailable
        }
    }

    /// The signed-in user's id, nil when signed out.
    var userID: UUID? {
        guard case .signedIn(_, let userID) = state else { return nil }
        return userID
    }

    /// The account whose notes stay on the device: signed in, or being deleted.
    var ownerID: UUID? {
        switch state {
        case .signedIn(_, let userID), .deleting(_, let userID): userID
        case .signedOut, .unavailable: nil
        }
    }

    func sendCode(to email: String) async throws {
        guard let auth else { throw SignInError.unavailable }
        try await auth.sendCode(to: email)
        Logger.account.info("Sent a sign-in code")
    }

    /// Checks the code, then calls `GET /api/me`, which creates the account on
    /// the first sign-in. If the API can't take the session, signs out again.
    func verify(email: String, code: String) async throws {
        guard let auth else { throw SignInError.unavailable }
        let signedInEmail = try await auth.verify(email: email, code: code)
        try await finishSigningIn(auth, email: signedInEmail)
    }

    #if DEBUG
    /// Signs in staging's test user with its password, then the same as `verify`.
    func signIn(as user: TestUser) async throws {
        guard let auth else { throw SignInError.unavailable }
        let signedInEmail = try await auth.signIn(email: user.email, password: user.password)
        try await finishSigningIn(auth, email: signedInEmail)
        Logger.account.notice("Signed in as the test user")
    }
    #endif

    /// Calls `GET /api/me` for a session Supabase just gave us.
    private func finishSigningIn(_ auth: any AuthService, email signedInEmail: String) async throws {
        let account: Account
        do {
            account = try await authorized(fetchAccount)
        } catch {
            await auth.signOut()
            state = .signedOut
            let reason = Self.signInError(error)
            Logger.account.error("""
                Signed in with Supabase, but GET me failed (\(String(describing: reason), privacy: .public)): \
                \(error.logSummary, privacy: .public)
                """)
            // The API rejecting a fresh session means it's misconfigured, not that you signed out.
            throw reason == .signedOut ? SignInError.unavailable : reason
        }
        signedOutReason = nil
        accountDeleted = false
        deleteError = nil
        state = .signedIn(email: signedInEmail, userID: account.id)
        Logger.account.notice("Signed in")
    }

    func signOut() async {
        // State first, so the SDK's own signed-out event finds you already signed out.
        signedOutReason = nil
        accountDeleted = false
        deleteError = nil
        state = auth == nil ? .unavailable : .signedOut
        await auth?.signOut()
        Logger.account.notice("Signed out")
    }

    /// Deletes the account with `DELETE /api/me`. Its notes leave the device only
    /// once it's gone; on a failure it's signed back in with `deleteError` set.
    func deleteAccount() async {
        guard let auth, case .signedIn(let email, let userID) = state else { return }
        deleteError = nil
        signedOutReason = nil
        state = .deleting(email: email, userID: userID)
        do {
            try await authorized(deleteAccountRequest)
        } catch SignInError.signedOut {
            // The session was rejected twice, as for any account request.
            signedOutReason = .signedOut
            state = .signedOut
            await auth.signOut()
            Logger.account.notice("Signed out while deleting the account: the session was rejected")
            return
        } catch {
            deleteError = DeleteAccountError(error)
            state = .signedIn(email: email, userID: userID)
            Logger.account.error("Couldn't delete the account: \(error.logSummary, privacy: .public)")
            return
        }
        accountDeleted = true
        // Before the SDK, so its event doesn't say "You were signed out".
        state = .signedOut
        await auth.signOut()
        Logger.account.notice("Deleted the account")
    }

    /// Follows the SDK's session for as long as the caller's task runs, so a
    /// session it drops (say, after a refresh token was revoked) shows as signed
    /// out without waiting for an account request.
    func observeSession() async {
        guard let auth else { return }
        for await _ in auth.sessionEnded {
            guard case .signedIn = state else { continue }
            signedOutReason = .signedOut
            state = .signedOut
            Logger.account.notice("Signed out: the saved session went away")
        }
    }

    /// Runs an account request with an access token. A 401 refreshes the session
    /// and tries once more; a second 401, or a session that can't be refreshed,
    /// signs out and throws `SignInError.signedOut`. Throws the same, without
    /// "You were signed out", when you weren't signed in to begin with.
    func withAccessToken<T: Sendable>(_ call: @Sendable (String) async throws -> T) async throws -> T {
        guard case .signedIn = state else { throw SignInError.signedOut }
        do {
            return try await authorized(call)
        } catch SignInError.signedOut {
            // Unless something already signed out while it ran, such as deleting the account.
            if case .signedIn = state {
                signedOutReason = .signedOut
                state = .signedOut
                await auth?.signOut()
                Logger.account.notice("Signed out: the session couldn't be refreshed or was rejected")
            }
            throw SignInError.signedOut
        }
    }

    private func authorized<T: Sendable>(_ call: @Sendable (String) async throws -> T) async throws -> T {
        guard let auth else { throw SignInError.unavailable }
        let token = try await auth.accessToken()
        do {
            return try await call(token)
        } catch FPLAPIClient.APIError.unauthorized {
            Logger.account.notice("The API rejected the access token; refreshing the session")
            let fresh = try await auth.refreshedAccessToken()
            do {
                return try await call(fresh)
            } catch FPLAPIClient.APIError.unauthorized {
                throw SignInError.signedOut
            }
        }
    }

    /// An API or connection error as a `SignInError`, for the sign-in sheet.
    nonisolated static func signInError(_ error: Error) -> SignInError {
        switch error {
        case let error as SignInError: error
        case FPLAPIClient.APIError.dataUnavailable: .unavailable
        case FPLAPIClient.APIError.unauthorized: .signedOut
        case is URLError: .connection
        default: .unknown
        }
    }
}

/// The sign-in sheet's steps: an email address, then the 6-digit code sent to it.
@MainActor
final class SignInModel: ObservableObject {
    enum Step: Equatable {
        case email
        case code(email: String)
    }

    /// Supabase allows one code per address a minute.
    static let resendCooldown: TimeInterval = 60

    @Published var emailText = ""
    /// Digits only, at most 6.
    @Published var codeText = "" {
        didSet {
            let digits = String(codeText.filter(\.isASCIIDigit).prefix(6))
            if digits != codeText { codeText = digits }
        }
    }
    @Published private(set) var step: Step = .email
    @Published private(set) var isWorking = false
    @Published private(set) var error: SignInError?
    @Published private(set) var canResendAt: Date?
    #if DEBUG
    /// Kept apart from `error` so a failed test-user sign-in doesn't mark the email field.
    @Published private(set) var testUserError: SignInError?
    #endif

    private let account: AccountStore
    private let now: () -> Date

    init(account: AccountStore, now: @escaping () -> Date = Date.init) {
        self.account = account
        self.now = now
    }

    /// The address trimmed and lowercased, or nil if it doesn't look like one.
    var email: String? {
        let email = emailText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return email.wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s]+/) == nil ? nil : email
    }

    var isCodeComplete: Bool { codeText.count == 6 }

    func sendCode() async {
        guard let email else {
            error = .invalidEmail
            return
        }
        await send(to: email)
    }

    func resend() async {
        guard case .code(let email) = step, canResend else { return }
        codeText = ""
        await send(to: email)
    }

    var canResend: Bool {
        canResendAt.map { now() >= $0 } ?? true
    }

    #if DEBUG
    /// True once signed in, so the sheet can close.
    func signIn(as user: TestUser) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        testUserError = nil
        do {
            try await account.signIn(as: user)
            return true
        } catch {
            testUserError = AccountStore.signInError(error)
            return false
        }
    }
    #endif

    /// True once signed in, so the sheet can close.
    func verify() async -> Bool {
        guard case .code(let email) = step, isCodeComplete, !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        error = nil
        do {
            try await account.verify(email: email, code: codeText)
            return true
        } catch {
            self.error = AccountStore.signInError(error)
            // Codes work once, and one Supabase accepted is spent even if the API then
            // failed, so resubmitting it would only say "wrong or expired".
            codeText = ""
            return false
        }
    }

    /// Back to the email field, keeping what was typed.
    func changeEmail() {
        step = .email
        codeText = ""
        error = nil
    }

    private func send(to email: String) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        error = nil
        do {
            try await account.sendCode(to: email)
            step = .code(email: email)
            canResendAt = now().addingTimeInterval(Self.resendCooldown)
        } catch {
            self.error = AccountStore.signInError(error)
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
