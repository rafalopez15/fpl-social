//
//  Mention.swift
//  FPL
//

import SwiftUI

/// Linking a player by typing @ and part of his name in a note. The note keeps
/// plain text ("@Saka"); the link is the `NotePlayer`, and highlighting is worked
/// out from the two when the note is shown.
enum Mention {
    /// The "@sak" being typed, from the @ up to the cursor.
    struct Query: Equatable {
        /// Includes the @.
        let range: Range<String.Index>
        /// What follows the @.
        let text: String
    }

    /// Longer than any name, so an @ earlier in the note stops suggesting.
    static let maxQueryLength = 20

    /// The mention being typed just before `cursor`, if any. The @ must start the
    /// note or follow a space or new line, so an email address isn't one.
    nonisolated static func query(in text: String, cursor: String.Index) -> Query? {
        guard cursor <= text.endIndex else { return nil }
        let before = text[..<cursor]
        guard let at = before.lastIndex(of: "@") else { return nil }
        if at > text.startIndex, !text[text.index(before: at)].isWhitespace { return nil }
        let typed = before[before.index(after: at)...]
        guard typed.count <= maxQueryLength, !typed.contains(where: \.isNewline) else { return nil }
        return Query(range: at..<cursor, text: String(typed))
    }

    /// `text` with the query replaced by "@Name " (no extra space if one follows),
    /// and the cursor just after it.
    nonisolated static func inserting(_ name: String, for query: Query, in text: String) -> (text: String, cursor: String.Index) {
        let followedBySpace = query.range.upperBound < text.endIndex && text[query.range.upperBound].isWhitespace
        let mention = "@\(name)" + (followedBySpace ? "" : " ")
        let offset = text.distance(from: text.startIndex, to: query.range.lowerBound) + mention.count
        var result = text
        result.replaceSubrange(query.range, with: mention)
        return (result, result.index(result.startIndex, offsetBy: offset + (followedBySpace ? 1 : 0)))
    }

    /// Where "@Name" appears for a linked player, not followed by a letter or digit.
    /// Longer names win, so "@Gabriel Martinelli" isn't cut short by "@Gabriel".
    nonisolated static func ranges(in text: String, linked: [NotePlayer]) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        for name in Set(linked.map(\.webName)).sorted(by: { $0.count > $1.count }) {
            var start = text.startIndex
            while let range = text.range(of: "@\(name)", range: start..<text.endIndex) {
                start = range.upperBound
                let atBoundary = range.upperBound == text.endIndex
                    || !(text[range.upperBound].isLetter || text[range.upperBound].isNumber)
                if atBoundary, !found.contains(where: { $0.overlaps(range) }) { found.append(range) }
            }
        }
        return found.sorted { $0.lowerBound < $1.lowerBound }
    }

    /// The note's text with linked players' mentions in the accent color and bold.
    nonisolated static func highlighted(_ text: String, linked: [NotePlayer]) -> AttributedString {
        var attributed = AttributedString(text)
        for range in ranges(in: text, linked: linked) {
            guard let span = Range(range, in: attributed) else { continue }
            attributed[span].foregroundColor = Theme.accent
            attributed[span].inlinePresentationIntent = .stronglyEmphasized
        }
        return attributed
    }

    /// For matching what's typed: lower case, accents and letters like ß or Ø made plain.
    nonisolated static func folded(_ string: String) -> String {
        string.applyingTransform(StringTransform("Latin-ASCII; Lower"), reverse: false) ?? string.lowercased()
    }
}
