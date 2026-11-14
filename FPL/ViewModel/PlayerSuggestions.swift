//
//  PlayerSuggestions.swift
//  FPL
//

import Foundation

/// Players to suggest while typing an @ mention in a note.
@MainActor
final class PlayerSuggestions: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    /// A player with the names a mention can start, folded once rather than per keystroke.
    struct Candidate: Sendable {
        let element: Element
        let keys: [String]

        init(_ element: Element) {
            self.element = element
            let names: [String] = [Mention.folded(element.webName), Mention.folded(element.fullName)]
            var keys = Set(names)
            for name in names {
                for word in name.split(whereSeparator: { $0 == " " || $0 == "-" }) { keys.insert(String(word)) }
            }
            self.keys = Array(keys)
        }
    }

    nonisolated static let limit = 5

    @Published private(set) var state: State = .idle
    private(set) var candidates: [Candidate] = []
    private let load: () async throws -> [Element]

    /// - Parameter load: Every player, from `/api/elements`. Not `ElementViewModel`,
    ///   which loads one position at a time.
    init(load: @escaping () async throws -> [Element] = { try await FPLAPIClient().elements() }) {
        self.load = load
    }

    /// Uses `known` when it's already loaded (Profile's players), and fetches otherwise.
    /// After a failure only `reload()` (Retry) tries again, not every keystroke.
    func loadIfNeeded(known: [Int: Element] = [:]) async {
        guard state == .idle else { return }
        if !known.isEmpty {
            use(Array(known.values))
            return
        }
        await reload()
    }

    func reload() async {
        state = .loading
        do {
            use(try await load())
        } catch where error is CancellationError || (error as? URLError)?.code == .cancelled {
            // Not a failure: the next mention loads again.
            state = .idle
        } catch {
            state = .failed
        }
    }

    private func use(_ elements: [Element]) {
        candidates = elements.filter(\.isSelectable).map(Candidate.init)
        state = .loaded
    }

    func suggestions(for query: String, squad: Set<Int>, linked: Set<Int>) -> [Element] {
        Self.suggestions(for: query, in: candidates, squad: squad, linked: linked)
    }

    /// Players a name of whom starts with `query`, ignoring case and accents: your
    /// squad first, then most total points, then name. Players already linked are left out.
    nonisolated static func suggestions(for query: String, in candidates: [Candidate], squad: Set<Int>,
                                        linked: Set<Int>, limit: Int = limit) -> [Element] {
        let typed = Mention.folded(query.trimmingCharacters(in: .whitespaces))
        let matches = candidates.filter { candidate in
            !linked.contains(candidate.element.id)
                && (typed.isEmpty || candidate.keys.contains { $0.hasPrefix(typed) })
        }
        return matches.map(\.element)
            .sorted { a, b in
                let aMine = squad.contains(a.id), bMine = squad.contains(b.id)
                if aMine != bMine { return aMine }
                if a.totalPoints != b.totalPoints { return (a.totalPoints ?? 0) > (b.totalPoints ?? 0) }
                return a.webName < b.webName
            }
            .prefix(limit)
            .map { $0 }
    }
}
