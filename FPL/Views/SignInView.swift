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
    @EnvironmentObject private var noteSync: NoteSync
    @Environment(\.dismiss) private var dismiss
    /// Signed in, and asking about this iPhone's notes before closing.
    @State private var isOffering = false

    /// The offer once this sheet has signed in. Nil again if the session ends
    /// before it's answered, which brings back Cancel.
    private var offer: Int? { isOffering ? noteSync.uploadOffer : nil }

    var body: some View {
        NavigationStack {
            Group {
                if let count = offer {
                    UploadOffer(count: count) { keep in
                        if keep {
                            noteSync.keepDeviceNotesInAccount()
                        } else {
                            noteSync.keepDeviceNotesOnDevice()
                        }
                        dismiss()
                    }
                } else {
                    SignInForm(account: account, reason: reason) {
                        if noteSync.uploadOffer != nil { isOffering = true } else { dismiss() }
                    }
                }
            }
            .themedScreen()
            .navigationTitle(offer == nil ? "Sign in" : "Your notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if offer == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .presentationBackground(Theme.background)
        // Both answers are buttons, so swiping away can't leave it unanswered.
        .interactiveDismissDisabled(offer != nil)
    }
}

/// After signing in on an iPhone that has notes: keep them in the account, so
/// they sync, or only on this iPhone. Asked once per sign-in.
private struct UploadOffer: View {
    let count: Int
    let onAnswer: (_ keepInAccount: Bool) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(count == 1 ? "Keep this note in your account?" : "Keep these \(count) notes in your account?")
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(count == 1
                         ? "You're signed in. Your note is only on this iPhone. In your account, it syncs to your other devices."
                         : "You're signed in. Your notes are only on this iPhone. In your account, they sync to your other devices.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 12) {
                    Button {
                        onAnswer(true)
                    } label: {
                        Text("Keep in account").frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        onAnswer(false)
                    } label: {
                        Text("Only on this iPhone").frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
        }
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

            #if DEBUG
            if let testUser = TestUser.configured() {
                testUserButton(testUser)
            }
            #endif
        }
    }

    #if DEBUG
    /// Debug builds pointed at staging with test credentials set: signs in without a code.
    private func testUserButton(_ user: TestUser) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task {
                    if await model.signIn(as: user) { onSignedIn() }
                }
            } label: {
                Text("Sign in as test user").frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.bordered)
            .disabled(model.isWorking)
            if let error = model.testUserError {
                ErrorLine(error: error)
            } else {
                Text("Debug only: \(user.email) on staging, no code needed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
    #endif

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
    let message: String
    /// Yellow for what's on our side, red for what you can fix.
    let isWarning: Bool

    init(message: String, isWarning: Bool) {
        self.message = message
        self.isWarning = isWarning
    }

    init(error: SignInError) {
        self.init(message: error.message, isWarning: error == .connection || error == .unavailable)
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
    @EnvironmentObject private var noteSync: NoteSync
    @State private var isSigningIn = false
    @State private var confirmingSignOut = false
    @State private var confirmingDelete = false

    static let reason = "Sign in to sync your notes and follow teams"

    var body: some View {
        // The sheet and dialog hang off the whole card, not one state's version of
        // it, so they aren't torn down when signing in or out swaps the content.
        Group {
            switch account.state {
            case .unavailable:
                EmptyView()
            case .deleting:
                card {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Deleting your account…")
                            .font(.subheadline)
                    }
                    .accessibilityElement(children: .combine)
                }
            case .signedOut:
                card {
                    if account.accountDeleted {
                        Label("Your account was deleted.", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                    }
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
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Text("Delete account").frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    if let error = account.deleteError {
                        ErrorLine(message: error.message, isWarning: error.isWarning)
                    }
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
                Text(Self.signOutMessage(email: email, unsynced: noteSync.pendingCount))
            }
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                Task { await account.deleteAccount() }
            }
        } message: {
            Text(Self.deleteMessage)
        }
        .onChange(of: confirmingSignOut) { _, isShowing in
            // One last try, so the warning about unsynced changes is only shown when it's real.
            if isShowing { Task { await noteSync.flush() } }
        }
        .onChange(of: account.state) {
            confirmingSignOut = false
            confirmingDelete = false
        }
    }

    static let deleteMessage = "This deletes your account, your synced notes and the teams you follow. "
        + "Your FPL teams aren't affected."

    nonisolated static func signOutMessage(email: String, unsynced: Int) -> String {
        var message = "Your synced notes leave this iPhone until you sign in again, "
            + "which needs a new code sent to \(email)."
        switch unsynced {
        case 0: break
        case 1: message += " 1 change hasn't synced yet and will be lost."
        default: message += " \(unsynced) changes haven't synced yet and will be lost."
        }
        return message
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
