//
//  FeedView.swift
//  FPL
//

import SwiftUI

/// The Feed tab: friends' activity timeline. Placeholder until FPL-15.
struct FeedView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("No activity yet", systemImage: "house")
            } description: {
                Text("Transfers, posts and highlights from friends you follow will show up here.")
            }
            .themedScreen()
            .navigationTitle("Feed")
        }
    }
}

#Preview {
    FeedView()
}
