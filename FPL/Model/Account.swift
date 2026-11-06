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
        case .connection: "Couldn't connect. Check your connection and try again."
        case .unavailable: "Sign-in is unavailable, try again later."
        case .signedOut: "You were signed out. Sign in again."
        case .unknown: "Something went wrong. Try again."
        }
    }
}
