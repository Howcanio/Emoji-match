import SwiftUI

struct ResultsView: View {
    let summary: RoundSummary
    let playAgain: () -> Void
    let openLeaderboard: () -> Void
    let goHome: () -> Void

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text(summary.isNewBest ? "New best! 🎉" : (summary.score > 0 ? "Nice round!" : "Time's up!"))
                .font(.system(.title, design: .rounded, weight: .heavy))
                .foregroundStyle(summary.isNewBest ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Theme.ink))
                .accessibilityIdentifier("resultsTitle")

            Text("\(summary.score)")
                .font(.system(size: 96, weight: .black, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(Theme.ink)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.7)
                .accessibilityLabel("Final score \(summary.score)")
                .accessibilityValue("\(summary.score)")
                .accessibilityIdentifier("finalScore")

            if let rank = summary.leaderboardRank {
                Text("#\(rank) on your leaderboard")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.pink)
                    .accessibilityIdentifier("leaderboardRank")
            }

            HStack(spacing: 12) {
                stat("Personal best", summary.best, id: "personalBest")
                stat("Matches", summary.matches, id: "matchCount")
                stat("Longest", summary.longestMatch, id: "longestMatch")
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            Spacer()

            VStack(spacing: 12) {
                Button("Play Again", action: playAgain)
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("playAgainButton")
                HStack(spacing: 12) {
                    Button("Leaderboard", action: openLeaderboard)
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("resultsLeaderboardButton")
                    Button("Home", action: goHome)
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("homeButton")
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { appeared = true }
        }
    }

    private func stat(_ title: String, _ value: Int, id: String) -> some View {
        VStack(spacing: 2) {
            Text(value.formatted())
                .font(.system(.title, design: .rounded, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value)")
        .accessibilityValue("\(value)")
        .accessibilityIdentifier(id)
    }
}
