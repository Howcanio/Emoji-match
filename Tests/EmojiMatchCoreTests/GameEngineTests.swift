import XCTest
@testable import EmojiMatchCore

final class GameEngineTests: XCTestCase {
    func testInitialBoardIsSolvable() {
        let game = GameEngine(randomType: { 0 })
        XCTAssertTrue(game.hasMatch())
        XCTAssertEqual(game.board.count, 8)
        XCTAssertEqual(game.board[0].count, 6)
    }
    func testMatchAwardsExactly100() {
        var game = GameEngine(randomType: { 0 })
        game.start(at: Position(0,0))
        XCTAssertFalse(game.visit(Position(0,1)))
        XCTAssertTrue(game.visit(Position(0,2)))
        XCTAssertEqual(game.score, 100)
        XCTAssertTrue(game.selection.isEmpty)
        XCTAssertTrue(game.hasMatch())
    }
    func testTimerEndsRound() {
        var game = GameEngine()
        game.tick(60)
        XCTAssertTrue(game.finished)
        XCTAssertEqual(game.remaining, 0)
    }
    func testSameTileCannotBeReused() {
        var game = GameEngine(randomType: { 0 })
        game.start(at: Position(0,0))
        XCTAssertFalse(game.visit(Position(0,0)))
        XCTAssertEqual(game.selection.count, 1)
    }
}
