//
//  LinkTeamForm.swift
//  FPL
//

import SwiftUI

/// What the ID lookup is for: the wording, and what confirming does.
enum TeamLookupPurpose {
    /// The first team on this device.
    case link
    /// Signed out: replaces the linked team.
    case change
    /// Signed in: another of your teams.
    case add
    /// Someone else's team, to follow.
    case follow

    var title: String {
        switch self {
        case .link: "Link your FPL team"
        case .change: "Change team"
        case .add: "Add another team"
        case .follow: "Follow a team"
        }
    }

    var blurb: String {
        switch self {
        case .link, .change: "The app reads your transfers so it can ask why you made them. You don't need to sign in."
        case .add: "Add another team you run. You can switch between your teams from the team card's menu."
        case .follow: "Follow any FPL team by its ID. Its manager doesn't need the app."
        }
    }

    var question: String { self == .follow ? "IS THIS THE TEAM?" : "IS THIS YOUR TEAM?" }
    var confirm: String { self == .follow ? "Follow" : self == .add ? "Add team" : "Link team" }
    var reject: String { self == .follow ? "Not this team" : "Not my team" }
}

/// Enter a manager ID, look the team up, and confirm it.
struct LinkTeamForm: View {
    let purpose: TeamLookupPurpose
    /// Why confirming failed, shown under the field.
    var error: TeamError?
    /// While confirming, the confirm button waits.
    var isWorking = false
    /// Shown as a Cancel button when changing an existing link.
    let onCancel: (() -> Void)?
    let onLink: (Manager) -> Void

    @StateObject private var model = LinkTeamModel()
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(purpose.title)
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text(purpose.blurb)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("Manager ID", text: $model.idText)
                    .keyboardType(.numberPad)
                    .autocorrectionDisabled()
                    .font(.title3.monospacedDigit())
                    .focused($isFieldFocused)
                    .padding(12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isError ? Theme.danger : Theme.border)
                    }
                    .accessibilityHint("Digits only")

                if case .failed(let error) = model.state {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .accessibilityHidden(true)
                        Text(error.message)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.footnote)
                    .foregroundStyle(error == .notFound ? Theme.danger : Theme.warning)
                } else if let error {
                    TeamErrorLine(error: error)
                } else {
                    Text("""
                        On the FPL website, open your team's Points page. Your ID is the number after \
                        /entry/ in the address, e.g. fantasy.premierleague.com/entry/**1234567**/event/9.
                        """)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if case .found(let manager) = model.state {
                ConfirmTeamCard(manager: manager, purpose: purpose, isWorking: isWorking) {
                    onLink(manager)
                } onReject: {
                    model.reject()
                    isFieldFocused = true
                }
            } else {
                Button {
                    isFieldFocused = false
                    Task { await model.lookUp() }
                } label: {
                    Group {
                        if model.state == .loading {
                            ProgressView().tint(Theme.onAccent)
                        } else {
                            Text(buttonTitle)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.managerID == nil || model.state == .loading)
            }

            if let onCancel {
                Button("Cancel", action: onCancel)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var isError: Bool {
        if case .failed = model.state { return true }
        return false
    }

    /// "Try again" after a failure that retrying could fix.
    private var buttonTitle: String {
        if case .failed(let error) = model.state, error.canRetry { return "Try again" }
        return "Find team"
    }
}

/// "Is this your team?" with the team name, points and rank, before saving the link.
private struct ConfirmTeamCard: View {
    let manager: Manager
    let purpose: TeamLookupPurpose
    let isWorking: Bool
    let onConfirm: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(purpose.question)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(manager.name)
                    .font(.title3.weight(.bold))
                Text(details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 8) {
                Button(action: onReject) {
                    Text(purpose.reject).frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.bordered)

                Button(action: onConfirm) {
                    Group {
                        if isWorking {
                            ProgressView().tint(Theme.onAccent)
                        } else {
                            Text(purpose.confirm)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.6))
        }
    }

    /// e.g. "563 pts · Rank 1,571,477", or "ID 1" for a team with neither yet.
    private var details: String {
        var parts: [String] = []
        if let points = manager.summaryOverallPoints { parts.append("\(points.formatted()) pts") }
        if let rank = manager.summaryOverallRank { parts.append("Rank \(rank.formatted())") }
        return parts.isEmpty ? "ID \(String(manager.id))" : parts.joined(separator: " · ")
    }
}
