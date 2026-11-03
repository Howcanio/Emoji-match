import EmojiMatchCore
import SwiftUI

/// Navigates between the three full screens.
struct RootView: View {
    private enum Screen: Equatable {
        case home
        case game(UUID)
        case results(RoundSummary)
    }

    @State private var screen: Screen = .home
    @State private var best: Int
    @State private var showingSettings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {
        if LaunchOptions.current.resetDefaults, let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        _best = State(initialValue: HighScoreStore().best)
    }

    var body: some View {
        ZStack {
            AppBackground()
            switch screen {
            case .home:
                HomeView(best: best, play: startRound, openSettings: { showingSettings = true })
                    .transition(.opacity)
            case .game(let id):
                GameView { summary in
                    best = summary.best
                    go(to: .results(summary))
                }
                .id(id)
                .transition(.opacity)
            case .results(let summary):
                ResultsView(summary: summary, playAgain: startRound, goHome: { go(to: .home) })
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .presentationDetents([.medium])
        }
    }

    private func startRound() { go(to: .game(UUID())) }

    private func go(to next: Screen) {
        withAnimation(.easeInOut(duration: reduceMotion ? 0.1 : 0.25)) { screen = next }
    }
}
