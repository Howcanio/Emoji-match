import EmojiMatchCore
import SpriteKit
import SwiftUI

struct GameView: View {
    let onFinished: (RoundSummary) -> Void

    @StateObject private var session = GameSession(
        engine: LaunchOptions.current.makeEngine(),
        feedback: SystemFeedback()
    )
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            HUD(score: session.score, seconds: session.secondsLeft, urgent: session.isUrgent)
            StringGauge(remaining: session.stringRemaining)
            GameBoardView(scene: session.scene)
                .aspectRatio(boardAspect, contentMode: .fit)
                .layoutPriority(1)
                .accessibilityElement()
                .accessibilityLabel("Game board, 6 columns by 8 rows")
                .accessibilityHint("Touch an emoji and drag to two matching emojis to pop them")
                .accessibilityIdentifier("gameBoard")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .overlay {
            if session.phase == .gameOver {
                TimeUpBanner()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.phase == .gameOver)
        .onAppear { session.onFinished = onFinished }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.resume() } else { session.pause() }
        }
        .onChange(of: session.phase) { _, phase in
            guard phase == .gameOver else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 500 : 900))
                session.showResults()
            }
        }
    }

    private var boardAspect: CGFloat {
        CGFloat(session.engine.config.columns) / CGFloat(session.engine.config.rows)
    }
}

private struct HUD: View {
    let score: Int
    let seconds: Int
    let urgent: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text("SCORE").font(.system(.caption, design: .rounded, weight: .bold)).foregroundStyle(Theme.inkSoft)
                Text("\(score)")
                    .font(.system(.largeTitle, design: .rounded, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: score)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Score \(score)")
            .accessibilityValue("\(score)")
            .accessibilityIdentifier("score")

            Spacer()

            VStack(alignment: .trailing, spacing: 0) {
                Text("TIME").font(.system(.caption, design: .rounded, weight: .bold)).foregroundStyle(Theme.inkSoft)
                Text("\(seconds)")
                    .font(.system(.largeTitle, design: .rounded, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(urgent ? Theme.urgent : Theme.ink)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(seconds) seconds left")
            .accessibilityValue("\(seconds)")
            .accessibilityIdentifier("timer")
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

/// A thin bar showing how much string is left. Only visible while connecting.
private struct StringGauge: View {
    let remaining: Double?

    var body: some View {
        GeometryReader { space in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.ink.opacity(0.08))
                Capsule()
                    .fill(Theme.brand)
                    .frame(width: space.size.width * (remaining ?? 0))
                    .animation(.easeOut(duration: 0.12), value: remaining)
            }
        }
        .frame(height: 5)
        .padding(.horizontal, 16)
        .opacity(remaining == nil ? 0 : 1)
        .animation(.easeOut(duration: 0.12), value: remaining == nil)
        .accessibilityHidden(true)
    }
}

private struct TimeUpBanner: View {
    var body: some View {
        Text("Time's up!")
            .font(.system(size: 44, weight: .black, design: .rounded))
            .foregroundStyle(Theme.brand)
            .padding(.horizontal, 32)
            .padding(.vertical, 18)
            .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 20, y: 10)
            .accessibilityIdentifier("timeUpBanner")
    }
}

/// Hosts the SpriteKit scene. A plain SKView gives direct control of pausing, frame rate, and
/// transparency, which `SpriteView` doesn't fully expose.
struct GameBoardView: UIViewRepresentable {
    let scene: GameScene

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.allowsTransparency = true
        view.isOpaque = false
        view.backgroundColor = .clear
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 120
        view.isMultipleTouchEnabled = false
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ view: SKView, context: Context) {}
}
