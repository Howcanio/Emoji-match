import EmojiMatchCore
import Foundation

/// Launch options used only by UI tests, for a deterministic board and short rounds.
struct LaunchOptions {
    var fixedBoard = false
    var roundDuration: TimeInterval?
    var resetDefaults = false

    static let current: LaunchOptions = {
        var options = LaunchOptions()
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        options.fixedBoard = arguments.contains("-uiTestFixedBoard")
        options.resetDefaults = arguments.contains("-uiTestResetDefaults")
        if let index = arguments.firstIndex(of: "-uiTestRoundDuration"), index + 1 < arguments.count {
            options.roundDuration = TimeInterval(arguments[index + 1])
        }
        #endif
        return options
    }()

    func makeEngine() -> GameEngine {
        let config = GameConfig(duration: roundDuration ?? GameConfig().duration)
        guard fixedBoard else { return GameEngine(config: config) }
        let stripes = (0..<config.rows).map { _ in (0..<config.columns).map { $0 } }
        return GameEngine(config: config, seed: 1, initialTypes: stripes)
    }
}

struct RoundSummary: Equatable {
    let score: Int
    let matches: Int
    let best: Int
    let isNewBest: Bool
}
