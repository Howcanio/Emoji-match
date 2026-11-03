import EmojiMatchCore
import SpriteKit
import XCTest
@testable import EmojiMatch

@MainActor
private final class RecordingFeedback: GameFeedback {
    var selections: [Int] = []
    var matches = 0
    var raises = 0
    var ticks = 0
    var endings: [Bool] = []
    func tileSelected(index: Int) { selections.append(index) }
    func matched() { matches += 1 }
    func multiplierRaised() { raises += 1 }
    func timerTick() { ticks += 1 }
    func roundEnded(newBest: Bool) { endings.append(newBest) }
}

/// Drives a real GameSession and GameScene without a window, one simulated frame at a time.
@MainActor
final class GameSessionTests: XCTestCase {
    private let suite = "EmojiMatchTests.session"
    private var defaults: UserDefaults!
    private var feedback: RecordingFeedback!
    private var session: GameSession!

    private static var stripes: [[Int]] { (0..<8).map { _ in (0..<6).map { $0 } } }

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        feedback = RecordingFeedback()
        session = makeSession(GameEngine(seed: 1, initialTypes: Self.stripes))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeSession(_ engine: GameEngine) -> GameSession {
        let session = GameSession(engine: engine, highScores: HighScoreStore(defaults: defaults), feedback: feedback)
        session.scene.reduceMotion = { false }
        session.scene.size = CGSize(width: 390, height: 520)
        return session
    }

    private func run(seconds: TimeInterval, frame: TimeInterval = 1.0 / 60) {
        var elapsed = 0.0
        while elapsed < seconds {
            session.frame(delta: frame)
            elapsed += frame
        }
    }

    private func startRound() {
        run(seconds: GameScene.Timing.intro + 0.05)
        XCTAssertEqual(session.phase, .playing)
    }

    private func center(_ row: Int, _ column: Int) -> BoardPoint { BoardPoint(center: Position(row, column)) }

    private func playColumnMatch(column: Int = 0) {
        session.touchDown(at: center(5, column))
        session.touchMoved(to: center(7, column))
        session.touchUp()
    }

    func testSceneBuildsFullBoard() {
        XCTAssertEqual(session.scene.liveTileCount, 48)
    }

    func testIntroThenPlaying() {
        XCTAssertEqual(session.phase, .ready)
        run(seconds: 0.1)
        XCTAssertEqual(session.phase, .ready)
        XCTAssertEqual(session.engine.remaining, 60)
        startRound()
    }

    func testMatchUpdatesHUDFeedbackAndResolvesAfterAnimation() {
        startRound()
        playColumnMatch()
        XCTAssertEqual(session.score, 100)
        XCTAssertEqual(session.phase, .resolvingMatch)
        XCTAssertEqual(feedback.matches, 1)
        XCTAssertEqual(feedback.selections, [0, 1])
        XCTAssertEqual(session.scene.liveTileCount, 48)
        run(seconds: GameScene.Timing.pop + GameScene.Timing.gravity + 0.05)
        XCTAssertEqual(session.phase, .playing)
    }

    func testResolveTakesAboutTheSpecifiedTime() {
        startRound()
        playColumnMatch()
        run(seconds: GameScene.Timing.pop + GameScene.Timing.gravity - 0.05)
        XCTAssertEqual(session.phase, .resolvingMatch, "input stays locked during gravity and refill")
        run(seconds: 0.1)
        XCTAssertEqual(session.phase, .playing)
    }

    func testRepeatedMatchesKeepSceneConsistent() {
        var engine = GameEngine(seed: 5)
        engine.startRound()
        session = makeSession(engine)
        for iteration in 1...50 {
            let path = session.engine.availableMatch!
            session.touchDown(at: BoardPoint(center: path[0]))
            // Reach each target by touching it directly; any same-type tile on the way only
            // changes which match is made, and the assertions hold either way.
            session.touchMoved(to: BoardPoint(center: path[1]))
            if session.phase == .selecting { session.touchMoved(to: BoardPoint(center: path[2])) }
            session.touchUp()
            XCTAssertGreaterThanOrEqual(session.score, 100)
            XCTAssertEqual(session.scene.liveTileCount, 48)
            run(seconds: 0.6)
            XCTAssertEqual(session.phase, .playing)
        }
    }

    func testRapidSwipeThroughSceneInput() {
        startRound()
        session.touchDown(at: center(0, 2))
        session.touchMoved(to: center(7, 2))
        // A 3-unit string crossing a full column reaches 4 tiles and raises the multiplier to ×2.
        XCTAssertEqual(session.score, 200)
        XCTAssertEqual(session.multiplier, 2)
        XCTAssertEqual(feedback.raises, 1)
        XCTAssertEqual(session.scene.liveTileCount, 48)
    }

    func testStringGaugeTracksSelection() {
        startRound()
        XCTAssertEqual(session.stringRemaining, 1)
        XCTAssertEqual(session.stringGrowth, 0.25)
        session.touchDown(at: center(0, 0))
        session.touchMoved(to: center(1, 0))
        XCTAssertEqual(session.stringRemaining, 2.0 / 3, accuracy: 0.001)
        session.touchUp()
        XCTAssertEqual(session.stringRemaining, 1)
        playColumnMatch()
        XCTAssertEqual(session.stringGrowth, 3.5 / 12, accuracy: 0.001)
    }

    func testPauseFreezesRoundAndResumeContinues() {
        startRound()
        run(seconds: 1)
        let before = session.engine.remaining
        session.pause()
        XCTAssertTrue(session.engine.isPaused)
        XCTAssertTrue(session.scene.isPaused)
        run(seconds: 5)
        XCTAssertEqual(session.engine.remaining, before)
        session.resume()
        XCTAssertFalse(session.scene.isPaused)
        run(seconds: 1)
        XCTAssertLessThan(session.engine.remaining, before)
        XCTAssertGreaterThan(session.engine.remaining, before - 1.1)
    }

    func testPauseDuringIntroHoldsReadyState() {
        session.pause()
        run(seconds: 2)
        XCTAssertEqual(session.phase, .ready)
        session.resume()
        startRound()
    }

    func testPauseDropsGestureAndHeldFinger() {
        startRound()
        session.touchDown(at: center(0, 0))
        session.pause()
        XCTAssertEqual(session.phase, .playing)
        XCTAssertEqual(session.stringRemaining, 1)
        session.resume()
        session.touchMoved(to: center(1, 0))
        XCTAssertTrue(session.engine.selection.isEmpty)
    }

    func testPauseDuringResolvingCompletesAfterResume() {
        startRound()
        playColumnMatch()
        session.pause()
        run(seconds: 2)
        XCTAssertEqual(session.phase, .resolvingMatch)
        session.resume()
        run(seconds: 0.6)
        XCTAssertEqual(session.phase, .playing)
        XCTAssertEqual(session.score, 100)
    }

    func testExpiryRecordsHighScoreOnceAndProducesSummary() {
        session = makeSession(GameEngine(config: GameConfig(duration: 2), seed: 1, initialTypes: Self.stripes))
        var summaries: [RoundSummary] = []
        session.onFinished = { summaries.append($0) }
        startRound()
        playColumnMatch()
        run(seconds: 3)
        XCTAssertEqual(session.phase, .gameOver)
        XCTAssertEqual(feedback.endings, [true])
        session.showResults()
        session.showResults()
        XCTAssertEqual(summaries, [RoundSummary(score: 100, matches: 1, longestMatch: 3, best: 100, isNewBest: true)])
        XCTAssertEqual(HighScoreStore(defaults: defaults).best, 100)
    }

    func testLowerScoreDoesNotReplaceBest() {
        HighScoreStore(defaults: defaults).record(500)
        session = makeSession(GameEngine(config: GameConfig(duration: 1), seed: 1, initialTypes: Self.stripes))
        var summary: RoundSummary?
        session.onFinished = { summary = $0 }
        startRound()
        playColumnMatch()
        run(seconds: 2)
        session.showResults()
        XCTAssertEqual(summary, RoundSummary(score: 100, matches: 1, longestMatch: 3, best: 500, isNewBest: false))
        XCTAssertEqual(feedback.endings, [false])
    }

    func testExpiryMidResolveFinishesMatchBeforeEnding() {
        session = makeSession(GameEngine(config: GameConfig(duration: 1), seed: 1, initialTypes: Self.stripes))
        startRound()
        run(seconds: 0.9)
        playColumnMatch()
        run(seconds: 0.2)
        XCTAssertEqual(session.engine.remaining, 0)
        XCTAssertEqual(session.phase, .resolvingMatch)
        run(seconds: 0.5)
        XCTAssertEqual(session.phase, .gameOver)
        XCTAssertEqual(session.score, 100)
    }

    func testLastSecondsTick() {
        session = makeSession(GameEngine(config: GameConfig(duration: 7), seed: 1, initialTypes: Self.stripes))
        startRound()
        run(seconds: 8)
        XCTAssertEqual(feedback.ticks, 5)
    }

    func testReduceMotionUsesShorterTimingAndSameRules() {
        session = makeSession(GameEngine(seed: 1, initialTypes: Self.stripes))
        session.scene.reduceMotion = { true }
        run(seconds: GameScene.Timing.reducedIntro + 0.05)
        XCTAssertEqual(session.phase, .playing)
        playColumnMatch()
        XCTAssertEqual(session.scene.liveTileCount, 48)
        run(seconds: GameScene.Timing.reducedPop + GameScene.Timing.reducedSettle + 0.05)
        XCTAssertEqual(session.phase, .playing)
        XCTAssertEqual(session.score, 100)
    }

    func testReshuffleExtendsResolveAndKeepsTiles() {
        // Lattice board with no match after refill: see core ReshuffleTests.
        let lattice: [[Int]] = (0..<8).map { r in
            (0..<6).map { c in (r % 2) + 2 * (c % 2) + 4 * ((r / 2 + c / 2) % 2) }
        }
        var types = lattice
        for row in 0..<5 { types[row][5] = lattice[row + 3][5] }
        for row in 5..<8 { types[row][5] = 0 }
        let engine = GameEngine(seed: 1, initialTypes: types, scriptedRefills: (0..<3).map { lattice[$0][5] })
        session = makeSession(engine)
        startRound()
        playColumnMatch(column: 5)
        XCTAssertEqual(session.scene.liveTileCount, 48)
        run(seconds: GameScene.Timing.pop + GameScene.Timing.gravity + 0.05)
        XCTAssertEqual(session.phase, .resolvingMatch, "reshuffle glide still running")
        run(seconds: GameScene.Timing.reshuffle)
        XCTAssertEqual(session.phase, .playing)
        XCTAssertNotNil(session.engine.board.findMatch(maxLength: 5))
    }

    func testSoundSynthBuildsEverySoundWithoutCrashing() {
        let synth = SoundSynth()
        for sound in SoundSynth.Sound.allCases { synth.play(sound) }
    }

    func testEmojiCatalogHasDistinctEntryForEveryType() {
        XCTAssertEqual(EmojiCatalog.entries.count, GameConfig().types)
        XCTAssertEqual(Set(EmojiCatalog.entries.map(\.emoji)).count, GameConfig().types)
    }
}
