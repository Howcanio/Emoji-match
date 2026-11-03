# Emoji Match

**Connect 3. Pop. Repeat.**

A fast, one-finger iOS puzzle game. Touch an emoji, drag a glowing string across more of the same emoji, and lift to pop them. Every win makes your string longer, so you can grab more, and each new longest grab raises your multiplier. You have 60 seconds. Fully offline, with no accounts, ads, purchases, or backend.

## Requirements

- Xcode 16 or later (the project uses folder-synchronized groups). Developed and tested with Xcode 27.1.
- iOS 17.0 or later, iPhone, portrait.
- No third-party dependencies and no project generators.

## Run it

1. Open `EmojiMatch.xcodeproj`.
2. Pick the **EmojiMatch** scheme and an iPhone simulator.
3. Press Run.

To run on a physical iPhone, first choose your team under *Signing & Capabilities* for the EmojiMatch target.

## Test it

Rules and persistence (fast, no simulator):

```bash
swift test
```

Everything on an iOS simulator: the same rules tests, a hosted GameSession/GameScene suite, and end-to-end UI tests:

```bash
xcodebuild test -project EmojiMatch.xcodeproj -scheme EmojiMatch -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO
```

The manual test matrix for a physical iPhone is in [docs/QA_CHECKLIST.md](docs/QA_CHECKLIST.md). Distribution steps are in [docs/TESTFLIGHT.md](docs/TESTFLIGHT.md).

## Rules

| | |
|---|---|
| Board | 6 columns × 8 rows, 8 emoji types |
| Match | 3 or more identical emojis; pops when you lift, or at once when nothing more is in reach |
| Connections | Any direction, including diagonals; other emojis are skipped; no tile reuse |
| String | Starts at 3 tile widths, grows 0.5 per match, capped at 12; measured as cumulative center-to-center Euclidean distance |
| Multiplier | Starts at ×1; +1 each time a match beats the round's longest grab (the first 4-tile match gives ×2), and it stays for the round |
| Score | 100 × multiplier per match, no cascades |
| Round | 60 seconds |
| Lifting early | Fewer than 3 tiles disappears with no score |
| After a match | Lift your finger before starting the next connection |
| Board state | Always has a match the current string can reach; reshuffles if a refill would leave none |

## Architecture

```
Sources/EmojiMatchCore/      Game rules. No UIKit, SwiftUI, or SpriteKit.
  GameEngine.swift           State machine, selection, touch interpolation, match resolution
  Board.swift                Grid storage, solvability search, reshuffle fallback
  RoundClock.swift           Safe frame deltas
  Persistence.swift          High score and settings keys (UserDefaults)
Tests/EmojiMatchCoreTests/   Rules tests, runnable with `swift test`
App/EmojiMatch/
  Game/GameSession.swift     Connects engine, scene, feedback, and HUD for one round
  Game/GameScene.swift       SpriteKit rendering and touch capture; holds no rules
  Game/TileTextures.swift    Pre-rendered tile art
  Screens/                   SwiftUI Home, Game (HUD), Results, Settings
  Support/                   Theme, emoji catalog, synthesized sound, haptics
App/EmojiMatchTests/         Hosted tests driving a real session and scene frame by frame
                             (this target also compiles Tests/EmojiMatchCoreTests)
App/EmojiMatchUITests/       End-to-end XCUITest on a fixed board
```

**Data flow.** `GameScene` converts touches to tile-unit `BoardPoint`s and hands them to `GameSession`, which calls `GameEngine`. The engine updates its state immediately and returns `GameEvent`s. The session passes those to the scene to animate, to feedback for sound and haptics, and to `@Published` properties for the HUD.

**State machine.** `ready → playing ⇄ selecting → resolvingMatch → playing`, and any active phase `→ gameOver`. `isPaused` is separate and freezes the clock and input in any phase. See the diagram at the top of `GameEngine.swift`.

**Decisions worth knowing:**

- *Input can't corrupt the board.* The engine computes the whole match result the moment a match commits, and rejects all input during `resolvingMatch`. The animation only depicts the result. Resolution is timed by the frame loop rather than by action completion callbacks.
- *Fast swipes.* Each finger movement is interpolated in 0.1-tile steps, and `GameScene` also feeds iOS's coalesced touches, so crossed tiles register in order. While dragging, a tile registers only within 0.45 tiles of its center, so a diagonal doesn't clip the corners of its neighbors.
- *No lost touches.* A finger that lands during the intro or a match animation starts its selection, at its current location, as soon as input reopens.
- *Timer.* The 60 seconds run during match animations, since the round is real time. On expiry, a selection of 3 or more tiles commits and fewer is cancelled; a committed match finishes animating, counts, and then the round ends. Backgrounding treats the selection the same way, as if the finger lifted.
- *Tuning.* String start, growth, and cap are the `startingLength`, `lengthGrowth`, and `lengthCap` defaults in `GameConfig`.
- *Solvability.* Random boards can genuinely have no match: `unsolvableTypes()` in the tests is a full board without one. After every refill the engine checks, then shuffles the existing tiles, with a deterministic fallback that always succeeds.
- *Sound* is synthesized at runtime, so there are no audio assets, and uses the ambient session so it mixes with music and obeys the silent switch.

## Known limitations

- The board isn't playable with VoiceOver. HUD, buttons, and results are labeled, but the core gesture is a continuous visual drag, and the MVP has no alternative input.
- Emoji artwork is the system font, so it varies slightly across iOS versions.
- There's no way to quit a round in progress; rounds last 60 seconds, and the spec calls for minimal gameplay UI.
- Feel, audio, and haptics need checking on real hardware. See the QA checklist for what has not been verified.
