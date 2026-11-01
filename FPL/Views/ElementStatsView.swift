//
//  ElementStatsView.swift
//  FPL
//

import SwiftUI

/// Season and advanced stats for one player, shown in a popover from the list.
struct ElementStatsView: View {
    let element: Element
    let team: Team?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(element.fullName)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if element.status.isFlagged || element.currentNews != nil {
                NewsCallout(element: element)
            }

            StatSection(title: "Season", stats: [
                ("Minutes", int(element.minutes)),
                ("Starts", int(element.starts)),
                ("Goals", int(element.goalsScored)),
                ("Assists", int(element.assists)),
                ("Clean sheets", int(element.cleanSheets)),
                ("Goals conceded", int(element.goalsConceded)),
                ("Saves", int(element.saves)),
                ("Bonus", int(element.bonus)),
                ("Yellow cards", int(element.yellowCards)),
                ("Red cards", int(element.redCards)),
            ])

            StatSection(title: "Advanced", stats: [
                ("xG", decimal(element.expectedGoals, places: 2)),
                ("xA", decimal(element.expectedAssists, places: 2)),
                ("xGI", decimal(element.expectedGoalInvolvements, places: 2)),
                ("xGC", decimal(element.expectedGoalsConceded, places: 2)),
                ("ICT index", decimal(element.ictIndex, places: 1)),
            ])
        }
        .padding()
        .frame(width: 300)
    }

    /// e.g. "Forward · Man City · Selected by 46.3%"
    private var subtitle: String {
        [
            element.position?.singularTitle,
            team?.name,
            element.selectedByPercent.map { String(format: "Selected by %.1f%%", $0) },
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private func int(_ value: Int?) -> String {
        value.map(String.init) ?? "–"
    }

    private func decimal(_ value: Double?, places: Int) -> String {
        value.map { String(format: "%.\(places)f", $0) } ?? "–"
    }
}

/// Injury or availability news, yellow with a hazard icon when the player is flagged.
private struct NewsCallout: View {
    let element: Element

    private var isFlagged: Bool { element.status.isFlagged }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: isFlagged ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(isFlagged ? Theme.warning : Theme.secondaryText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(element.currentNews ?? element.status.title)
                    .foregroundStyle(isFlagged ? Theme.warning : Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let added = element.newsAdded {
                    Text("Updated \(added, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.subheadline)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A titled two-column grid of label/value pairs.
private struct StatSection: View {
    let title: String
    let stats: [(label: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                ForEach(Array(stride(from: 0, to: stats.count, by: 2)), id: \.self) { index in
                    GridRow {
                        cell(stats[index])
                        if index + 1 < stats.count {
                            cell(stats[index + 1])
                        }
                    }
                }
            }
            .font(.subheadline)
        }
    }

    @ViewBuilder
    private func cell(_ stat: (label: String, value: String)) -> some View {
        Text(stat.label)
            .foregroundStyle(.secondary)
        Text(stat.value)
            .monospacedDigit()
            .fontWeight(.semibold)
            .gridColumnAlignment(.trailing)
    }
}
