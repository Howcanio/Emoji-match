import SwiftUI

struct HomeView: View {
    let best: Int
    let play: () -> Void
    let openLeaderboard: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: openLeaderboard) {
                    Image(systemName: "trophy.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.inkSoft)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Leaderboard")
                .accessibilityIdentifier("leaderboardButton")
                Spacer()
                Button(action: openSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.inkSoft)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("settingsButton")
            }
            .padding(.horizontal, 12)

            Spacer()

            LogoMark()
                .padding(.bottom, 28)

            Text("Emoji Match")
                .font(.system(size: 50, weight: .black, design: .rounded))
                .foregroundStyle(Theme.brand)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Text("Connect 3. Pop. Repeat.")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 6)

            Spacer()

            Button("Play", action: play)
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("playButton")
                .padding(.horizontal, 32)

            Text(best > 0 ? "Best  \(best.formatted())" : "No best score yet")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .padding(.top, 20)
                .accessibilityIdentifier("homeBest")

            Spacer().frame(height: 48)
        }
    }
}

/// Three matching tiles joined by a glowing string: the whole game in one picture.
private struct LogoMark: View {
    private let side: CGFloat = 78
    private let points = [CGPoint(x: 39, y: 112), CGPoint(x: 130, y: 39), CGPoint(x: 221, y: 112)]

    var body: some View {
        ZStack {
            string(width: 20, opacity: 0.2)
            string(width: 11, opacity: 0.45)
            string(width: 4, opacity: 1, color: .white)
            ForEach(points.indices, id: \.self) { index in
                Text("😀")
                    .font(.system(size: side * 0.62))
                    .frame(width: side, height: side)
                    .background(
                        Color(uiColor: EmojiCatalog.entries[0].tint),
                        in: RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 6, y: 4)
                    .position(points[index])
            }
        }
        .frame(width: 260, height: 152)
        .accessibilityHidden(true)
    }

    private func string(width: CGFloat, opacity: Double, color: Color = Theme.pink) -> some View {
        Path { path in path.addLines(points) }
            .stroke(color.opacity(opacity), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
}
