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
        case signedIn(email: String)
    }

    @Published private(set) var state: State
    /// Set when a session ended on its own (not from Sign out), shown until the next sign-in.
    @Published private(set) var signedOutReason: SignInError?

    private let auth: (any AuthService)?
    private let fetchAccount: @Sendable (String) async throws -> Account

    init(auth: (any AuthService)?,
         fetchAccount: @escaping @Sendable (String) async throws -> Account = { try await FPLAPIClient().me(accessToken: $0) }) {
        self.auth = auth
        self.fetchAccount = fetchAccount
        if let auth {
            state = auth.storedEmail.map { .signedIn(email: $0) } ?? .signedOut
        } else {
            state = .unavailable
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
        do {
            _ = try await authorized(fetchAccount)
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
        state = .signedIn(email: signedInEmail)
        Logger.account.notice("Signed in")
    }

    func signOut() async {
        // State first, so the SDK's own signed-out event finds you already signed out.
        signedOutReason = nil
        state = auth == nil ? .unavailable : .signedOut
        await auth?.signOut()
        Logger.account.notice("Signed out")
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
            signedOutReason = .signedOut
            state = .signedOut
            await auth?.signOut()
            Logger.account.notice("Signed out: the session couldn't be refreshed or was rejected")
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
