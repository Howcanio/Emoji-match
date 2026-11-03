import Foundation

/// A cell on the board. Row 0 is the top row; column 0 is the left column.
public struct Position: Hashable, Sendable, CustomStringConvertible {
    public let row: Int
    public let column: Int
    public init(_ row: Int, _ column: Int) { self.row = row; self.column = column }
    public var description: String { "(\(row),\(column))" }

    /// Euclidean distance between tile centers, in tile units.
    public func distance(to other: Position) -> Double {
        hypot(Double(row - other.row), Double(column - other.column))
    }
}

/// A continuous location on the board in tile units.
/// Tile (r, c) covers x in c..<c+1 and y in r..<r+1, so its center is (c + 0.5, r + 0.5).
public struct BoardPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public init(center position: Position) {
        self.init(x: Double(position.column) + 0.5, y: Double(position.row) + 0.5)
    }
    public var isFinite: Bool { x.isFinite && y.isFinite }
    public func distance(to other: BoardPoint) -> Double { hypot(x - other.x, y - other.y) }
}

public struct GameConfig: Sendable, Equatable {
    public let rows: Int
    public let columns: Int
    public let types: Int
    public let maxLength: Double
    public let duration: TimeInterval
    public let pointsPerMatch: Int
    public let matchSize = 3

    public init(
        rows: Int = 8,
        columns: Int = 6,
        types: Int = 8,
        maxLength: Double = 5,
        duration: TimeInterval = 60,
        pointsPerMatch: Int = 100
    ) {
        // More than 2 tiles per type guarantees some type has 3 tiles (pigeonhole), and a
        // 2-unit string can always join 3 adjacent tiles, so every valid config is solvable.
        precondition(rows > 0 && columns > 0 && types > 0, "Board and type counts must be positive")
        precondition(rows * columns > 2 * types, "Board too small to guarantee three tiles of one type")
        precondition(maxLength >= 2, "String too short to guarantee a match")
        self.rows = rows
        self.columns = columns
        self.types = types
        self.maxLength = maxLength
        self.duration = duration
        self.pointsPerMatch = pointsPerMatch
    }

    public func contains(_ position: Position) -> Bool {
        (0..<rows).contains(position.row) && (0..<columns).contains(position.column)
    }
}

/// Tiles keep their identity while they move so renderers can animate them.
public struct Tile: Hashable, Sendable, Identifiable {
    public let id: Int
    public let type: Int
    public init(id: Int, type: Int) { self.id = id; self.type = type }
}

public enum GamePhase: Equatable, Sendable {
    case ready
    case playing
    case selecting
    case resolvingMatch
    case gameOver
}

public struct ClearedTile: Equatable, Sendable {
    public let tile: Tile
    public let position: Position
}

public struct TileMove: Equatable, Sendable {
    public let tile: Tile
    public let from: Position
    public let to: Position
}

public struct TileSpawn: Equatable, Sendable {
    public let tile: Tile
    public let to: Position
    /// Row the tile starts falling from. Always negative: above the board.
    public let entryRow: Int
}

/// Everything a renderer needs to animate one completed match. The engine's board already
/// reflects the result; `reshuffle` is non-empty only if the refilled board had no valid match.
public struct MatchResolution: Equatable, Sendable {
    public let cleared: [ClearedTile]
    public let moves: [TileMove]
    public let spawns: [TileSpawn]
    public let reshuffle: [TileMove]
    public let points: Int
}

public enum SelectionRejection: Equatable, Sendable {
    case notAccepting
    case outOfBounds
    case noActiveSelection
    case duplicateTile
    case typeMismatch
    case stringTooLong
}

public enum SelectionResult: Equatable, Sendable {
    case selected
    case matched(MatchResolution)
    case rejected(SelectionRejection)
}

public enum GameEvent: Equatable, Sendable {
    case roundStarted
    case tileSelected(Tile, at: Position, index: Int)
    case selectionCancelled([Position])
    case matched(MatchResolution)
    case resolvingFinished
    case roundEnded(score: Int, matches: Int)
}
