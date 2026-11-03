import XCTest
@testable import EmojiMatchCore

/// Vertical stripes: every column is one type, so any three tiles in a column match.
func stripedTypes(rows: Int = 8, columns: Int = 6) -> [[Int]] {
    (0..<rows).map { _ in (0..<columns).map { $0 } }
}

/// A full standard board with no valid match: each type forms a lattice with basis (2,2),(2,-2),
/// so a tile's two nearest same-type tiles are at least 2√2 away and 2 × 2√2 ≈ 5.66 > 5.
func unsolvableTypes(rows: Int = 8, columns: Int = 6) -> [[Int]] {
    (0..<rows).map { r in
        (0..<columns).map { c in (r % 2) + 2 * (c % 2) + 4 * ((r / 2 + c / 2) % 2) }
    }
}

func runningEngine(
    types: [[Int]]? = nil,
    refills: [Int] = [],
    config: GameConfig = GameConfig(),
    seed: UInt64 = 1
) -> GameEngine {
    var engine = GameEngine(config: config, seed: seed, initialTypes: types, scriptedRefills: refills)
    engine.startRound()
    return engine
}

extension Array where Element == GameEvent {
    var selectedPositions: [Position] {
        compactMap { if case .tileSelected(_, let position, _) = $0 { position } else { nil } }
    }
    var resolution: MatchResolution? {
        lazy.compactMap { if case .matched(let resolution) = $0 { resolution } else { nil } }.first
    }
}
