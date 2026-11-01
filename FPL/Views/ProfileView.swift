//
//  ProfileView.swift
//  FPL
//

import SwiftUI

/// The Profile tab: your account and linked FPL team. Placeholder until FPL-9 and FPL-11.
struct ProfileView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Not signed in", systemImage: "person.crop.circle")
            } description: {
                Text("Sign in and link your FPL team to share activity with friends.")
            }
            .themedScreen()
            .navigationTitle("Profile")
        }
    }
}

#Preview {
    ProfileView()
}
