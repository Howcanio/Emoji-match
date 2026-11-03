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

public enum SettingsKeys {
    public static let sound = "emojiMatch.soundEnabled"
    public static let haptics = "emojiMatch.hapticsEnabled"
}
