//
//  ElementViewModel.swift
//  FPL
//
//  Created by Rafael Lopez on 12/3/24.
//

import Foundation

class ElementViewModel: ObservableObject {
    @Published var elements: [Element] = []
    @Published var sortedElements: [Element] = []
    @Published var isLoading: Bool = true
    @Published var errorMessage: String? = nil
    @Published var searchQuery: String = ""
    
    func fetchElements() {
        guard let url = URL(string: "http://127.0.0.1:5000/api/elements/position/4") else { return }
        
        isLoading = true
        errorMessage = nil
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.errorMessage = "Error fetching elements: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self?.errorMessage = "No data returned from server"
                    return
                }
                
                var decodedData: [Element] = []
                do {
                    decodedData = try JSONDecoder().decode([Element].self, from: data)
                } catch {
                    self?.errorMessage = "Error decoding elements: \(error.localizedDescription)"
                }
                self?.elements = decodedData
                self?.sortedElements = decodedData.sorted { $0.totalPoints > $1.totalPoints }
            }
        }.resume()
    }
    
    var filteredElements: [Element] {
            if searchQuery.isEmpty {
                return sortedElements
            } else {
                return elements.filter { $0.fullName.localizedCaseInsensitiveContains(searchQuery) }
            }
    }
}
