//
//  TransferPromptView.swift
//  FPL
//

import SwiftData
import SwiftUI

/// Asks why you made your new transfers: one card per transfer, each with an
/// optional note, and one Save. "Later" saves the transfers without notes so
/// they can be written from the Notes tab.
struct TransferPromptView: View {
    let transfers: [NamedTransfer]
    /// Called after the notes are saved, either way.
    let onFinish: () -> Void

    @Environment(\.modelContext) private var context
    /// Note text per transfer id.
    @State private var texts: [String: String] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(transfers.count == 1
                         ? "Write down why you made it, so you can check your reasoning before you sell."
                         : "Write down why you made them, so you can check your reasoning before you sell. Notes are optional.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(transfers) { pending in
                        TransferCard(transfer: pending.noteTransfer, gameweek: pending.transfer.event,
                                     text: binding(for: pending.id))
                    }
                }
                .padding(16)
            }
            .themedScreen()
            .navigationTitle(transfers.count == 1 ? "New transfer" : "\(transfers.count) new transfers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { save() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
        .presentationBackground(Theme.background)
        // Swiping away would lose the transfers; Later and Save both keep them.
        .interactiveDismissDisabled()
    }

    private func binding(for id: String) -> Binding<String> {
        Binding { texts[id, default: ""] } set: { texts[id] = $0 }
    }

    /// Saves a note for every transfer, with or without text, so a skipped one
    /// shows on the Notes tab ready to be written.
    private func save() {
        for pending in transfers {
            let text = texts[pending.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            context.insert(Note(text: text,
                                gameweek: pending.transfer.event,
                                players: [pending.noteTransfer.playerIn],
                                transfer: pending.noteTransfer,
                                createdAt: pending.transfer.time))
        }
        onFinish()
    }
}

/// One transfer: who came in (with the price), who went out, and the note field.
private struct TransferCard: View {
    let transfer: NoteTransfer
    let gameweek: Int
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("GAMEWEEK \(gameweek)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TransferLine(transfer: transfer)
            }

            TextField("Why did you bring in \(transfer.playerIn.webName)?", text: $text, axis: .vertical)
                .lineLimit(3...8)
                .padding(10)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// "IN Isak £8.6m" over "OUT Watkins £8.0m", shared by the prompt, notes and the editor.
struct TransferLine: View {
    let transfer: NoteTransfer

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row("IN", transfer.playerIn.webName, color: Theme.accent, detail: money(transfer.cost))
            row("OUT", transfer.playerOut.webName, color: Theme.danger, detail: money(transfer.outCost))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(transfer.playerIn.webName) in, \(transfer.playerOut.webName) out")
    }

    private func money(_ tenths: Int?) -> String? {
        tenths.map { String(format: "£%.1fm", Double($0) / 10) }
    }

    private func row(_ tag: String, _ name: String, color: Color, detail: String?) -> some View {
        HStack(spacing: 8) {
            Text(tag)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 30, alignment: .leading)
            Text(name)
                .font(.subheadline.weight(.semibold))
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
