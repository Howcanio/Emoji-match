import XCTest
@testable import EmojiMatchCore

final class BoardGenerationTests: XCTestCase {
    func testInitialBoardHasConfiguredDimensionsAndTypes() {
        let engine = GameEngine(seed: 42)
        XCTAssertEqual(engine.board.types.count, 8)
        XCTAssertTrue(engine.board.types.allSatisfy { $0.count == 6 })
        XCTAssertTrue(engine.board.types.joined().allSatisfy { (0..<8).contains($0) })
        XCTAssertEqual(engine.phase, .ready)
        XCTAssertEqual(engine.score, 0)
        XCTAssertEqual(engine.remaining, 60)
    }

    func testRandomnessRespectsConfiguredTypeCount() {
        let config = GameConfig(rows: 8, columns: 6, types: 3)
        let engine = GameEngine(config: config, seed: 9)
        XCTAssertEqual(Set(engine.board.types.joined()), [0, 1, 2])
    }

    func testAllEightTypesAppearAcrossABoard() {
        let engine = GameEngine(seed: 3)
        XCTAssertEqual(Set(engine.board.types.joined()).count, 8)
    }

    func testSameSeedProducesSameBoardDifferentSeedsDiffer() {
        XCTAssertEqual(GameEngine(seed: 7).board.types, GameEngine(seed: 7).board.types)
        XCTAssertNotEqual(GameEngine(seed: 7).board.types, GameEngine(seed: 8).board.types)
    }

    func testTileIDsAreUnique() {
        let engine = GameEngine(seed: 5)
        XCTAssertEqual(Set(engine.board.positions.map { engine.board[$0].id }).count, 48)
    }

    func testOutOfRangeScriptedTypesAreNormalized() {
        var engine = runningEngine(types: stripedTypes(), refills: [-1, 8, 17])
        _ = engine.beginSelection(at: Position(5, 0))
        _ = engine.extendSelection(to: Position(6, 0))
        _ = engine.extendSelection(to: Position(7, 0))
        XCTAssertEqual(engine.board.types.map { $0[0] }.prefix(3), [7, 0, 1])
    }
}

final class SolvabilityTests: XCTestCase {
    func testFixtureIsAFullBoardWithAllTypesAndNoMatch() {
        let types = unsolvableTypes()
        XCTAssertEqual(Set(types.joined()).count, 8)
        let board = Board(
            rows: 8, columns: 6,
            cells: types.joined().enumerated().map { Tile(id: $0.offset, type: $0.element) }
        )
        XCTAssertNil(board.findMatch(maxLength: 5))
    }

    func testInitialBoardsAreAlwaysSolvable() {
        for seed in 0..<500 {
            let engine = GameEngine(seed: UInt64(seed))
            XCTAssertNotNil(engine.board.findMatch(maxLength: 5), "seed \(seed)")
        }
    }

    func testFoundMatchIsActuallyPlayable() {
        for seed in 0..<200 {
            var engine = runningEngine(seed: UInt64(seed))
            let path = try! XCTUnwrap(engine.board.findMatch(maxLength: 5))
            XCTAssertEqual(engine.beginSelection(at: path[0]), .selected)
            XCTAssertEqual(engine.extendSelection(to: path[1]), .selected)
            guard case .matched = engine.extendSelection(to: path[2]) else {
                return XCTFail("seed \(seed)")
            }
        }
    }

    func testSolvabilityCheckAcceptsPathOfExactlyMaxLength() {
        // Only three tiles of type 0: path lengths 2 + 3 = 5 exactly.
        var types = unsolvableTypes().map { $0.map { $0 == 0 ? 1 : $0 } }
        types[7][0] = 0; types[7][2] = 0; types[7][5] = 0
        let board = Board(rows: 8, columns: 6, cells: types.joined().enumerated().map { Tile(id: $0.offset, type: $0.element) })
        let path = board.findMatch(maxLength: 5)
        XCTAssertNotNil(path)
    }

    func testUnsolvableStartingBoardIsReshuffledKeepingTiles() {
        let types = unsolvableTypes()
        let engine = GameEngine(seed: 11, initialTypes: types)
        XCTAssertNotNil(engine.board.findMatch(maxLength: 5))
        XCTAssertEqual(engine.board.types.joined().sorted(), types.joined().sorted())
    }

    func testBoardStaysSolvableThroughManyMatches() {
        var engine = runningEngine(seed: 2024)
        for index in 0..<2000 {
            let path = try! XCTUnwrap(engine.board.findMatch(maxLength: 5), "match \(index)")
            _ = engine.beginSelection(at: path[0])
            _ = engine.extendSelection(to: path[1])
            _ = engine.extendSelection(to: path[2])
            engine.touchUp()
            engine.finishResolving()
        }
        XCTAssertEqual(engine.score, 200_000)
    }
}

final class ReshuffleTests: XCTestCase {
    /// Clearing column 5's bottom three type-5 tiles, refilled so the whole board is the lattice.
    func makeEngineThatNeedsReshuffle() -> GameEngine {
        var types = unsolvableTypes()
        let lattice = unsolvableTypes()
        // Rows 0-4 of column 5 hold what rows 3-7 must become; rows 5-7 are the matching trio.
        for row in 0..<5 { types[row][5] = lattice[row + 3][5] }
        for row in 5..<8 { types[row][5] = 0 }
        let refills = (0..<3).map { lattice[$0][5] }
        return runningEngine(types: types, refills: refills)
    }

    func testRefillThatLeavesNoMatchTriggersReshuffle() {
        var engine = makeEngineThatNeedsReshuffle()
        _ = engine.beginSelection(at: Position(5, 5))
        _ = engine.extendSelection(to: Position(6, 5))
        guard case .matched(let resolution) = engine.extendSelection(to: Position(7, 5)) else {
            return XCTFail("expected match")
        }
        XCTAssertFalse(resolution.reshuffle.isEmpty)
        XCTAssertNotNil(engine.board.findMatch(maxLength: 5))
        XCTAssertEqual(engine.board.types.joined().sorted(), unsolvableTypes().joined().sorted())
        for move in resolution.reshuffle {
            XCTAssertEqual(engine.board[move.to], move.tile)
            XCTAssertNotEqual(move.from, move.to)
        }
    }

    func testNoReshuffleWhenBoardRemainsSolvable() {
        var engine = runningEngine(types: stripedTypes())
        _ = engine.beginSelection(at: Position(0, 0))
        _ = engine.extendSelection(to: Position(1, 0))
        guard case .matched(let resolution) = engine.extendSelection(to: Position(2, 0)) else {
            return XCTFail("expected match")
        }
        XCTAssertTrue(resolution.reshuffle.isEmpty)
    }

    func testGatherTrioFallbackCreatesAMatchOnEveryShape() {
        for (rows, columns) in [(8, 6), (1, 3), (3, 1), (2, 2), (2, 5)] {
            // Spread three type-0 tiles to the end of the cell list, everything else distinct-ish.
            let count = rows * columns
            let cells = (0..<count).map { Tile(id: $0, type: $0 >= count - 3 ? 0 : $0 + 1) }
            var board = Board(rows: rows, columns: columns, cells: cells)
            board.gatherTrio()
            let path = board.findMatch(maxLength: 2)
            XCTAssertNotNil(path, "\(rows)x\(columns)")
        }
    }
}

final class SelectionTests: XCTestCase {
    func testSelectingMatchingTiles() {
        var engine = runningEngine(types: stripedTypes())
        XCTAssertEqual(engine.beginSelection(at: Position(0, 0)), .selected)
        XCTAssertEqual(engine.phase, .selecting)
        XCTAssertEqual(engine.extendSelection(to: Position(1, 0)), .selected)
        XCTAssertEqual(engine.selection, [Position(0, 0), Position(1, 0)])
    }

    func testNonMatchingTileIsRejectedAndSelectionKept() {
        var engine = runningEngine(types: stripedTypes())
        _ = engine.beginSelection(at: Position(0, 0))
        XCTAssertEqual(engine.extendSelection(to: Position(0, 1)), .rejected(.typeMismatch))
        XCTAssertEqual(engine.selection, [Position(0, 0)])
        XCTAssertEqual(engine.phase, .selecting)
    }

    func testDuplicateTileIsRejected() {
        var engine = runningEngine(types: stripedTypes())
        _ = engine.beginSelection(at: Position(0, 0))
        XCTAssertEqual(engine.extendSelection(to: Position(0, 0)), .rejected(.duplicateTile))
        _ = engine.extendSelection(to: Position(1, 0))
        XCTAssertEqual(engine.extendSelection(to: Position(0, 0)), .rejected(.duplicateTile))
        XCTAssertEqual(engine.extendSelection(to: Position(1, 0)), .rejected(.duplicateTile))
        XCTAssertEqual(engine.selection.count, 2)
    }

    func testOutOfBoundsRejected() {
        var engine = runningEngine(types: stripedTypes())
        XCTAssertEqual(engine.beginSelection(at: Position(8, 0)), .rejected(.outOfBounds))
        XCTAssertEqual(engine.beginSelection(at: Position(0, -1)), .rejected(.outOfBounds))
        _ = engine.beginSelection(at: Position(0, 0))
        XCTAssertEqual(engine.extendSelection(to: Position(0, 6)), .rejected(.outOfBounds))
    }

    func testExtendWithoutSelectionRejected() {
        var engine = runningEngine(types: stripedTypes())
        XCTAssertEqual(engine.extendSelection(to: Position(1, 0)), .rejected(.noActiveSelection))
    }

    func testSelectionNotAcceptedBeforeRoundStarts() {
        var engine = GameEngine(seed: 1, initialTypes: stripedTypes())
        XCTAssertEqual(engine.beginSelection(at: Position(0, 0)), .rejected(.notAccepting))
    }

    func testAnyDirectionIncludingDiagonalsAndSkipping() {
        var types = stripedTypes()
        types[2][2] = 0; types[3][1] = 0
        var engine = runningEngine(types: types)
        _ = engine.beginSelection(at: Position(0, 0))
        XCTAssertEqual(engine.extendSelection(to: Position(2, 2)), .selected) // skips (1,1); diagonal
        guard case .matched = engine.extendSelection(to: Position(3, 1)) else {
            return XCTFail("diagonal back-left should match")
        }
    }

    func testCanExtendMirrorsExtendSelection() {
        var engine = runningEngine(types: stripedTypes())
        _ = engine.beginSelection(at: Position(0, 0))
        XCTAssertTrue(engine.canExtend(to: Position(3, 0)))
        XCTAssertFalse(engine.canExtend(to: Position(0, 0)))
        XCTAssertFalse(engine.canExtend(to: Position(0, 1)))
        XCTAssertFalse(engine.canExtend(to: Position(7, 0)))
    }
}

final class StringLengthTests: XCTestCase {
    private func engine(typeZeroAt positions: [Position]) -> GameEngine {
        var types = (0..<8).map { _ in [Int](repeating: 1, count: 6) }
        for position in positions { types[position.row][position.column] = 0 }
        return runningEngine(types: types)
    }

    func testPathOfExactlyFiveMatches() {
        var engine = engine(typeZeroAt: [Position(0, 0), Position(0, 2), Position(0, 5)])
        _ = engine.beginSelection(at: Position(0, 0))
        XCTAssertEqual(engine.extendSelection(to: Position(0, 2)), .selected)
        XCTAssertEqual(engine.remainingLength, 3, accuracy: 1e-9)
        guard case .matched = engine.extendSelection(to: Position(0, 5)) else {
            return XCTFail("exactly 5 units must be allowed")
        }
    }

    func testPythagoreanSegmentOfExactlyFiveIsAllowed() {
        var engine = engine(typeZeroAt: [Position(0, 0), Position(4, 3), Position(7, 3)])
        _ = engine.beginSelection(at: Position(0, 0))
        XCTAssertEqual(engine.extendSelection(to: Position(4, 3)), .selected)
        XCTAssertEqual(engine.remainingLength, 0, accuracy: 1e-9)
        XCTAssertEqual(engine.extendSelection(to: Position(7, 3)), .rejected(.stringTooLong))
    }

    func testFirstSegmentJustOverFiveIsRejected() {
        var engine = engine(typeZeroAt: [Position(0, 0), Position(5, 1), Position(5, 2)])
        _ = engine.beginSelection(at: Position(0, 0))
        XCTAssertEqual(engine.extendSelection(to: Position(5, 1)), .rejected(.stringTooLong)) // √26
        XCTAssertEqual(engine.selection.count, 1)
    }

    func testCumulativeDistanceNotDirectDistance() {
        // Third tile is close to the first, but the cumulative path 3 + √(9+1) exceeds 5.
        var engine = engine(typeZeroAt: [Position(0, 0), Position(3, 0), Position(0, 1)])
        _ = engine.beginSelection(at: Position(0, 0))
        XCTAssertEqual(engine.extendSelection(to: Position(3, 0)), .selected)
        XCTAssertEqual(engine.extendSelection(to: Position(0, 1)), .rejected(.stringTooLong))
    }

    func testTooFarTileDoesNotEndSelectionAndNearerTileStillMatches() {
        var engine = engine(typeZeroAt: [Position(0, 0), Position(3, 0), Position(7, 5), Position(4, 0)])
        _ = engine.beginSelection(at: Position(0, 0))
        _ = engine.extendSelection(to: Position(3, 0))
        XCTAssertEqual(engine.extendSelection(to: Position(7, 5)), .rejected(.stringTooLong))
        guard case .matched = engine.extendSelection(to: Position(4, 0)) else {
            return XCTFail("nearer tile should match")
        }
    }
}

final class ClearingAndRefillTests: XCTestCase {
    func testThirdTileClearsAutomaticallyAndScores() {
        var engine = runningEngine(types: stripedTypes())
        _ = engine.beginSelection(at: Position(5, 0))
        _ = engine.extendSelection(to: Position(6, 0))
        guard case .matched(let resolution) = engine.extendSelection(to: Position(7, 0)) else {
            return XCTFail("expected match")
        }
        XCTAssertEqual(resolution.cleared.map(\.position), [Position(5, 0), Position(6, 0), Position(7, 0)])
        XCTAssertEqual(resolution.points, 100)
        XCTAssertEqual(engine.score, 100)
        XCTAssertEqual(engine.matchCount, 1)
        XCTAssertEqual(engine.phase, .resolvingMatch)
        XCTAssertTrue(engine.selection.isEmpty)
    }

    func testGravityInSingleColumn() {
        var types = stripedTypes()
        for row in 0..<5 { types[row][0] = 10 + row } // 10...14 normalize to types 2...6
        var engine = runningEngine(types: types, refills: [1, 2, 3])
        let idsAbove = (0..<5).map { engine.board[Position($0, 0)].id }
        _ = engine.beginSelection(at: Position(5, 0))
        _ = engine.extendSelection(to: Position(6, 0))
        guard case .matched(let resolution) = engine.extendSelection(to: Position(7, 0)) else {
            return XCTFail("expected match")
        }
        XCTAssertEqual((3..<8).map { engine.board[Position($0, 0)].id }, idsAbove, "survivors keep order")
        XCTAssertEqual((0..<3).map { engine.board[Position($0, 0)].type }, [1, 2, 3], "refills enter top-down")
        XCTAssertEqual(resolution.moves.count, 5)
        XCTAssertTrue(resolution.moves.allSatisfy { $0.to.row == $0.from.row + 3 && $0.to.column == 0 })
        XCTAssertEqual(resolution.spawns.map(\.entryRow), [-3, -2, -1])
        XCTAssertEqual(resolution.spawns.map(\.to.row), [0, 1, 2])
    }

    func testGravityMovesOnlyAffectedColumns() {
        var types = stripedTypes()
        types[1][1] = 0; types[3][2] = 0
        var engine = runningEngine(types: types)
        let before = engine.board
        _ = engine.beginSelection(at: Position(2, 0))
        _ = engine.extendSelection(to: Position(1, 1))
        guard case .matched(let resolution) = engine.extendSelection(to: Position(3, 2)) else {
            return XCTFail("expected match")
        }
        for column in 3..<6 {
            for row in 0..<8 {
                XCTAssertEqual(engine.board[Position(row, column)], before[Position(row, column)])
            }
        }
        XCTAssertEqual(resolution.spawns.count, 3)
        XCTAssertEqual(Set(resolution.spawns.map(\.to.column)), [0, 1, 2])
        // Tiles below a removed cell don't move.
        XCTAssertEqual(engine.board[Position(4, 2)], before[Position(4, 2)])
        // Tiles above the removed cell shift down one.
        XCTAssertEqual(engine.board[Position(3, 2)], before[Position(2, 2)])
    }

    func testTwoRemovedInOneColumnWithGap() {
        var types = stripedTypes()
        types[4][0] = 2 // Interrupts column 0; rows 3 and 5 still type 0.
        var engine = runningEngine(types: types, refills: [3, 4, 5])
        let interruptor = engine.board[Position(4, 0)]
        let row2 = engine.board[Position(2, 0)]
        _ = engine.beginSelection(at: Position(3, 0))
        _ = engine.extendSelection(to: Position(5, 0))
        guard case .matched = engine.extendSelection(to: Position(6, 0)) else {
            return XCTFail("expected match")
        }
        XCTAssertEqual(engine.board[Position(6, 0)], interruptor)
        XCTAssertEqual(engine.board[Position(5, 0)], row2)
    }

    func testBoardStaysFullWithUniqueIDsAfterEveryMatch() {
        var engine = runningEngine(seed: 77)
        for _ in 0..<200 {
            let path = engine.board.findMatch(maxLength: 5)!
            _ = engine.beginSelection(at: path[0])
            _ = engine.extendSelection(to: path[1])
            _ = engine.extendSelection(to: path[2])
            engine.touchUp()
            engine.finishResolving()
            XCTAssertEqual(engine.phase, .playing)
            XCTAssertEqual(Set(engine.board.positions.map { engine.board[$0].id }).count, 48)
        }
    }

    func testResolutionDescribesEveryTileThatChangedPosition() {
        var engine = runningEngine(seed: 123)
        let before = engine.board
        let path = engine.board.findMatch(maxLength: 5)!
        _ = engine.beginSelection(at: path[0])
        _ = engine.extendSelection(to: path[1])
        guard case .matched(let resolution) = engine.extendSelection(to: path[2]) else {
            return XCTFail("expected match")
        }
        // Replay the resolution on the old board's IDs: it must reproduce the new board.
        var positions: [Int: Position] = [:]
        for position in before.positions { positions[before[position].id] = position }
        for cleared in resolution.cleared { positions[cleared.tile.id] = nil }
        for move in resolution.moves { positions[move.tile.id] = move.to }
        for spawn in resolution.spawns { positions[spawn.tile.id] = spawn.to }
        for move in resolution.reshuffle { positions[move.tile.id] = move.to }
        for position in engine.board.positions {
            XCTAssertEqual(positions[engine.board[position].id], position)
        }
    }
}

final class ScoringAndStateTests: XCTestCase {
    func testEachMatchScoresExactly100NoMultiplier() {
        var engine = runningEngine(seed: 4)
        for expected in stride(from: 100, through: 1000, by: 100) {
            let path = engine.board.findMatch(maxLength: 5)!
            _ = engine.beginSelection(at: path[0])
            _ = engine.extendSelection(to: path[1])
            _ = engine.extendSelection(to: path[2])
            engine.touchUp()
            engine.finishResolving()
            XCTAssertEqual(engine.score, expected)
        }
        XCTAssertEqual(engine.matchCount, 10)
    }

    func testNoCascades() {
        // A match whose gravity lines up three more of a type must not score again by itself.
        var engine = runningEngine(types: stripedTypes())
        _ = engine.beginSelection(at: Position(5, 0))
        _ = engine.extendSelection(to: Position(6, 0))
        _ = engine.extendSelection(to: Position(7, 0))
        engine.finishResolving()
        XCTAssertEqual(engine.score, 100)
        XCTAssertEqual(engine.phase, .playing)
    }

    func testInputRejectedWhileResolvingCannotCorruptBoard() {
        var engine = runningEngine(types: stripedTypes())
        _ = engine.beginSelection(at: Position(5, 0))
        _ = engine.extendSelection(to: Position(6, 0))
        _ = engine.extendSelection(to: Position(7, 0))
        let snapshot = engine.board
        XCTAssertEqual(engine.beginSelection(at: Position(0, 1)), .rejected(.notAccepting))
        XCTAssertEqual(engine.extendSelection(to: Position(1, 1)), .rejected(.noActiveSelection))
        XCTAssertTrue(engine.touchMoved(to: BoardPoint(center: Position(1, 1))).isEmpty)
        XCTAssertEqual(engine.board, snapshot)
        XCTAssertEqual(engine.score, 100)
    }

    func testFinishResolvingOutsideResolvingIsNoOp() {
        var engine = runningEngine(types: stripedTypes())
        XCTAssertTrue(engine.finishResolving().isEmpty)
        XCTAssertEqual(engine.phase, .playing)
    }

    func testStartRoundOnlyFromReady() {
        var engine = runningEngine(types: stripedTypes())
        XCTAssertTrue(engine.startRound().isEmpty)
        engine.tick(60)
        XCTAssertTrue(engine.startRound().isEmpty)
        XCTAssertEqual(engine.phase, .gameOver)
    }
}

final class TimerTests: XCTestCase {
    func testClockDoesNotRunBeforeRoundStarts() {
        var engine = GameEngine(seed: 1)
        engine.tick(10)
        XCTAssertEqual(engine.remaining, 60)
        XCTAssertEqual(engine.phase, .ready)
    }

    func testExpiryEndsRoundOnce() {
        var engine = runningEngine(types: stripedTypes())
        engine.tick(59.5)
        XCTAssertEqual(engine.phase, .playing)
        let events = engine.tick(0.5)
        XCTAssertEqual(engine.remaining, 0)
        XCTAssertEqual(engine.phase, .gameOver)
        XCTAssertEqual(events, [.roundEnded(score: 0, matches: 0)])
        XCTAssertTrue(engine.tick(1).isEmpty)
    }

    func testOverlongTickClampsToZero() {
        var engine = runningEngine(types: stripedTypes())
        engine.tick(1000)
        XCTAssertEqual(engine.remaining, 0)
    }

    func testNegativeAndNonFiniteTicksAreIgnored() {
        var engine = runningEngine(types: stripedTypes())
        engine.tick(-5)
        engine.tick(.nan)
        engine.tick(.infinity)
        XCTAssertEqual(engine.remaining, 60)
    }

    func testExpiryCancelsIncompleteSelection() {
        var engine = runningEngine(types: stripedTypes())
        _ = engine.beginSelection(at: Position(0, 0))
        _ = engine.extendSelection(to: Position(1, 0))
        let events = engine.tick(60)
        XCTAssertEqual(events.first, .selectionCancelled([Position(0, 0), Position(1, 0)]))
        XCTAssertEqual(events.last, .roundEnded(score: 0, matches: 0))
        XCTAssertTrue(engine.selection.isEmpty)
        XCTAssertEqual(engine.score, 0)
    }

    func testExpiryDuringResolvingFinishesCommittedMatchThenEnds() {
        var engine = runningEngine(types: stripedTypes())
        _ = engine.beginSelection(at: Position(5, 0))
        _ = engine.extendSelection(to: Position(6, 0))
        _ = engine.extendSelection(to: Position(7, 0))
        XCTAssertTrue(engine.tick(60).isEmpty)
        XCTAssertEqual(engine.phase, .resolvingMatch, "committed match still animating")
        XCTAssertEqual(engine.remaining, 0)
        let events = engine.finishResolving()
        XCTAssertEqual(events, [.resolvingFinished, .roundEnded(score: 100, matches: 1)])
        XCTAssertEqual(engine.phase, .gameOver)
    }

    func testClockKeepsRunningWhileResolving() {
        var engine = runningEngine(types: stripedTypes())
        _ = engine.beginSelection(at: Position(5, 0))
        _ = engine.extendSelection(to: Position(6, 0))
        _ = engine.extendSelection(to: Position(7, 0))
        engine.tick(1)
        XCTAssertEqual(engine.remaining, 59)
    }

    func testNoInputAfterGameOver() {
        var engine = runningEngine(types: stripedTypes())
        engine.tick(60)
        XCTAssertTrue(engine.touchDown(at: BoardPoint(center: Position(0, 0))).isEmpty)
        XCTAssertEqual(engine.beginSelection(at: Position(0, 0)), .rejected(.notAccepting))
    }

    func testRoundClockFirstFrameIsZeroAndGapsAreCapped() {
        var clock = RoundClock(maxStep: 0.25)
        XCTAssertEqual(clock.delta(now: 100), 0)
        XCTAssertEqual(clock.delta(now: 100.1), 0.1, accuracy: 1e-9)
        XCTAssertEqual(clock.delta(now: 500), 0.25)
        clock.reset()
        XCTAssertEqual(clock.delta(now: 900), 0)
        XCTAssertEqual(clock.delta(now: 899), 0, "time going backward")
    }
}

final class PauseResumeTests: XCTestCase {
    func testPauseFreezesClockAndResumeContinues() {
        var engine = runningEngine(types: stripedTypes())
        engine.tick(10)
        engine.pause()
        engine.tick(30)
        XCTAssertEqual(engine.remaining, 50)
        engine.resume()
        engine.tick(5)
        XCTAssertEqual(engine.remaining, 45)
    }

    func testBackgroundingCancelsGestureInProgress() {
        var engine = runningEngine(types: stripedTypes())
        engine.touchDown(at: BoardPoint(center: Position(0, 0)))
        let events = engine.pause()
        XCTAssertEqual(events, [.selectionCancelled([Position(0, 0)])])
        XCTAssertEqual(engine.phase, .playing)
    }

    func testInputIgnoredWhilePaused() {
        var engine = runningEngine(types: stripedTypes())
        engine.pause()
        XCTAssertTrue(engine.touchDown(at: BoardPoint(center: Position(0, 0))).isEmpty)
        XCTAssertEqual(engine.beginSelection(at: Position(0, 0)), .rejected(.notAccepting))
    }

    func testFingerHeldAcrossPauseMustTouchDownAgain() {
        var engine = runningEngine(types: stripedTypes())
        engine.touchDown(at: BoardPoint(center: Position(0, 0)))
        engine.pause()
        engine.resume()
        XCTAssertTrue(engine.touchMoved(to: BoardPoint(center: Position(1, 0))).isEmpty)
        XCTAssertTrue(engine.selection.isEmpty)
        XCTAssertEqual(engine.touchDown(at: BoardPoint(center: Position(1, 0))).selectedPositions, [Position(1, 0)])
    }

    func testPauseDuringResolvingKeepsCommittedMatch() {
        var engine = runningEngine(types: stripedTypes())
        _ = engine.beginSelection(at: Position(5, 0))
        _ = engine.extendSelection(to: Position(6, 0))
        _ = engine.extendSelection(to: Position(7, 0))
        engine.pause()
        XCTAssertEqual(engine.phase, .resolvingMatch)
        XCTAssertEqual(engine.score, 100)
        engine.resume()
        engine.finishResolving()
        XCTAssertEqual(engine.phase, .playing)
    }

    func testPauseIsIdempotentAndCannotEndRound() {
        var engine = runningEngine(types: stripedTypes())
        engine.pause()
        XCTAssertTrue(engine.pause().isEmpty)
        engine.tick(100)
        XCTAssertEqual(engine.phase, .playing)
        XCTAssertEqual(engine.remaining, 60)
    }
}

final class TouchInputTests: XCTestCase {
    private func center(_ row: Int, _ column: Int) -> BoardPoint { BoardPoint(center: Position(row, column)) }

    func testTouchDownSelectsAnywhereInCell() {
        var engine = runningEngine(types: stripedTypes())
        let events = engine.touchDown(at: BoardPoint(x: 0.02, y: 0.98))
        XCTAssertEqual(events.selectedPositions, [Position(0, 0)])
    }

    func testSlowDragCompletesMatch() {
        var engine = runningEngine(types: stripedTypes())
        engine.touchDown(at: center(0, 0))
        var points: [BoardPoint] = []
        for step in 1...40 { points.append(BoardPoint(x: 0.5, y: 0.5 + Double(step) * 0.05)) }
        let events = points.flatMap { engine.touchMoved(to: $0) }
        XCTAssertEqual(events.selectedPositions, [Position(1, 0)])
        XCTAssertEqual(events.resolution?.cleared.map(\.position), [Position(0, 0), Position(1, 0), Position(2, 0)])
    }

    func testRapidSwipeInOneEventRegistersEveryCrossedTileInOrder() {
        var engine = runningEngine(types: stripedTypes())
        engine.touchDown(at: center(0, 0))
        // One event spanning 4 tiles straight down: crosses (1,0) and (2,0), which complete the match.
        let events = engine.touchMoved(to: center(4, 0))
        XCTAssertEqual(events.resolution?.cleared.map(\.position), [Position(0, 0), Position(1, 0), Position(2, 0)])
        XCTAssertEqual(engine.phase, .resolvingMatch)
    }

    func testRapidDiagonalSwipeIsInterpolated() {
        var types = stripedTypes()
        types[1][1] = 0; types[2][2] = 0
        var engine = runningEngine(types: types)
        engine.touchDown(at: center(0, 0))
        let events = engine.touchMoved(to: center(3, 3))
        XCTAssertEqual(events.resolution?.cleared.map(\.position), [Position(0, 0), Position(1, 1), Position(2, 2)])
    }

    func testRapidSwipeSkipsNonMatchingTilesWithoutEndingGesture() {
        var engine = runningEngine(types: stripedTypes())
        engine.touchDown(at: center(0, 1))
        // Across the row: all other columns are non-matching.
        XCTAssertTrue(engine.touchMoved(to: center(0, 5)).isEmpty)
        XCTAssertEqual(engine.selection, [Position(0, 1)])
        XCTAssertEqual(engine.phase, .selecting)
    }

    func testDiagonalDragBetweenTilesDoesNotCatchCorners() {
        var types = (0..<8).map { _ in [Int](repeating: 1, count: 6) }
        types[0][0] = 0; types[1][1] = 0; types[0][1] = 0; types[1][0] = 0
        var engine = runningEngine(types: types)
        engine.touchDown(at: center(0, 0))
        let events = engine.touchMoved(to: center(1, 1))
        XCTAssertEqual(events.selectedPositions, [Position(1, 1)], "the corners of (0,1) and (1,0) aren't hit")
    }

    func testSamplesAreDenseAndEndExactly() {
        let start = BoardPoint(x: 0, y: 0), end = BoardPoint(x: 5, y: 7)
        let samples = GameEngine.samples(from: start, to: end)
        XCTAssertEqual(samples.last, end)
        var previous = start
        for sample in samples {
            XCTAssertLessThanOrEqual(previous.distance(to: sample), GameEngine.sampleStep + 1e-9)
            previous = sample
        }
    }

    func testZeroLengthMoveIsHarmless() {
        XCTAssertEqual(GameEngine.samples(from: BoardPoint(x: 1, y: 1), to: BoardPoint(x: 1, y: 1)).count, 1)
        var engine = runningEngine(types: stripedTypes())
        engine.touchDown(at: center(0, 0))
        XCTAssertTrue(engine.touchMoved(to: center(0, 0)).isEmpty)
    }

    func testIncompleteSelectionDisappearsOnRelease() {
        var engine = runningEngine(types: stripedTypes())
        engine.touchDown(at: center(0, 0))
        _ = engine.touchMoved(to: center(1, 0))
        let events = engine.touchUp()
        XCTAssertEqual(events, [.selectionCancelled([Position(0, 0), Position(1, 0)])])
        XCTAssertTrue(engine.selection.isEmpty)
        XCTAssertEqual(engine.phase, .playing)
        XCTAssertEqual(engine.score, 0)
    }

    func testMatchEndsGestureAndRequiresRelease() {
        var engine = runningEngine(types: stripedTypes())
        engine.touchDown(at: center(5, 0))
        _ = engine.touchMoved(to: center(7, 0))
        XCTAssertEqual(engine.score, 100)
        XCTAssertTrue(engine.awaitingRelease)
        engine.finishResolving()
        XCTAssertEqual(engine.phase, .playing)
        // Finger still down and moving over matching tiles: nothing happens.
        XCTAssertTrue(engine.touchMoved(to: center(7, 1)).isEmpty)
        XCTAssertTrue(engine.touchMoved(to: center(4, 1)).isEmpty)
        XCTAssertTrue(engine.selection.isEmpty)
        XCTAssertEqual(engine.score, 100)
        engine.touchUp()
        XCTAssertFalse(engine.awaitingRelease)
        XCTAssertEqual(engine.touchDown(at: center(7, 1)).selectedPositions, [Position(7, 1)])
    }

    func testRepeatedMatchesViaFullGesturesAcrossManyRounds() {
        var engine = runningEngine(seed: 31)
        for iteration in 1...100 {
            let path = engine.board.findMatch(maxLength: 5)!
            engine.touchDown(at: BoardPoint(center: path[0]))
            // Jump tile to tile via direct selection events, so non-target same-type tiles in the
            // straight line can't intervene.
            _ = engine.extendSelection(to: path[1])
            _ = engine.extendSelection(to: path[2])
            XCTAssertEqual(engine.score, iteration * 100)
            engine.touchUp()
            engine.finishResolving()
            XCTAssertEqual(engine.phase, .playing)
        }
    }

    func testTouchDuringResolvingIsBufferedAndStartsWhenResolved() {
        var engine = runningEngine(types: stripedTypes())
        engine.touchDown(at: center(5, 0))
        _ = engine.touchMoved(to: center(7, 0))
        engine.touchUp()
        XCTAssertTrue(engine.touchDown(at: center(0, 1)).isEmpty, "locked out while resolving")
        _ = engine.touchMoved(to: center(0, 2))
        let events = engine.finishResolving()
        XCTAssertEqual(events.selectedPositions, [Position(0, 2)], "starts under the finger's current location")
    }

    func testTouchLiftedDuringResolvingDoesNothingLater() {
        var engine = runningEngine(types: stripedTypes())
        engine.touchDown(at: center(5, 0))
        _ = engine.touchMoved(to: center(7, 0))
        engine.touchUp()
        engine.touchDown(at: center(0, 1))
        engine.touchUp()
        XCTAssertEqual(engine.finishResolving(), [.resolvingFinished])
        XCTAssertEqual(engine.phase, .playing)
    }

    func testTouchHeldThroughIntroStartsAtRoundStart() {
        var engine = GameEngine(seed: 1, initialTypes: stripedTypes())
        XCTAssertTrue(engine.touchDown(at: center(0, 0)).isEmpty)
        let events = engine.startRound()
        XCTAssertEqual(events.first, .roundStarted)
        XCTAssertEqual(events.selectedPositions, [Position(0, 0)])
    }

    func testTouchStartedOffBoardCanDragOntoBoard() {
        var engine = runningEngine(types: stripedTypes())
        XCTAssertTrue(engine.touchDown(at: BoardPoint(x: -1, y: 0.5)).isEmpty)
        XCTAssertEqual(engine.touchMoved(to: center(0, 0)).selectedPositions, [Position(0, 0)])
    }

    func testDraggingOffBoardKeepsSelectionUntilRelease() {
        var engine = runningEngine(types: stripedTypes())
        engine.touchDown(at: center(0, 0))
        XCTAssertTrue(engine.touchMoved(to: BoardPoint(x: -3, y: -3)).isEmpty)
        XCTAssertEqual(engine.selection, [Position(0, 0)])
        _ = engine.touchMoved(to: center(1, 0))
        XCTAssertEqual(engine.selection, [Position(0, 0), Position(1, 0)])
    }

    func testMoveAndReleaseWithoutTouchDownAreIgnored() {
        var engine = runningEngine(types: stripedTypes())
        XCTAssertTrue(engine.touchMoved(to: center(0, 0)).isEmpty)
        XCTAssertTrue(engine.touchUp().isEmpty)
        XCTAssertEqual(engine.phase, .playing)
    }

    func testNonFinitePointsAreIgnored() {
        var engine = runningEngine(types: stripedTypes())
        XCTAssertTrue(engine.touchDown(at: BoardPoint(x: .nan, y: 0)).isEmpty)
        engine.touchDown(at: center(0, 0))
        XCTAssertTrue(engine.touchMoved(to: BoardPoint(x: .infinity, y: 0)).isEmpty)
        XCTAssertEqual(engine.selection, [Position(0, 0)])
    }

    func testSecondTouchDownWithoutReleaseRestartsSelection() {
        var engine = runningEngine(types: stripedTypes())
        engine.touchDown(at: center(0, 0))
        let events = engine.touchDown(at: center(0, 1))
        XCTAssertEqual(events.first, .selectionCancelled([Position(0, 0)]))
        XCTAssertEqual(engine.selection, [Position(0, 1)])
    }

    func testLostTouchEndCannotWedgeAwaitingRelease() {
        var engine = runningEngine(types: stripedTypes())
        engine.touchDown(at: center(5, 0))
        _ = engine.touchMoved(to: center(7, 0))
        engine.finishResolving()
        XCTAssertEqual(engine.touchDown(at: center(0, 1)).selectedPositions, [Position(0, 1)])
    }

    func testFuzzedTouchStreamKeepsInvariants() {
        var generator = SeededGenerator(seed: 2026)
        var engine = runningEngine(seed: 99)
        for _ in 0..<50_000 {
            let point = BoardPoint(x: .random(in: -2...8, using: &generator), y: .random(in: -2...10, using: &generator))
            switch Int.random(in: 0..<10, using: &generator) {
            case 0: engine.touchDown(at: point)
            case 1: engine.touchUp()
            case 2: engine.finishResolving()
            default: engine.touchMoved(to: point)
            }
            XCTAssertLessThan(engine.selection.count, 3)
            XCTAssertEqual(engine.score, engine.matchCount * 100)
            XCTAssertEqual(engine.phase == .selecting, !engine.selection.isEmpty)
            if engine.phase == .selecting {
                XCTAssertLessThanOrEqual(engine.selectionLength, 5 + 1e-9)
                XCTAssertEqual(Set(engine.selection).count, engine.selection.count)
                XCTAssertEqual(Set(engine.selection.map { engine.board[$0].type }).count, 1)
            }
        }
        XCTAssertGreaterThan(engine.matchCount, 0)
    }
}

final class HighScoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "EmojiMatchTests.highscore"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    func testStartsAtZero() {
        XCTAssertEqual(HighScoreStore(defaults: defaults).best, 0)
    }

    func testRecordsOnlyImprovements() {
        let store = HighScoreStore(defaults: defaults)
        XCTAssertTrue(store.record(300))
        XCTAssertFalse(store.record(200))
        XCTAssertFalse(store.record(300))
        XCTAssertEqual(store.best, 300)
        XCTAssertTrue(store.record(400))
        XCTAssertEqual(store.best, 400)
    }

    func testZeroIsNotARecord() {
        XCTAssertFalse(HighScoreStore(defaults: defaults).record(0))
    }

    func testPersistsAcrossInstances() {
        HighScoreStore(defaults: defaults).record(1200)
        defaults.synchronize()
        let reopened = UserDefaults(suiteName: suite)!
        XCTAssertEqual(HighScoreStore(defaults: reopened).best, 1200)
    }

    func testCorruptNegativeValueTreatedAsZero() {
        defaults.set(-50, forKey: HighScoreStore.key)
        XCTAssertEqual(HighScoreStore(defaults: defaults).best, 0)
        XCTAssertTrue(HighScoreStore(defaults: defaults).record(100))
    }
}
