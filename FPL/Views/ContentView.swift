//
//  ContentView.swift
//  FPL
//
//  Created by Rafael Lopez on 11/4/24.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ElementViewModel()
    
    var body: some View {
        NavigationView {
            if viewModel.isLoading {
                ProgressView("Loading...")
                    .progressViewStyle(CircularProgressViewStyle())
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            } else {
                List(viewModel.filteredElements) { element in
                    VStack(alignment: .leading) {
                        let points = String(element.totalPoints)
                        
                        Text(element.fullName)
                            .font(.headline)
                        Text(points)
                            .font(.footnote)
                            .foregroundColor(.primary)
                    }
                }
                .navigationTitle("Forwards")
                //.searchable(text: $viewModel.searchQuery, prompt: "Search forwards")
            }
        }
        .onAppear {
            viewModel.fetchElements()
        }
    }
}

// Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
