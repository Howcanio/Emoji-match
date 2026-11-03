import Foundation

/// Personal best, stored locally.
public struct HighScoreStore {
    static let key = "emojiMatch.highScore"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var best: Int { max(0, defaults.integer(forKey: Self.key)) }

    /// Returns true when `score` beats the stored best. A score of 0 is never a record.
    @discardableResult
    public func record(_ score: Int) -> Bool {
        guard score > best else { return false }
        defaults.set(score, forKey: Self.key)
        return true
    }
}

public struct LeaderboardEntry: Codable, Equatable, Sendable {
    public let score: Int
    public let matches: Int
    public let longestMatch: Int
    public let multiplier: Int
    public let date: Date

    public init(score: Int, matches: Int, longestMatch: Int, multiplier: Int, date: Date) {
        self.score = score
        self.matches = matches
        self.longestMatch = longestMatch
        self.multiplier = multiplier
        self.date = date
    }
}

/// The best rounds played on this device, highest score first.
public struct LeaderboardStore {
    static let key = "emojiMatch.leaderboard"
    public static let capacity = 10
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Unreadable data reads as an empty board rather than stopping the game.
    public var entries: [LeaderboardEntry] {
        guard let data = defaults.data(forKey: Self.key),
              let saved = try? JSONDecoder().decode([LeaderboardEntry].self, from: data) else { return [] }
        return saved
    }

    /// A best from before the leaderboard existed goes on an empty board, so the two can't
    /// disagree. Its round details weren't kept, which `matches == 0` marks.
    public func adopt(best: Int, date: Date = Date()) {
        guard entries.isEmpty else { return }
        record(LeaderboardEntry(score: best, matches: 0, longestMatch: 0, multiplier: 1, date: date))
    }

    /// Returns the entry's 1-based rank, or nil if it didn't place. A score of 0 never places,
    /// and on a tie the earlier round keeps the higher rank.
    @discardableResult
    public func record(_ entry: LeaderboardEntry) -> Int? {
        guard entry.score > 0 else { return nil }
        var board = entries
        let index = board.firstIndex { $0.score < entry.score } ?? board.count
        guard index < Self.capacity else { return nil }
        board.insert(entry, at: index)
        guard let data = try? JSONEncoder().encode(Array(board.prefix(Self.capacity))) else { return nil }
        defaults.set(data, forKey: Self.key)
        return index + 1
    }
}

public enum SettingsKeys {
    public static let sound = "emojiMatch.soundEnabled"
    public static let haptics = "emojiMatch.hapticsEnabled"
}
