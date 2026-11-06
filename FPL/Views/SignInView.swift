//
//  SignInView.swift
//  FPL
//

import SwiftUI

/// The sign-in sheet: an email address, then the 6-digit code sent to it.
/// Open it from an action that needs an account, with `reason` saying what for.
struct SignInView: View {
    let reason: String

    @EnvironmentObject private var account: AccountStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SignInForm(account: account, reason: reason) { dismiss() }
                .themedScreen()
                .navigationTitle("Sign in")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .presentationBackground(Theme.background)
    }
}

private struct SignInForm: View {
    let reason: String
    let onSignedIn: () -> Void

    @StateObject private var model: SignInModel
    @FocusState private var focused: Field?

    private enum Field { case email, code }

    init(account: AccountStore, reason: String, onSignedIn: @escaping () -> Void) {
        self.reason = reason
        self.onSignedIn = onSignedIn
        _model = StateObject(wrappedValue: SignInModel(account: account))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(reason)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                // Sign in with Apple goes here, above the email field.

                switch model.step {
                case .email: emailStep
                case .code(let email): codeStep(email: email)
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { focused = .email }
        .onChange(of: model.step) { _, step in
            focused = step == .email ? .email : .code
        }
        .onChange(of: model.codeText) { _, _ in
            if model.isCodeComplete { verify() }
        }
    }

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Email", text: $model.emailText)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .onSubmit { Task { await model.sendCode() } }
                    .focused($focused, equals: .email)
                    .modifier(FieldStyle(isError: model.error != nil))

                if let error = model.error {
                    ErrorLine(error: error)
                } else {
                    Text("We'll email you a 6-digit code. There's no password.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                Task { await model.sendCode() }
            } label: {
                ButtonLabel(title: "Send code", isWorking: model.isWorking)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.emailText.isEmpty || model.isWorking)
        }
    }

    private func codeStep(email: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Enter the 6-digit code sent to \(email). It expires after 10 minutes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("6-digit code", text: $model.codeText)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.title2.monospacedDigit())
                    .focused($focused, equals: .code)
                    .modifier(FieldStyle(isError: model.error != nil))

                if let error = model.error {
                    ErrorLine(error: error)
                }
            }

            Button(action: verify) {
                ButtonLabel(title: "Sign in", isWorking: model.isWorking)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.isCodeComplete || model.isWorking)

            HStack {
                Button("Use a different email") { model.changeEmail() }
                Spacer()
                // Ticks once a second so the countdown updates.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = model.canResendAt.map { Int($0.timeIntervalSince(context.date).rounded(.up)) } ?? 0
                    Button(remaining > 0 ? "Resend in \(remaining)s" : "Resend code") {
                        Task { await model.resend() }
                    }
                    .disabled(remaining > 0 || model.isWorking)
                    .monospacedDigit()
                }
            }
            .font(.subheadline)
        }
    }

    private func verify() {
        Task {
            if await model.verify() { onSignedIn() }
        }
    }
}

private struct FieldStyle: ViewModifier {
    let isError: Bool

    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isError ? Theme.danger : Theme.border)
            }
    }
}

private struct ErrorLine: View {
    let error: SignInError

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .accessibilityHidden(true)
            Text(error.message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        // Red for what you can fix, yellow for what's on our side.
        .foregroundStyle(error == .connection || error == .unavailable ? Theme.warning : Theme.danger)
    }
}

private struct ButtonLabel: View {
    let title: String
    let isWorking: Bool

    var body: some View {
        Group {
            if isWorking {
                ProgressView().tint(Theme.onAccent)
            } else {
                Text(title)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 32)
    }
}

/// Profile's Account card: an invitation to sign in, or who you're signed in
/// as and Sign out. Hidden when the build has no sign-in.
struct AccountCard: View {
    @EnvironmentObject private var account: AccountStore
    @State private var isSigningIn = false
    @State private var confirmingSignOut = false

    static let reason = "Sign in to sync your notes and follow teams"

    var body: some View {
        // The sheet and dialog hang off the whole card, not one state's version of
        // it, so they aren't torn down when signing in or out swaps the content.
        Group {
            switch account.state {
            case .unavailable:
                EmptyView()
            case .signedOut:
                card {
                    Text("\(Self.reason). Everything else works without an account.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let reason = account.signedOutReason {
                        ErrorLine(error: reason)
                    }
                    Button {
                        isSigningIn = true
                    } label: {
                        Text("Sign in").frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .signedIn(let email, _):
                card {
                    Text("Signed in as \(email)")
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        confirmingSignOut = true
                    } label: {
                        Text("Sign out").frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .sheet(isPresented: $isSigningIn) {
            SignInView(reason: Self.reason)
        }
        .confirmationDialog("Sign out?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                Task { await account.signOut() }
            }
        } message: {
            if case .signedIn(let email, _) = account.state {
                Text("To sign in again, you'll need a new code sent to \(email).")
            }
        }
        .onChange(of: account.state) {
            confirmingSignOut = false
        }
    }

    private func card(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACCOUNT")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
