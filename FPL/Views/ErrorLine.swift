//
//  ErrorLine.swift
//  FPL
//

import SwiftUI

/// An error under a field or button: yellow for what's on our side or the
/// connection's, red for what you can fix.
struct ErrorLine: View {
    let message: String
    let isWarning: Bool

    init(message: String, isWarning: Bool) {
        self.message = message
        self.isWarning = isWarning
    }

    init(error: SignInError) {
        self.init(message: error.message, isWarning: error == .connection || error == .unavailable)
    }

    init(error: TeamError) {
        self.init(message: error.message, isWarning: error == .fplUnavailable || error == .connection)
    }

    init(error: LinkError) {
        self.init(message: error.message, isWarning: error != .notFound)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .accessibilityHidden(true)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .foregroundStyle(isWarning ? Theme.warning : Theme.danger)
    }
}
