import XCTest
@testable import EmojiMatchCore

final class LeaderboardTests: XCTestCase {
    private let suite = "EmojiMatchCoreTests.leaderboard"
    private var defaults: UserDefaults!
    private var store: LeaderboardStore!

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        store = LeaderboardStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func entry(_ score: Int, longest: Int = 3, at seconds: TimeInterval = 0) -> LeaderboardEntry {
        LeaderboardEntry(score: score, matches: 1, longestMatch: longest, multiplier: 1, date: Date(timeIntervalSince1970: seconds))
    }

    func testStartsEmpty() {
        XCTAssertEqual(store.entries, [])
    }

    func testEntriesSortHighestFirstAndReportRank() {
        XCTAssertEqual(store.record(entry(200)), 1)
        XCTAssertEqual(store.record(entry(500)), 1)
        XCTAssertEqual(store.record(entry(300)), 2)
        XCTAssertEqual(store.entries.map(\.score), [500, 300, 200])
    }

    func testZeroScoreNeverPlaces() {
        XCTAssertNil(store.record(entry(0)))
        XCTAssertEqual(store.entries, [])
    }

    func testTieKeepsEarlierRoundAhead() {
        store.record(entry(300, at: 1))
        XCTAssertEqual(store.record(entry(300, at: 2)), 2)
        XCTAssertEqual(store.entries.map(\.date.timeIntervalSince1970), [1, 2])
    }

    func testKeepsOnlyTopTen() {
        for score in 1...10 { store.record(entry(score * 100)) }
        XCTAssertNil(store.record(entry(50)), "Below a full board")
        XCTAssertNil(store.record(entry(100)), "A tie with last place doesn't displace it")
        XCTAssertEqual(store.record(entry(150)), 10)
        XCTAssertEqual(store.entries.count, LeaderboardStore.capacity)
        XCTAssertEqual(store.entries.last?.score, 150)
    }

    func testPersistsEveryField() {
        let saved = LeaderboardEntry(score: 900, matches: 4, longestMatch: 6, multiplier: 3, date: Date(timeIntervalSince1970: 1000))
        store.record(saved)
        XCTAssertEqual(LeaderboardStore(defaults: defaults).entries, [saved])
    }

    func testEarlierBestJoinsOnlyAnEmptyBoard() {
        store.adopt(best: 0)
        XCTAssertEqual(store.entries, [])
        store.adopt(best: 8500)
        XCTAssertEqual(store.entries.map(\.score), [8500])
        store.adopt(best: 9000)
        XCTAssertEqual(store.entries.map(\.score), [8500])
        XCTAssertEqual(store.record(entry(200)), 2)
    }

    func testCorruptDataReadsEmptyAndRecovers() {
        defaults.set(Data("not json".utf8), forKey: LeaderboardStore.key)
        XCTAssertEqual(store.entries, [])
        XCTAssertEqual(store.record(entry(100)), 1)
    }
}

final class ComboTierTests: XCTestCase {
    func testTiersFollowGrabSize() {
        XCTAssertEqual(ComboTier(grabSize: 3), .none)
        XCTAssertEqual(ComboTier(grabSize: 4), .nice)
        XCTAssertEqual(ComboTier(grabSize: 5), .great)
        XCTAssertEqual(ComboTier(grabSize: 6), .amazing)
        XCTAssertEqual(ComboTier(grabSize: 7), .legendary)
        XCTAssertEqual(ComboTier(grabSize: 20), .legendary)
    }

    func testOnlyRealCombosHaveATitle() {
        XCTAssertNil(ComboTier.none.title)
        XCTAssertEqual(ComboTier.great.title, "Great combo!")
    }
}
