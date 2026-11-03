import SwiftUI
import UIKit

enum Theme {
    static let backgroundTop = Color(red: 1.0, green: 0.973, blue: 0.933)
    static let backgroundBottom = Color(red: 0.914, green: 0.957, blue: 1.0)
    static let ink = Color(red: 0.2, green: 0.17, blue: 0.3)
    static let inkSoft = Color(red: 0.2, green: 0.17, blue: 0.3).opacity(0.6)
    static let pink = Color(red: 1.0, green: 0.36, blue: 0.54)
    static let violet = Color(red: 0.48, green: 0.36, blue: 1.0)
    static let urgent = Color(red: 0.93, green: 0.2, blue: 0.3)
    static let brand = LinearGradient(colors: [pink, violet], startPoint: .leading, endPoint: .trailing)
}

struct AppBackground: View {
    var body: some View {
        LinearGradient(colors: [Theme.backgroundTop, Theme.backgroundBottom], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

/// Large gradient call-to-action with a tactile press.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.title2, design: .rounded, weight: .heavy))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Theme.brand, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Theme.violet.opacity(0.35), radius: 14, y: 8)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.title3, design: .rounded, weight: .bold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(.white.opacity(configuration.isPressed ? 0.5 : 0.85), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// The eight tile types. Picked to differ in both color and silhouette.
enum EmojiCatalog {
    struct Entry {
        let emoji: String
        let name: String
        let tint: UIColor
        let glow: UIColor
    }

    static let entries: [Entry] = [
        Entry(emoji: "😀", name: "Smile", tint: rgb(255, 241, 184), glow: rgb(255, 184, 0)),
        Entry(emoji: "🐸", name: "Frog", tint: rgb(213, 245, 196), glow: rgb(60, 203, 74)),
        Entry(emoji: "🍓", name: "Strawberry", tint: rgb(255, 212, 212), glow: rgb(255, 59, 92)),
        Entry(emoji: "🐳", name: "Whale", tint: rgb(207, 232, 255), glow: rgb(30, 155, 255)),
        Entry(emoji: "🍊", name: "Orange", tint: rgb(255, 226, 194), glow: rgb(255, 138, 0)),
        Entry(emoji: "🍇", name: "Grapes", tint: rgb(229, 216, 255), glow: rgb(138, 77, 255)),
        Entry(emoji: "🌸", name: "Blossom", tint: rgb(255, 221, 238), glow: rgb(255, 79, 163)),
        Entry(emoji: "🐼", name: "Panda", tint: rgb(226, 232, 240), glow: rgb(0, 191, 165)),
    ]

    static func entry(for type: Int) -> Entry { entries[type % entries.count] }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        UIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }
}
