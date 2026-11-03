import Foundation

/// The rules of Emoji Match, independent of rendering and UI.
///
/// State machine (`phase`):
///
///     ready ──startRound──▶ playing ◀──release under 3 tiles── selecting
///                             ▲  │ begin                           │ release with 3+ tiles,
///                             │  └──────────▶ selecting            ▼ or nothing left in reach
///                             └──────finishResolving────── resolvingMatch
///     any active phase ── timer expiry ──▶ gameOver
///
/// The string starts short and grows with every match. A selection of 3 or more tiles commits when
/// the finger lifts, or at once when no further tile is in reach. Completing a longer grab than any
/// before it in the round raises the multiplier, which then applies to every later match.
///
/// Expiry commits a selection of 3 or more; the committed match finishes and the round ends on
/// `finishResolving()`. `isPaused` is orthogonal: it freezes the clock and input in any phase.
/// The clock keeps running during `resolvingMatch` because the round is 60 real seconds.
public struct GameEngine {
    /// Tolerance for floating-point sums at the exact string limit.
    static let lengthTolerance = 1e-9
    /// Spacing of interpolated touch samples, in tile units. Well under a tile's hit diameter.
    static let sampleStep = 0.1
    /// While dragging, a tile only registers within this distance of its center, so that a
    /// diagonal drag between two tiles doesn't catch their corners.
    public static let hitRadius = 0.45

    public let config: GameConfig
    public private(set) var board: Board
    public private(set) var phase: GamePhase = .ready
    public private(set) var isPaused = false
    public private(set) var score = 0
    public private(set) var matchCount = 0
    public private(set) var multiplier = 1
    /// Most tiles cleared by one match this round.
    public private(set) var longestMatch = 0
    /// Current string length in tile units.
    public private(set) var stringLength: Double
    public private(set) var remaining: TimeInterval
    public private(set) var selection: [Position] = []
    /// True from a completed match until that finger lifts.
    public private(set) var awaitingRelease = false

    private var generator: SeededGenerator
    private var scriptedTypes: ArraySlice<Int>
    private var nextTileID = 0
    private var fingerDown = false
    private var lastPoint: BoardPoint?
    private var lastHit: Position?

    /// - Parameters:
    ///   - seed: Determines the board and refills.
    ///   - initialTypes: Optional fixed starting grid (rows of tile types).
    ///   - scriptedRefills: Tile types to use for refills before falling back to the seed.
    public init(
        config: GameConfig = GameConfig(),
        seed: UInt64 = .random(in: .min ... .max),
        initialTypes: [[Int]]? = nil,
        scriptedRefills: [Int] = []
    ) {
        self.config = config
        self.remaining = config.duration
        self.stringLength = config.startingLength
        self.generator = SeededGenerator(seed: seed)
        self.scriptedTypes = scriptedRefills[...]
        self.board = Board(rows: 0, columns: 0, cells: [])
        var cells: [Tile] = []
        for row in 0..<config.rows {
            for column in 0..<config.columns {
                cells.append(makeTile(type: initialTypes.map { $0[row][column] }))
            }
        }
        board = Board(rows: config.rows, columns: config.columns, cells: cells)
        _ = ensureSolvable()
    }

    // MARK: - Round lifecycle

    @discardableResult
    public mutating func startRound() -> [GameEvent] {
        guard phase == .ready else { return [] }
        phase = .playing
        return [.roundStarted] + beginFromHeldFinger()
    }

    @discardableResult
    public mutating func tick(_ seconds: TimeInterval) -> [GameEvent] {
        guard !isPaused, seconds.isFinite, phase != .ready, phase != .gameOver, remaining > 0 else { return [] }
        remaining = max(0, remaining - max(0, seconds))
        guard remaining == 0, phase != .resolvingMatch else { return [] }
        if let resolution = commitSelection() {
            fingerDown = false
            awaitingRelease = false
            return [.matched(resolution)]
        }
        return endRound()
    }

    /// Call when the match animation has finished.
    @discardableResult
    public mutating func finishResolving() -> [GameEvent] {
        guard phase == .resolvingMatch else { return [] }
        if remaining == 0 { return [.resolvingFinished] + endRound() }
        phase = .playing
        return [.resolvingFinished] + beginFromHeldFinger()
    }

    /// Freezes the clock and drops any gesture in progress; a committed match stays committed.
    @discardableResult
    public mutating func pause() -> [GameEvent] {
        guard !isPaused else { return [] }
        isPaused = true
        return releaseFinger()
    }

    public mutating func resume() { isPaused = false }

    // MARK: - Selection

    public var canAcceptInput: Bool { !isPaused && (phase == .playing || phase == .selecting) }

    /// Length of the string between selected tiles, in tile units.
    public var selectionLength: Double {
        zip(selection, selection.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    public var remainingLength: Double { max(0, stringLength - selectionLength) }

    /// A connection the current string can make, if any.
    public var availableMatch: [Position]? { board.findMatch(maxLength: stringLength) }

    /// Whether `position` would be accepted as the next tile of the current selection.
    public func canExtend(to position: Position) -> Bool {
        rejectionForExtending(to: position) == nil
    }

    public mutating func beginSelection(at position: Position) -> SelectionResult {
        guard !isPaused, phase == .playing, !awaitingRelease else { return .rejected(.notAccepting) }
        guard config.contains(position) else { return .rejected(.outOfBounds) }
        selection = [position]
        phase = .selecting
        return .selected
    }

    public mutating func extendSelection(to position: Position) -> SelectionResult {
        if let rejection = rejectionForExtending(to: position) { return .rejected(rejection) }
        selection.append(position)
        // With nothing further in reach, there's no reason to wait for the finger to lift.
        guard selection.count >= config.matchSize,
              !board.positions.contains(where: canExtend) else { return .selected }
        return .matched(commitMatch())
    }

    /// Commits the current selection if it has enough tiles.
    public mutating func commitSelection() -> MatchResolution? {
        guard phase == .selecting, selection.count >= config.matchSize else { return nil }
        return commitMatch()
    }

    public mutating func cancelSelection() -> [Position] {
        guard phase == .selecting else { return [] }
        let cancelled = selection
        selection = []
        phase = .playing
        return cancelled
    }

    private func rejectionForExtending(to position: Position) -> SelectionRejection? {
        guard !isPaused else { return .notAccepting }
        guard phase == .selecting, let first = selection.first, let last = selection.last else {
            return .noActiveSelection
        }
        guard config.contains(position) else { return .outOfBounds }
        guard !selection.contains(position) else { return .duplicateTile }
        guard board[position].type == board[first].type else { return .typeMismatch }
        guard selectionLength + last.distance(to: position) <= stringLength + Self.lengthTolerance else {
            return .stringTooLong
        }
        return nil
    }

    // MARK: - Touch input

    /// A new finger. Only one finger is tracked, so this also implies any earlier finger lifted.
    @discardableResult
    public mutating func touchDown(at point: BoardPoint) -> [GameEvent] {
        guard !isPaused, phase != .gameOver, point.isFinite else { return [] }
        var events = releaseFinger()
        fingerDown = true
        lastPoint = point
        events += beginFromHeldFinger()
        return events
    }

    /// Feeds a finger movement. The path since the last sample is interpolated so that a fast
    /// swipe registers every tile it crossed, in order.
    @discardableResult
    public mutating func touchMoved(to point: BoardPoint) -> [GameEvent] {
        guard fingerDown, point.isFinite, let previous = lastPoint else { return [] }
        lastPoint = point
        guard canAcceptInput, !awaitingRelease else { return [] }
        var events: [GameEvent] = []
        for sample in Self.samples(from: previous, to: point) {
            guard let tile = hitTile(at: sample) else {
                lastHit = nil
                continue
            }
            guard tile != lastHit else { continue }
            lastHit = tile
            if phase == .playing {
                _ = beginSelection(at: tile)
                events.append(selectedEvent(for: tile))
                continue
            }
            switch extendSelection(to: tile) {
            case .selected:
                events.append(selectedEvent(for: tile))
            case .matched(let resolution):
                events.append(.matched(resolution))
                return events
            case .rejected:
                break
            }
        }
        return events
    }

    /// The finger lifted or the system cancelled the touch. Commits a selection of 3 or more
    /// tiles and drops a shorter one.
    @discardableResult
    public mutating func touchUp() -> [GameEvent] { releaseFinger() }

    private mutating func releaseFinger() -> [GameEvent] {
        fingerDown = false
        awaitingRelease = false
        lastPoint = nil
        lastHit = nil
        if let resolution = commitSelection() {
            awaitingRelease = false
            return [.matched(resolution)]
        }
        let cancelled = cancelSelection()
        return cancelled.isEmpty ? [] : [.selectionCancelled(cancelled)]
    }

    /// Starts a selection under a finger that is already down, so a touch landing during the
    /// short lock-out of the intro or a match animation isn't lost.
    private mutating func beginFromHeldFinger() -> [GameEvent] {
        guard fingerDown, !awaitingRelease, let point = lastPoint else { return [] }
        let tile = Position(Int(floor(point.y)), Int(floor(point.x)))
        guard config.contains(tile), case .selected = beginSelection(at: tile) else { return [] }
        lastHit = tile
        return [selectedEvent(for: tile)]
    }

    private func selectedEvent(for position: Position) -> GameEvent {
        .tileSelected(board[position], at: position, index: selection.count - 1)
    }

    private func hitTile(at point: BoardPoint) -> Position? {
        let tile = Position(Int(floor(point.y)), Int(floor(point.x)))
        guard config.contains(tile), point.distance(to: BoardPoint(center: tile)) <= Self.hitRadius else {
            return nil
        }
        return tile
    }

    /// Evenly spaced points after `start`, ending exactly at `end`.
    static func samples(from start: BoardPoint, to end: BoardPoint) -> [BoardPoint] {
        let count = min(4096, max(1, Int((start.distance(to: end) / sampleStep).rounded(.up))))
        return (1...count).map { index in
            let t = Double(index) / Double(count)
            return BoardPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
        }
    }

    // MARK: - Match resolution

    private mutating func commitMatch() -> MatchResolution {
        let cleared = selection.map { ClearedTile(tile: board[$0], position: $0) }
        selection = []
        let raisedMultiplier = cleared.count > max(longestMatch, config.matchSize)
        if raisedMultiplier { multiplier += 1 }
        longestMatch = max(longestMatch, cleared.count)
        let points = config.pointsPerMatch * multiplier
        score += points
        matchCount += 1
        stringLength = min(config.lengthCap, stringLength + config.lengthGrowth)
        phase = .resolvingMatch
        awaitingRelease = true

        var moves: [TileMove] = []
        var spawns: [TileSpawn] = []
        for column in Set(cleared.map(\.position.column)).sorted() {
            let removedRows = Set(cleared.filter { $0.position.column == column }.map(\.position.row))
            var writeRow = config.rows - 1
            for readRow in stride(from: config.rows - 1, through: 0, by: -1) where !removedRows.contains(readRow) {
                let tile = board[Position(readRow, column)]
                if writeRow != readRow {
                    moves.append(TileMove(tile: tile, from: Position(readRow, column), to: Position(writeRow, column)))
                    board[Position(writeRow, column)] = tile
                }
                writeRow -= 1
            }
            let newCount = writeRow + 1
            for row in 0..<newCount {
                let tile = makeTile(type: nil)
                board[Position(row, column)] = tile
                spawns.append(TileSpawn(tile: tile, to: Position(row, column), entryRow: row - newCount))
            }
        }
        return MatchResolution(
            cleared: cleared,
            moves: moves,
            spawns: spawns,
            reshuffle: ensureSolvable(),
            points: points,
            multiplier: multiplier,
            raisedMultiplier: raisedMultiplier
        )
    }

    /// Reshuffles the existing tiles if the current string can't make any match, keeping the tile set intact.
    /// Returns the resulting tile movements.
    private mutating func ensureSolvable() -> [TileMove] {
        guard availableMatch == nil else { return [] }
        let before = board
        for _ in 0..<32 {
            board.shuffle(using: &generator)
            if availableMatch != nil { break }
        }
        if availableMatch == nil { board.gatherTrio() }
        var origins: [Int: Position] = [:]
        for position in before.positions { origins[before[position].id] = position }
        return board.positions.compactMap { position in
            let tile = board[position]
            guard let origin = origins[tile.id], origin != position else { return nil }
            return TileMove(tile: tile, from: origin, to: position)
        }
    }

    private mutating func endRound() -> [GameEvent] {
        var events: [GameEvent] = []
        let cancelled = cancelSelection()
        if !cancelled.isEmpty { events.append(.selectionCancelled(cancelled)) }
        fingerDown = false
        awaitingRelease = false
        phase = .gameOver
        events.append(.roundEnded(score: score, matches: matchCount))
        return events
    }

    private mutating func makeTile(type: Int?) -> Tile {
        defer { nextTileID += 1 }
        let raw = type ?? scriptedTypes.popFirst() ?? Int.random(in: 0..<config.types, using: &generator)
        return Tile(id: nextTileID, type: ((raw % config.types) + config.types) % config.types)
    }
}
