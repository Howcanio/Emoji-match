import EmojiMatchCore
import SwiftUI

/// Navigates between the three full screens.
struct RootView: View {
    /// Carries the rank into the sheet; a separate state value would reach it stale.
    private struct LeaderboardRequest: Identifiable {
        let id = UUID()
        let highlightedRank: Int?
    }

    private enum Screen: Equatable {
        case home
        case game(UUID)
        case results(RoundSummary)
    }

    @State private var screen: Screen = .home
    @State private var best: Int
    @State private var showingSettings = false
    @State private var leaderboardRequest: LeaderboardRequest?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {
        if LaunchOptions.current.resetDefaults, let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        let best = HighScoreStore().best
        LeaderboardStore().adopt(best: best)
        _best = State(initialValue: best)
    }

    var body: some View {
        ZStack {
            AppBackground()
            switch screen {
            case .home:
                HomeView(best: best, play: startRound, openLeaderboard: { openLeaderboard() }, openSettings: { showingSettings = true })
                    .transition(.opacity)
            case .game(let id):
                GameView { summary in
                    best = summary.best
                    go(to: .results(summary))
                }
                .id(id)
                .transition(.opacity)
            case .results(let summary):
                ResultsView(
                    summary: summary,
                    playAgain: startRound,
                    openLeaderboard: { openLeaderboard(highlighting: summary.leaderboardRank) },
                    goHome: { go(to: .home) }
                )
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .presentationDetents([.medium])
        }
        .sheet(item: $leaderboardRequest) { request in
            LeaderboardView(entries: LeaderboardStore().entries, highlightedRank: request.highlightedRank)
                .presentationDetents([.large])
        }
    }

    private func openLeaderboard(highlighting rank: Int? = nil) {
        leaderboardRequest = LeaderboardRequest(highlightedRank: rank)
    }

    private func startRound() { go(to: .game(UUID())) }

    private func go(to next: Screen) {
        withAnimation(.easeInOut(duration: reduceMotion ? 0.1 : 0.25)) { screen = next }
    }
}
