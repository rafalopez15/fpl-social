//
//  NotesView.swift
//  FPL
//

import SwiftUI

/// The Notes tab: your transfer notes grouped by gameweek. Placeholder until FPL-14.
struct NotesView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("No notes yet", systemImage: "note.text")
            } description: {
                Text("Write down why you made a transfer, so you can check your reasoning before you sell.")
            }
            .themedScreen()
            .navigationTitle("Notes")
        }
    }
}

#Preview {
    NotesView()
}
