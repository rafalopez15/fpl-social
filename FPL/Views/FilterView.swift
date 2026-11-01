//
//  FilterView.swift
//  FPL
//

import SwiftUI

/// Sort and filter controls for the player list, shown as a sheet.
struct FilterView: View {
    @ObservedObject var viewModel: ElementViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Sort") {
                    Picker("Sort by", selection: $viewModel.sort) {
                        ForEach(ElementSort.allCases) { sort in
                            Text(sort.title).tag(sort)
                        }
                    }
                    Picker("Order", selection: $viewModel.sortAscending) {
                        Text("High to low").tag(false)
                        Text("Low to high").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                if let range = viewModel.priceRange {
                    Section("Max price") {
                        VStack(alignment: .leading) {
                            Text(viewModel.filter.maxPrice.map { String(format: "£%.1fm", $0) } ?? "Any")
                                .monospacedDigit()
                            Slider(value: maxPriceBinding(range: range), in: range, step: 0.1) {
                                Text("Max price")
                            } minimumValueLabel: {
                                Text(String(format: "£%.1f", range.lowerBound)).font(.caption)
                            } maximumValueLabel: {
                                Text(String(format: "£%.1f", range.upperBound)).font(.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { viewModel.resetFilters() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Slider at the top of the range means "no limit".
    private func maxPriceBinding(range: ClosedRange<Double>) -> Binding<Double> {
        Binding(
            get: { viewModel.filter.maxPrice ?? range.upperBound },
            set: { viewModel.filter.maxPrice = $0 >= range.upperBound - 0.001 ? nil : $0 }
        )
    }
}
