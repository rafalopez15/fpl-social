//
//  Toast.swift
//  FPL
//

import SwiftUI

/// A short message that slides in at the top of a screen for 3 seconds. A new
/// one replaces the one showing, and restarts the time.
struct Toast: Equatable, Identifiable {
    let id = UUID()
    let message: String
}

extension View {
    /// Shows `toast` while it's set, and clears it after 3 seconds or a tap.
    func toast(_ toast: Binding<Toast?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var toast: Toast?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast {
                    ToastView(message: toast.message) { dismiss(toast) }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        .task(id: toast.id) {
                            AccessibilityNotification.Announcement(toast.message).post()
                            try? await Task.sleep(for: .seconds(3))
                            dismiss(toast)
                        }
                }
            }
            .animation(.easeOut(duration: 0.25), value: toast?.id)
    }

    /// Only this one: a newer toast stays.
    private func dismiss(_ shown: Toast) {
        if toast?.id == shown.id { toast = nil }
    }
}

private struct ToastView: View {
    let message: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warning)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.warning.opacity(0.5))
            }
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Dismisses the message")
    }
}
