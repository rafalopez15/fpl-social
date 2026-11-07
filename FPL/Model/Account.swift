//
//  Account.swift
//  FPL
//

import Foundation

/// The signed-in user's account from `GET /api/me`. The email lives with
/// Supabase Auth, not here.
struct Account: Decodable, Equatable, Sendable {
    /// The Supabase Auth user id.
    let id: UUID
    let createdAt: Date
}

/// Why signing in, or a call that needs an account, didn't work. The message
/// is shown as is.
enum SignInError: Error, Equatable {
    case invalidEmail
    /// Staging's email sender only reaches a few test addresses.
    case emailNotAllowed
    /// Supabase gives the same error for a wrong code and an expired one.
    case wrongCode
    case tooManyCodes
    #if DEBUG
    /// Supabase rejected the Debug test user: a wrong email or password, or not confirmed.
    case testUserRejected
    #endif
    case connection
    /// Sign-in isn't configured, Supabase is down or the API answered 503.
    case unavailable
    /// The session can't be refreshed, or the API rejected a fresh token.
    case signedOut
    case unknown

    var message: String {
        switch self {
        case .invalidEmail: "Enter a valid email address."
        case .emailNotAllowed: "Codes can't be sent to this address yet. Only test addresses can sign in for now."
        case .wrongCode: "That code is wrong or has expired. Check it, or send a new one."
        case .tooManyCodes: "Too many codes sent. Wait a few minutes and try again."
        #if DEBUG
        case .testUserRejected:
            "Supabase rejected the test user. Check Config/Secrets.xcconfig and that the user is confirmed."
        #endif
        case .connection: "Couldn't connect. Check your connection and try again."
        case .unavailable: "Sign-in is unavailable, try again later."
        case .signedOut: "You were signed out. Sign in again."
        case .unknown: "Something went wrong. Try again."
        }
    }
}

/// Why deleting the account failed. You're still signed in, and except for
/// `unconfirmed`, nothing was deleted.
enum DeleteAccountError: Error, Equatable {
    /// 503: the API couldn't delete it right now.
    case unavailable
    /// The request never reached the API.
    case connection
    /// The connection failed after the request may have reached the API, so the
    /// account may be gone. Retrying is safe: a second delete is also a 204.
    case unconfirmed
    case unknown

    init(_ error: Error) {
        if let error = error as? URLError {
            self = Self.neverSent.contains(error.code) ? .connection : .unconfirmed
            return
        }
        switch AccountStore.signInError(error) {
        case .unavailable: self = .unavailable
        case .connection: self = .connection
        default: self = .unknown
        }
    }

    /// Yellow for what's on our side or the connection's, like `SignInError`.
    var isWarning: Bool { self != .unknown }

    /// URL errors that mean the request couldn't have been sent.
    private static let neverSent: Set<URLError.Code> = [
        .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
        .dataNotAllowed, .internationalRoamingOff, .secureConnectionFailed,
    ]

    var message: String {
        switch self {
        case .unavailable: "Couldn't delete your account right now. Nothing was deleted; try again later."
        case .connection: "Couldn't connect, so nothing was deleted. Check your connection and try again."
        case .unconfirmed: "We couldn't confirm your account was deleted. Check your connection and try again."
        case .unknown: "Something went wrong, so nothing was deleted. Try again."
        }
    }
}
