import EmojiMatchCore
import SwiftUI

/// The best rounds played on this device.
struct LeaderboardView: View {
    let entries: [LeaderboardEntry]
    let highlightedRank: Int?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No scores yet",
                        systemImage: "trophy",
                        description: Text("Play a round to get on the board.")
                    )
                    .accessibilityIdentifier("leaderboardEmpty")
                } else {
                    List(Array(entries.enumerated()), id: \.offset) { index, entry in
                        row(entry, rank: index + 1)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Leaderboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("leaderboardDone")
                }
            }
        }
    }

    private func row(_ entry: LeaderboardEntry, rank: Int) -> some View {
        HStack(spacing: 14) {
            Text(medal(rank))
                .font(.system(.title2, design: .rounded, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.score.formatted())
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text(details(entry))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            if rank == highlightedRank {
                Text("This round")
                    .font(.system(.caption, design: .rounded, weight: .heavy))
                    .foregroundStyle(Theme.pink)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rank \(rank), \(entry.score) points, \(details(entry))\(rank == highlightedRank ? ", this round" : "")")
        .accessibilityValue("\(entry.score)")
        .accessibilityIdentifier("leaderboardRow\(rank)")
    }

    private func medal(_ rank: Int) -> String {
        switch rank {
        case 1: return "🥇"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return "\(rank)"
        }
    }

    private func details(_ entry: LeaderboardEntry) -> String {
        guard entry.matches > 0 else { return "Earlier best" }
        let date = entry.date.formatted(date: .abbreviated, time: .omitted)
        return "Longest \(entry.longestMatch) · ×\(entry.multiplier) · \(date)"
    }
}
