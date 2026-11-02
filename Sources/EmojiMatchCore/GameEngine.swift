import Foundation

public struct Position: Hashable, Sendable {
    public let row: Int
    public let column: Int
    public init(_ row: Int, _ column: Int) { self.row = row; self.column = column }
}
public struct GameConfig: Sendable {
    public let rows: Int
    public let columns: Int
    public let types: Int
    public let maxLength: Double
    public let duration: TimeInterval
    public init(rows: Int = 8, columns: Int = 6, types: Int = 8, maxLength: Double = 5, duration: TimeInterval = 60) {
        self.rows = rows; self.columns = columns; self.types = types; self.maxLength = maxLength; self.duration = duration
    }
}
public struct GameEngine {
    public let config: GameConfig
    public private(set) var board: [[Int]]
    public private(set) var score = 0
    public private(set) var remaining: TimeInterval
    public private(set) var selection: [Position] = []
    public private(set) var finished = false
    private var randomType: () -> Int

    public init(config: GameConfig = GameConfig(), randomType: @escaping () -> Int = { Int.random(in: 0..<8) }) {
        self.config = config
        self.randomType = randomType
        self.remaining = config.duration
        self.board = Array(repeating: Array(repeating: 0, count: config.columns), count: config.rows)
        refillAll()
    }
    public mutating func start(at p: Position) {
        guard !finished, valid(p) else { return }
        selection = [p]
    }
    public mutating func visit(_ p: Position) -> Bool {
        guard !finished, valid(p), let first = selection.first, selection.count < 3,
              !selection.contains(p), board[p.row][p.column] == board[first.row][first.column],
              let last = selection.last else { return false }
        let used = zip(selection, selection.dropFirst()).reduce(0.0) { $0 + distance($1.0, $1.1) }
        guard used + distance(last, p) <= config.maxLength + 1e-9 else { return false }
        selection.append(p)
        if selection.count == 3 { clearMatch(); return true }
        return false
    }
    public mutating func cancel() { selection.removeAll() }
    public mutating func tick(_ seconds: TimeInterval) {
        guard !finished else { return }
        remaining = max(0, remaining - max(0, seconds))
        if remaining == 0 { finished = true; cancel() }
    }
    public func hasMatch() -> Bool {
        for r in 0..<config.rows { for c in 0..<config.columns {
            let a = Position(r,c)
            for s in 0..<config.rows { for t in 0..<config.columns {
                let b = Position(s,t)
                if a == b || board[r][c] != board[s][t] { continue }
                let ab = distance(a,b)
                if ab > config.maxLength { continue }
                for u in 0..<config.rows { for v in 0..<config.columns {
                    let d = Position(u,v)
                    if d != a && d != b && board[u][v] == board[r][c] && ab + distance(b,d) <= config.maxLength { return true }
                }}
            }}
        }}
        return false
    }
    private func valid(_ p: Position) -> Bool { (0..<config.rows).contains(p.row) && (0..<config.columns).contains(p.column) }
    private func distance(_ a: Position, _ b: Position) -> Double {
        hypot(Double(a.row-b.row), Double(a.column-b.column))
    }
    private mutating func clearMatch() {
        let cleared = selection
        selection.removeAll()
        score += 100
        for col in Set(cleared.map(\.column)) {
            let removedRows = Set(cleared.filter { $0.column == col }.map(\.row))
            let survivors = (0..<config.rows).filter { !removedRows.contains($0) }.map { board[$0][col] }
            let replacements = (0..<(config.rows-survivors.count)).map { _ in nextType() }
            for (row, type) in (replacements + survivors).enumerated() { board[row][col] = type }
        }
        ensureSolvable()
    }
    private mutating func refillAll() {
        for r in 0..<config.rows { for c in 0..<config.columns { board[r][c] = nextType() } }
        ensureSolvable()
    }
    private mutating func ensureSolvable() {
        guard config.rows * config.columns >= 3 else { return }
        if hasMatch() { return }
        // Force a guaranteed valid horizontal or vertical trio rather than an unbounded shuffle.
        let type = nextType()
        if config.columns >= 3 {
            for c in 0..<3 { board[0][c] = type }
        } else if config.rows >= 3 {
            for r in 0..<3 { board[r][0] = type }
        }
    }
    private mutating func nextType() -> Int {
        let raw = randomType()
        return ((raw % config.types) + config.types) % config.types
    }
}
