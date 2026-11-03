import Foundation

public struct Board: Equatable, Sendable {
    public let rows: Int
    public let columns: Int
    fileprivate(set) var cells: [Tile]

    init(rows: Int, columns: Int, cells: [Tile]) {
        precondition(cells.count == rows * columns)
        self.rows = rows
        self.columns = columns
        self.cells = cells
    }

    public subscript(position: Position) -> Tile {
        get { cells[position.row * columns + position.column] }
        set { cells[position.row * columns + position.column] = newValue }
    }

    /// Tile types as a row-major grid.
    public var types: [[Int]] {
        (0..<rows).map { row in (0..<columns).map { self[Position(row, $0)].type } }
    }

    public var positions: [Position] {
        (0..<rows).flatMap { row in (0..<columns).map { Position(row, $0) } }
    }

    /// Returns a valid 3-tile connection in selection order, or nil if the board has none.
    /// For each candidate middle tile only its two nearest same-type tiles need checking.
    public func findMatch(maxLength: Double) -> [Position]? {
        var byType: [Int: [Position]] = [:]
        for position in positions { byType[self[position].type, default: []].append(position) }
        for group in byType.values where group.count >= 3 {
            for middle in group {
                let nearest = group.filter { $0 != middle }
                    .sorted { $0.distance(to: middle) < $1.distance(to: middle) }
                if nearest[0].distance(to: middle) + nearest[1].distance(to: middle)
                    <= maxLength + GameEngine.lengthTolerance {
                    return [nearest[0], middle, nearest[1]]
                }
            }
        }
        return nil
    }

    mutating func shuffle<G: RandomNumberGenerator>(using generator: inout G) {
        cells.shuffle(using: &generator)
    }

    /// Deterministically gathers three tiles of the most common type into adjacent cells.
    mutating func gatherTrio() {
        var counts: [Int: Int] = [:]
        for tile in cells { counts[tile.type, default: 0] += 1 }
        guard let type = counts.max(by: { ($0.value, $1.key) < ($1.value, $0.key) })?.key else { return }
        let targets: [Position]
        if columns >= 3 {
            targets = (0..<3).map { Position(0, $0) }
        } else if rows >= 3 {
            targets = (0..<3).map { Position($0, 0) }
        } else {
            targets = [Position(0, 1), Position(0, 0), Position(1, 0)]
        }
        var sources = positions.filter { !targets.contains($0) && self[$0].type == type }
        for target in targets where self[target].type != type {
            guard let source = sources.popLast() else { return }
            let displaced = self[target]
            self[target] = self[source]
            self[source] = displaced
        }
    }
}
