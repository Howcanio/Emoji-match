import Combine
import EmojiMatchCore
import Foundation

/// Owns one round: routes input to the engine, engine events to the scene and feedback, and
/// publishes what the SwiftUI HUD shows.
@MainActor
final class GameSession: ObservableObject {
    @Published private(set) var score = 0
    @Published private(set) var secondsLeft: Int
    @Published private(set) var phase: GamePhase = .ready
    @Published private(set) var multiplier = 1
    /// Fraction of the current string still available; 1 when nothing is selected.
    @Published private(set) var stringRemaining: Double = 1
    /// Current string length as a fraction of its cap, so growth is visible.
    @Published private(set) var stringGrowth: Double

    private(set) var engine: GameEngine
    let scene: GameScene
    var onFinished: ((RoundSummary) -> Void)?

    private let highScores: HighScoreStore
    private let leaderboard: LeaderboardStore
    private let feedback: GameFeedback
    private var introRemaining: TimeInterval?
    private var resolveRemaining: TimeInterval?
    private var pendingSummary: RoundSummary?

    /// The timer turns red for the last few seconds and ticks for the very last.
    static let urgentSeconds = 10
    private static let tickingSeconds = 5

    init(
        engine: GameEngine,
        highScores: HighScoreStore = HighScoreStore(),
        leaderboard: LeaderboardStore = LeaderboardStore(),
        feedback: GameFeedback
    ) {
        self.engine = engine
        self.highScores = highScores
        self.leaderboard = leaderboard
        self.feedback = feedback
        self.secondsLeft = Int(engine.remaining.rounded(.up))
        self.stringGrowth = engine.stringLength / engine.config.lengthCap
        self.scene = GameScene(size: CGSize(width: 1, height: 1))
        scene.session = self
    }

    var isUrgent: Bool { secondsLeft <= Self.urgentSeconds && phase != .ready }

    // MARK: - Frame loop

    func frame(delta: TimeInterval) {
        guard !engine.isPaused else { return }
        if engine.phase == .ready {
            let remaining = (introRemaining ?? scene.introDuration) - delta
            introRemaining = remaining
            if remaining <= 0 {
                introRemaining = nil
                process(engine.startRound())
            }
            return
        }
        process(engine.tick(delta))
        if let remaining = resolveRemaining {
            let next = remaining - delta
            resolveRemaining = next > 0 ? next : nil
            if next <= 0 { process(engine.finishResolving()) }
        }
        updateCountdown()
    }

    private func updateCountdown() {
        let seconds = Int(engine.remaining.rounded(.up))
        guard seconds != secondsLeft else { return }
        secondsLeft = seconds
        if seconds > 0, seconds <= Self.tickingSeconds { feedback.timerTick() }
    }

    // MARK: - Input

    func touchDown(at point: BoardPoint) { process(engine.touchDown(at: point)) }
    func touchMoved(to point: BoardPoint) { process(engine.touchMoved(to: point)) }
    func touchUp() { process(engine.touchUp()) }

    // MARK: - App lifecycle

    func pause() {
        process(engine.pause())
        scene.forgetTouch()
        scene.isPaused = true
    }

    func resume() {
        engine.resume()
        scene.resetClock()
        scene.isPaused = false
        scene.view?.isPaused = false
    }

    // MARK: - Events

    private func process(_ events: [GameEvent]) {
        for event in events {
            let duration = scene.apply(event)
            switch event {
            case .tileSelected(let tile, _, let index):
                feedback.tileSelected(type: tile.type, index: index)
            case .matched(let resolution):
                resolveRemaining = duration ?? 0
                feedback.matched(type: resolution.cleared[0].tile.type, count: resolution.cleared.count)
                if resolution.raisedMultiplier { feedback.multiplierRaised() }
            case .roundEnded(let score, let matches):
                finishRound(score: score, matches: matches)
            case .roundStarted, .selectionCancelled, .resolvingFinished:
                break
            }
        }
        guard !events.isEmpty else { return }
        score = engine.score
        phase = engine.phase
        multiplier = engine.multiplier
        stringGrowth = engine.stringLength / engine.config.lengthCap
        stringRemaining = engine.phase == .selecting ? engine.remainingLength / engine.stringLength : 1
        updateCountdown()
    }

    private func finishRound(score: Int, matches: Int) {
        let isNewBest = highScores.record(score)
        let rank = leaderboard.record(LeaderboardEntry(
            score: score,
            matches: matches,
            longestMatch: engine.longestMatch,
            multiplier: engine.multiplier,
            date: Date()
        ))
        pendingSummary = RoundSummary(
            score: score,
            matches: matches,
            longestMatch: engine.longestMatch,
            best: highScores.best,
            isNewBest: isNewBest,
            leaderboardRank: rank
        )
        feedback.roundEnded(newBest: isNewBest)
    }

    /// Called after the "Time's up" beat to move on to results.
    func showResults() {
        guard let summary = pendingSummary else { return }
        pendingSummary = nil
        onFinished?(summary)
    }
}
