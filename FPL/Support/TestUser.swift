//
//  TestUser.swift
//  FPL
//

#if DEBUG
import Foundation

/// Staging's password test user, for one-tap sign-in on Debug builds. The
/// credentials come from the gitignored `Config/Secrets.xcconfig` via Info.plist.
struct TestUser: Equatable {
    let email: String
    let password: String

    /// Staging's Supabase project, the only one the test user exists in.
    static let stagingHost = "ltasgegihkapmdqlkaov.supabase.co"

    /// Nil unless both credentials are set, the app signs in with staging, and the
    /// API isn't production, which rejects staging's tokens.
    static func configured(info: [String: Any] = Bundle.main.infoDictionary ?? [:],
                           apiBaseURL: URL = FPLAPIClient.configuredBaseURL) -> TestUser? {
        guard apiBaseURL != FPLAPIClient.productionBaseURL,
              let email = info["TestUserEmail"] as? String, !email.isEmpty,
              let password = info["TestUserPassword"] as? String, !password.isEmpty,
              let url = (info["SupabaseURL"] as? String).flatMap(URL.init(string:)),
              url.host() == stagingHost
        else { return nil }
        return TestUser(email: email, password: password)
    }
}
#endif
