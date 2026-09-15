import Foundation

struct HighScoreEntry: Codable, Equatable {
    var initials: String   // exactly 3 characters
    var score: Int
}

/// The top-10 table, persisted as JSON in UserDefaults.
final class HighScoreStore {
    static let shared = HighScoreStore()

    /// v2: the table was reset here after the scoring rescale, and to correct
    /// the second-place initials. Bumping the key discards any saved v1 table.
    private let key = "spyhunter.highscores.v2"
    private(set) var entries: [HighScoreEntry] = []

    private init() { load() }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([HighScoreEntry].self, from: data),
           !decoded.isEmpty {
            entries = decoded
        } else {
            entries = GameConfig.defaultHighScores.map {
                HighScoreEntry(initials: $0.0, score: $0.1)
            }
        }
        normalise()
    }

    private func normalise() {
        entries.sort { $0.score > $1.score }
        if entries.count > GameConfig.highScoreCount {
            entries = Array(entries.prefix(GameConfig.highScoreCount))
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    var topScore: Int { entries.first?.score ?? 0 }

    /// True when `score` earns a place in the table.
    func qualifies(_ score: Int) -> Bool {
        guard score > 0 else { return false }
        if entries.count < GameConfig.highScoreCount { return true }
        return score > (entries.last?.score ?? 0)
    }

    /// Inserts a score and returns the row it landed on (0-based), or nil.
    @discardableResult
    func insert(initials: String, score: Int) -> Int? {
        guard qualifies(score) else { return nil }
        var ini = initials.uppercased()
        if ini.count > 3 { ini = String(ini.prefix(3)) }
        while ini.count < 3 { ini += " " }
        let entry = HighScoreEntry(initials: ini, score: score)
        entries.append(entry)
        normalise()
        save()
        return entries.firstIndex(of: entry)
    }

    /// Restores the built-in table.
    func reset() {
        entries = GameConfig.defaultHighScores.map {
            HighScoreEntry(initials: $0.0, score: $0.1)
        }
        normalise()
        save()
    }
}
