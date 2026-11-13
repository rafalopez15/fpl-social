//
//  ToastTests.swift
//  FPLTests
//

import SwiftUI
import Testing
@testable import FPL

@MainActor
struct ToastTests {
    /// Stands in for a screen's `@State var toast`.
    final class Screen {
        var toast: Toast?
        var undone = 0
        var binding: Binding<Toast?> {
            Binding { self.toast } set: { self.toast = $0 }
        }
    }

    @Test func showsForThreeSecondsOrFiveWithAnAction() {
        #expect(Toast("Refresh failed").displayDuration(voiceOver: false) == .seconds(3))
        #expect(Toast("Note deleted", action: .init("Undo") {}).displayDuration(voiceOver: false) == .seconds(5))
        #expect(Toast("Saved", duration: .seconds(1)).displayDuration(voiceOver: false) == .seconds(1))
    }

    @Test func voiceOverGetsLongerToReachAnAction() {
        #expect(Toast("Note deleted", action: .init("Undo") {}).displayDuration(voiceOver: true) == .seconds(30))
        // Nothing to reach without an action, and an explicit time is kept.
        #expect(Toast("Refresh failed").displayDuration(voiceOver: true) == .seconds(3))
        #expect(Toast("Saved", action: .init("View") {}, duration: .seconds(8)).displayDuration(voiceOver: true) == .seconds(8))
    }

    @Test func voiceOverHearsTheMessageAndTheAction() {
        #expect(Toast("Refresh failed", style: .warning).announcement == "Refresh failed")
        #expect(Toast("Note deleted", action: .init("Undo") {}).announcement == "Note deleted. Undo available.")
    }

    @Test func aNewToastReplacesTheOneShowing() {
        let screen = Screen()
        let first = Toast("Note deleted")
        let second = Toast("Note deleted")
        screen.toast = first
        screen.toast = second
        #expect(first != second)

        // The first one's time running out doesn't clear the second.
        screen.binding.dismiss(first)
        #expect(screen.toast == second)
        screen.binding.dismiss(second)
        #expect(screen.toast == nil)
    }

    @Test func theActionRunsAndDismissesTheToast() {
        let screen = Screen()
        let toast = Toast("Note deleted", action: .init("Undo") { screen.undone += 1 })
        screen.toast = toast
        screen.binding.perform(toast)
        #expect(screen.undone == 1)
        #expect(screen.toast == nil)
    }

    @Test func aToastShownByTheActionStays() {
        let screen = Screen()
        let next = Toast("Couldn't undo", style: .error)
        let toast = Toast("Note deleted", action: .init("Undo") { screen.toast = next })
        screen.toast = toast
        screen.binding.perform(toast)
        #expect(screen.toast == next)
    }
}
