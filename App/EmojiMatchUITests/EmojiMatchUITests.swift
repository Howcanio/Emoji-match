import XCTest

/// End-to-end tests on a fixed board: every column is one emoji type, so tiles in a column match.
final class EmojiMatchUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(duration: Int = 60, reset: Bool = true) {
        app.launchArguments = ["-uiTestFixedBoard", "-uiTestRoundDuration", "\(duration)"]
        if reset { app.launchArguments.append("-uiTestResetDefaults") }
        app.launch()
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    private func startGame(duration: Int = 60) -> XCUIElement {
        launch(duration: duration)
        element("playButton").tap()
        let board = element("gameBoard")
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1) // Intro.
        return board
    }

    /// Screen coordinate of a tile's center, allowing for the scene's 8pt padding.
    private func tile(_ row: Int, _ column: Int, on board: XCUIElement) -> XCUICoordinate {
        let frame = board.frame
        let side = (frame.width - 16) / 6
        let origin = board.coordinate(withNormalizedOffset: .zero)
        return origin.withOffset(CGVector(
            dx: 8 + side * (CGFloat(column) + 0.5),
            dy: 8 + side * (CGFloat(row) + 0.5)
        ))
    }

    private func value(_ id: String) -> Int {
        Int(element(id).value as? String ?? "") ?? -1
    }

    private func waitForScore(_ score: Int, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value == %@", "\(score)")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element("score"))
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, "score \(value("score")) != \(score)", file: file, line: line)
    }

    func testHomeShowsPlayAndBest() {
        launch()
        XCTAssertTrue(element("playButton").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Emoji Match"].exists)
        XCTAssertTrue(app.staticTexts["Connect 3. Pop. Repeat."].exists)
        XCTAssertTrue(element("homeBest").exists)
    }

    func testSettingsTogglesPersist() {
        launch()
        element("settingsButton").tap()
        let sound = app.switches["soundToggle"]
        XCTAssertTrue(sound.waitForExistence(timeout: 5))
        XCTAssertEqual(sound.value as? String, "1")
        sound.switches.firstMatch.tap()
        XCTAssertEqual(sound.value as? String, "0")
        element("settingsDone").tap()
        app.terminate()
        launch(reset: false)
        element("settingsButton").tap()
        XCTAssertTrue(app.switches["soundToggle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["soundToggle"].value as? String, "0")
        XCTAssertEqual(app.switches["hapticsToggle"].value as? String, "1")
    }

    func testDragAcrossThreeMatchingTilesScores() {
        let board = startGame()
        XCTAssertEqual(value("score"), 0)
        tile(5, 0, on: board).press(forDuration: 0.1, thenDragTo: tile(7, 0, on: board))
        waitForScore(100)
        XCTAssertFalse(element("multiplier").exists)
    }

    func testLongerGrabRaisesMultiplierAndAppliesToLaterMatches() {
        let board = startGame()
        tile(4, 0, on: board).press(forDuration: 0.1, thenDragTo: tile(7, 0, on: board))
        waitForScore(200) // 4 tiles: new longest, ×2.
        XCTAssertEqual(value("multiplier"), 2)
        Thread.sleep(forTimeInterval: 0.7)
        tile(5, 1, on: board).press(forDuration: 0.1, thenDragTo: tile(7, 1, on: board))
        waitForScore(400) // 3 tiles at the kept ×2.
    }

    func testFastSwipeStillRegistersCrossedTiles() {
        let board = startGame()
        tile(0, 1, on: board).press(
            forDuration: 0.02,
            thenDragTo: tile(7, 1, on: board),
            withVelocity: .fast,
            thenHoldForDuration: 0
        )
        waitForScore(200) // Crossing 4 tiles on the 3-unit string raises the multiplier to ×2.
    }

    func testRepeatedMatches() {
        let board = startGame()
        for (index, column) in [0, 1, 2, 3, 4, 5].enumerated() {
            tile(5, column, on: board).press(forDuration: 0.1, thenDragTo: tile(7, column, on: board))
            waitForScore((index + 1) * 100)
        }
    }

    func testNonMatchingDragDoesNotScore() {
        let board = startGame()
        tile(3, 0, on: board).press(forDuration: 0.1, thenDragTo: tile(3, 5, on: board))
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(value("score"), 0)
    }

    func testIncompleteSelectionReleasedDoesNotScore() {
        let board = startGame()
        tile(3, 0, on: board).press(forDuration: 0.1, thenDragTo: tile(4, 0, on: board))
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(value("score"), 0)
        tile(1, 0, on: board).press(forDuration: 0.1, thenDragTo: tile(3, 0, on: board))
        waitForScore(100)
    }

    func testBackgroundingPausesTimerAndResumes() {
        _ = startGame()
        let before = value("timer")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 6)
        app.activate()
        XCTAssertTrue(element("gameBoard").waitForExistence(timeout: 5))
        let after = value("timer")
        XCTAssertGreaterThan(after, before - 4, "6 seconds in the background must not count")
        Thread.sleep(forTimeInterval: 2.5)
        XCTAssertLessThan(value("timer"), after, "timer resumes")
    }

    func testRoundEndsShowsResultsAndHighScorePersists() {
        let board = startGame(duration: 6)
        tile(5, 0, on: board).press(forDuration: 0.1, thenDragTo: tile(7, 0, on: board))
        waitForScore(100)
        XCTAssertTrue(element("playAgainButton").waitForExistence(timeout: 10))
        XCTAssertEqual(value("finalScore"), 100)
        XCTAssertEqual(value("personalBest"), 100)
        XCTAssertEqual(value("matchCount"), 1)
        XCTAssertTrue(app.staticTexts["New best! 🎉"].exists)

        // Play Again starts a fresh round.
        element("playAgainButton").tap()
        XCTAssertTrue(element("gameBoard").waitForExistence(timeout: 5))
        XCTAssertEqual(value("score"), 0)
        // A round with no matches doesn't lower the best.
        XCTAssertTrue(element("homeButton").waitForExistence(timeout: 12))
        XCTAssertEqual(value("finalScore"), 0)
        XCTAssertEqual(value("personalBest"), 100)
        element("homeButton").tap()
        XCTAssertTrue(element("homeBest").waitForExistence(timeout: 5))
        XCTAssertEqual(element("homeBest").label, "Best  100")

        // The best survives a relaunch.
        app.terminate()
        launch(reset: false)
        XCTAssertTrue(element("homeBest").waitForExistence(timeout: 5))
        XCTAssertEqual(element("homeBest").label, "Best  100")
    }
}
