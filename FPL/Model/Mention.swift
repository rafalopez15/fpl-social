//
//  Mention.swift
//  FPL
//

import SwiftUI

/// The note keeps plain text ("@Saka"); the chip is the link.
enum Mention {
    struct Query: Equatable {
        /// Includes the @.
        let range: Range<String.Index>
        let text: String

        /// Return and Tab pick only after a letter, so @ then Return is a new line.
        var picksWithKeyboard: Bool { !text.trimmingCharacters(in: .whitespaces).isEmpty }

        /// Words after a mention ("@Saka is") match nobody, so they don't say so.
        var showsNoMatches: Bool { !text.contains(" ") }
    }

    /// Longer than any name, so an @ earlier in the note stops suggesting.
    static let maxQueryLength = 20

    /// The @ must start the note or follow whitespace, so an email address isn't one.
    /// A linked player's whole name ends it, but "@Gabriel M" still looks for Gabriel M.
    nonisolated static func query(in text: String, cursor: String.Index, linked: [NotePlayer] = []) -> Query? {
        guard cursor <= text.endIndex else { return nil }
        let before = text[..<cursor]
        guard let at = before.lastIndex(of: "@") else { return nil }
        if at > text.startIndex, !text[text.index(before: at)].isWhitespace { return nil }
        let typed = before[before.index(after: at)...]
        let name = typed.trimmingCharacters(in: .whitespaces)
        if linked.contains(where: { $0.webName == name }) { return nil }
        guard typed.count <= maxQueryLength, !typed.contains(where: \.isNewline) else { return nil }
        return Query(range: at..<cursor, text: String(typed))
    }

    /// No trailing space is added if one follows.
    nonisolated static func inserting(_ name: String, for query: Query, in text: String) -> (text: String, cursor: String.Index) {
        let followedBySpace = query.range.upperBound < text.endIndex && text[query.range.upperBound].isWhitespace
        let mention = "@\(name)" + (followedBySpace ? "" : " ")
        let offset = text.distance(from: text.startIndex, to: query.range.lowerBound) + mention.count
        var result = text
        result.replaceSubrange(query.range, with: mention)
        return (result, result.index(result.startIndex, offsetBy: offset + (followedBySpace ? 1 : 0)))
    }

    /// Whole names only. Longer names win, so "@Gabriel" doesn't cut "@Gabriel M." short.
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

    nonisolated static func highlighted(_ text: String, linked: [NotePlayer]) -> AttributedString {
        var attributed = AttributedString(text)
        for range in ranges(in: text, linked: linked) {
            guard let span = Range(range, in: attributed) else { continue }
            attributed[span].foregroundColor = Theme.accent
            attributed[span].inlinePresentationIntent = .stronglyEmphasized
        }
        return attributed
    }

    nonisolated static func mentionedIDs(in text: String, linked: [NotePlayer]) -> Set<Int> {
        let names = Set(ranges(in: text, linked: linked).map { String(text[$0].dropFirst()) })
        return Set(linked.filter { names.contains($0.webName) }.map(\.id))
    }

    struct Edit: Equatable {
        let text: String
        let linked: [NotePlayer]
        /// In characters. Nil when the text is left as typed.
        let cursor: Int?
    }

    /// As in Slack: deleting into "@Saka" removes it whole, and a player is unlinked
    /// once his last mention goes. Players never mentioned in the text never are.
    nonisolated static func applying(_ new: String, to old: String, linked: [NotePlayer]) -> Edit {
        let before = Array(old), after = Array(new)
        var prefix = 0
        while prefix < min(before.count, after.count), before[prefix] == after[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(before.count, after.count) - prefix,
              before[before.count - 1 - suffix] == after[after.count - 1 - suffix] { suffix += 1 }
        // before[prefix..<removedEnd] was replaced by `inserted`.
        let removedEnd = before.count - suffix
        let inserted = after[prefix..<(after.count - suffix)]

        var text = new
        var cursor: Int?
        if removedEnd > prefix {
            var lower = prefix, upper = removedEnd
            for range in ranges(in: old, linked: linked) {
                let start = old.distance(from: old.startIndex, to: range.lowerBound)
                let end = old.distance(from: old.startIndex, to: range.upperBound)
                if start < removedEnd && end > prefix {
                    lower = min(lower, start)
                    upper = max(upper, end)
                }
            }
            if lower != prefix || upper != removedEnd {
                text = String(before[..<lower]) + String(inserted) + String(before[upper...])
                cursor = lower + inserted.count
            }
        }
        let dropped = mentionedIDs(in: old, linked: linked).subtracting(mentionedIDs(in: text, linked: linked))
        return Edit(text: text, linked: linked.filter { !dropped.contains($0.id) }, cursor: cursor)
    }

    /// Folds ß and Ø too, so "gross" finds Groß.
    nonisolated static func folded(_ string: String) -> String {
        string.applyingTransform(StringTransform("Latin-ASCII; Lower"), reverse: false) ?? string.lowercased()
    }
}
