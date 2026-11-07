//
//  AuthService.swift
//  FPL
//

import Auth
import Foundation
import OSLog

/// Signing in with an email code and holding the session. A protocol so tests
/// can stand in for Supabase. Methods throw `SignInError`.
protocol AuthService: Sendable {
    /// The email of the saved session, or nil when signed out. No network call,
    /// so it's safe at launch.
    var storedEmail: String? { get }
    /// The user id of the saved session, the same as `Account.id`. No network call.
    var storedUserID: UUID? { get }
    func sendCode(to email: String) async throws
    /// Returns the signed-in email.
    func verify(email: String, code: String) async throws -> String
    #if DEBUG
    /// Signs in the staging test user. Returns the signed-in email.
    func signIn(email: String, password: String) async throws -> String
    #endif
    /// A valid access token, refreshed first if it's about to expire.
    func accessToken() async throws -> String
    /// Refreshes the session even if the token looks valid, after the API rejected it.
    func refreshedAccessToken() async throws -> String
    /// Ends the session on this device. Never fails: the local session is removed regardless.
    func signOut() async
    /// Yields each time the saved session goes away, including when the SDK drops
    /// it after a failed refresh. Also yields for `signOut()`.
    var sessionEnded: AsyncStream<Void> { get }
}

/// Supabase Auth through supabase-swift, which saves the session in the
/// keychain and refreshes it.
struct SupabaseAuthService: AuthService {
    private let client: AuthClient

    init(projectURL: URL, publishableKey: String) {
        client = AuthClient(url: projectURL.appendingPathComponent("auth/v1"),
                            headers: ["apikey": publishableKey],
                            localStorage: KeychainLocalStorage(),
                            emitLocalSessionAsInitialSession: true)
    }

    /// From the `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` build settings (via
    /// Info.plist). Nil when either is empty, as in Release until production has accounts.
    static func configured(bundle: Bundle = .main) -> SupabaseAuthService? {
        guard let url = (bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String).flatMap(URL.init(string:)),
              url.host() != nil,
              let key = bundle.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String, !key.isEmpty
        else { return nil }
        return SupabaseAuthService(projectURL: url, publishableKey: key)
    }

    var storedEmail: String? {
        client.currentSession.map { $0.user.email ?? "" }
    }

    var storedUserID: UUID? {
        client.currentSession?.user.id
    }

    func sendCode(to email: String) async throws {
        try await mapped { try await client.signInWithOTP(email: email) }
    }

    func verify(email: String, code: String) async throws -> String {
        try await mapped {
            let response = try await client.verifyOTP(email: email, token: code, type: .email)
            return response.user.email ?? email
        }
    }

    #if DEBUG
    func signIn(email: String, password: String) async throws -> String {
        try await mapped {
            let session = try await client.signIn(email: email, password: password)
            return session.user.email ?? email
        }
    }
    #endif

    func accessToken() async throws -> String {
        try await mapped { try await client.session.accessToken }
    }

    func refreshedAccessToken() async throws -> String {
        try await mapped { try await client.refreshSession().accessToken }
    }

    func signOut() async {
        do {
            try await client.signOut(scope: .local)
        } catch {
            // The SDK has already removed the local session; only telling Supabase failed.
            Logger.account.notice("Couldn't end the session with Supabase: \(error.logSummary, privacy: .public)")
        }
    }

    var sessionEnded: AsyncStream<Void> {
        let changes = client.authStateChanges
        return AsyncStream { continuation in
            let task = Task {
                for await (event, session) in changes {
                    switch event {
                    case .signedOut, .userDeleted: continuation.yield()
                    case .initialSession where session == nil: continuation.yield()
                    default: break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func mapped<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch {
            let mapped = Self.signInError(error)
            Logger.account.error("""
                Supabase Auth failed (\(String(describing: mapped), privacy: .public)): \(error.logSummary, privacy: .public)
                """)
            throw mapped
        }
    }

    static func signInError(_ error: Error) -> SignInError {
        if error is URLError { return .connection }
        guard let error = error as? AuthError else { return .unknown }
        switch error {
        case .sessionMissing:
            return .signedOut
        case let .api(_, code, _, response):
            switch code {
            case .otpExpired: return .wrongCode
            #if DEBUG
            case .invalidCredentials: return .wrongPassword
            #endif
            case .validationFailed: return .invalidEmail
            case .emailAddressNotAuthorized: return .emailNotAllowed
            case .overEmailSendRateLimit, .overRequestRateLimit: return .tooManyCodes
            case .sessionNotFound, .sessionExpired, .refreshTokenNotFound, .refreshTokenAlreadyUsed: return .signedOut
            default: return response.statusCode >= 500 ? .unavailable : .unknown
            }
        default:
            return .unknown
        }
    }
}
