//
//  Toast.swift
//  FPL
//

import SwiftUI

/// A short message just above the tab bar, with an optional action such as Undo.
/// Each screen owns its own: `@State var toast: Toast?` and `.toast($toast)`.
struct Toast: Identifiable, Equatable, Sendable {
    enum Style: Sendable {
        case info, success, warning, error
    }

    /// A trailing button. Tapping it runs the handler and dismisses the toast.
    struct Action: Sendable {
        let label: String
        let handler: @MainActor () -> Void

        init(_ label: String, handler: @escaping @MainActor () -> Void) {
            self.label = label
            self.handler = handler
        }
    }

    let id = UUID()
    let message: String
    let style: Style
    let action: Action?
    /// nil shows it for the default time.
    let duration: Duration?

    init(_ message: String, style: Style = .info, action: Action? = nil, duration: Duration? = nil) {
        self.message = message
        self.style = style
        self.action = action
        self.duration = duration
    }

    /// 3 seconds, or 5 with an action, which takes time to notice and reach.
    var displayDuration: Duration {
        duration ?? .seconds(action == nil ? 3 : 5)
    }

    /// What VoiceOver reads as it appears: "Note deleted. Undo available."
    var announcement: String {
        guard let action else { return message }
        return "\(message). \(action.label) available."
    }

    static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
}

extension Binding<Toast?> {
    /// Clears `shown` only: a newer toast stays.
    func dismiss(_ shown: Toast) {
        if wrappedValue?.id == shown.id { wrappedValue = nil }
    }

    /// Runs `shown`'s action, then dismisses it. A toast the action shows stays.
    @MainActor func perform(_ shown: Toast) {
        shown.action?.handler()
        dismiss(shown)
    }
}

extension View {
    /// Shows `toast` while it's set, and clears it after its time, a tap or its action.
    /// A new one replaces the one showing and restarts the time.
    func toast(_ toast: Binding<Toast?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var toast: Toast?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.tabBarClearance) private var tabBarClearance

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast {
                    ToastView(toast: toast) {
                        $toast.dismiss(toast)
                    } onAction: {
                        $toast.perform(toast)
                    }
                    .padding(.horizontal, 16)
                    // Screens run under the tab bar, so sit just above it.
                    .padding(.bottom, tabBarClearance + 4)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast.id) {
                        AccessibilityNotification.Announcement(toast.announcement).post()
                        try? await Task.sleep(for: toast.displayDuration)
                        guard !Task.isCancelled else { return }
                        $toast.dismiss(toast)
                    }
                }
            }
            .animation(.easeOut(duration: 0.25), value: toast?.id)
    }
}

private struct ToastView: View {
    let toast: Toast
    let onTap: () -> Void
    let onAction: () -> Void

    private var icon: String {
        switch toast.style {
        case .info: "info.circle"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch toast.style {
        case .info: Theme.secondaryText
        case .success: Theme.accent
        case .warning: Theme.warning
        case .error: Theme.danger
        }
    }

    private var border: Color {
        toast.style == .info ? Theme.border : color.opacity(0.5)
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                        .accessibilityHidden(true)
                    Text(toast.message)
                        .font(.subheadline)
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Dismisses the message")

            if let action = toast.action {
                Button(action.label, action: onAction)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, toast.action == nil ? 16 : 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(border)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }
}
