import EmojiMatchCore
import SpriteKit
import UIKit

/// Pre-renders tile art. Sprites from one texture cache are far cheaper than live emoji labels.
@MainActor
final class TileTextures {
    let tileSize: CGFloat
    private var baseCache: [Int: SKTexture] = [:]
    private var emojiCache: [Int: SKTexture] = [:]
    private var glowCache: [Int: SKTexture] = [:]
    private var badgeCache: [String: SKTexture] = [:]

    init(tileSize: CGFloat) { self.tileSize = tileSize }

    func base(_ type: Int) -> SKTexture {
        if let cached = baseCache[type] { return cached }
        let texture = makeBase(EmojiCatalog.entry(for: type))
        baseCache[type] = texture
        return texture
    }

    func emoji(_ type: Int) -> SKTexture {
        if let cached = emojiCache[type] { return cached }
        let texture = makeEmoji(EmojiCatalog.entry(for: type).emoji)
        emojiCache[type] = texture
        return texture
    }

    func glow(_ type: Int) -> SKTexture {
        if let cached = glowCache[type] { return cached }
        let texture = makeGlow(EmojiCatalog.entry(for: type).glow)
        glowCache[type] = texture
        return texture
    }

    /// Floating text such as "+300" or "×3!".
    func badge(_ text: String) -> SKTexture {
        if let cached = badgeCache[text] { return cached }
        let texture = Self.makeBadge(text, tileSize: tileSize)
        badgeCache[text] = texture
        return texture
    }

    /// Soft white-to-transparent disc, used for the string tip and pop sparks.
    private(set) lazy var spark: SKTexture = {
        let side: CGFloat = 32
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.2, 1])!
            let center = CGPoint(x: side / 2, y: side / 2)
            context.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: side / 2, options: [])
        }
        return SKTexture(image: image)
    }()

    private func makeBase(_ entry: EmojiCatalog.Entry) -> SKTexture {
        let side = tileSize
        let inset = side * 0.04
        let rect = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
        let corner = side * 0.24
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            let cg = context.cgContext
            let path = UIBezierPath(roundedRect: rect, cornerRadius: corner)
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: side * 0.03), blur: side * 0.05, color: UIColor(white: 0.2, alpha: 0.2).cgColor)
            entry.tint.setFill()
            path.fill()
            cg.restoreGState()
            cg.saveGState()
            path.addClip()
            let colors = [UIColor.white.withAlphaComponent(0.65).cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.midY), options: [])
            cg.restoreGState()
            UIColor.white.withAlphaComponent(0.8).setStroke()
            let rim = UIBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: corner - 1)
            rim.lineWidth = 1.5
            rim.stroke()
        }
        return SKTexture(image: image)
    }

    private func makeEmoji(_ emoji: String) -> SKTexture {
        let side = tileSize
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            let text = NSAttributedString(string: emoji, attributes: [.font: UIFont.systemFont(ofSize: side * 0.62)])
            let size = text.size()
            text.draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2))
        }
        return SKTexture(image: image)
    }

    private func makeGlow(_ color: UIColor) -> SKTexture {
        let side = tileSize * 1.7
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            let colors = [color.withAlphaComponent(0.85).cgColor, color.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.35, 1])!
            let center = CGPoint(x: side / 2, y: side / 2)
            context.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: side / 2, options: [])
        }
        return SKTexture(image: image)
    }

    private static func makeBadge(_ string: String, tileSize: CGFloat) -> SKTexture {
        let descriptor = UIFont.systemFont(ofSize: tileSize * 0.5, weight: .heavy).fontDescriptor.withDesign(.rounded)
        let font = descriptor.map { UIFont(descriptor: $0, size: tileSize * 0.5) } ?? .boldSystemFont(ofSize: tileSize * 0.5)
        let text = NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: UIColor(red: 1, green: 0.36, blue: 0.54, alpha: 1),
            .strokeColor: UIColor.white,
            .strokeWidth: -5,
        ])
        let size = text.size()
        let image = UIGraphicsImageRenderer(size: size).image { _ in text.draw(at: .zero) }
        return SKTexture(image: image)
    }
}

/// One tile: glow under base under emoji. The connection string renders between base and emoji.
@MainActor
final class TileNode: SKNode {
    enum Z {
        static let glow: CGFloat = 1
        static let base: CGFloat = 2
        static let selectedBase: CGFloat = 4
        static let string: CGFloat = 10
        static let emoji: CGFloat = 20
        static let effects: CGFloat = 30
    }

    let tile: Tile
    private let base: SKSpriteNode
    private let emoji: SKSpriteNode
    private let glow: SKSpriteNode

    init(tile: Tile, textures: TileTextures) {
        self.tile = tile
        let side = textures.tileSize
        base = SKSpriteNode(texture: textures.base(tile.type), size: CGSize(width: side, height: side))
        emoji = SKSpriteNode(texture: textures.emoji(tile.type), size: CGSize(width: side, height: side))
        glow = SKSpriteNode(texture: textures.glow(tile.type), size: CGSize(width: side * 1.7, height: side * 1.7))
        super.init()
        glow.alpha = 0
        glow.zPosition = Z.glow
        base.zPosition = Z.base
        emoji.zPosition = Z.emoji
        addChild(glow)
        addChild(base)
        addChild(emoji)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setSelected(_ selected: Bool, reduceMotion: Bool) {
        let duration = 0.1
        removeAction(forKey: "scale")
        run(.scale(to: selected && !reduceMotion ? 1.15 : 1, duration: duration), withKey: "scale")
        glow.removeAllActions()
        glow.run(.fadeAlpha(to: selected ? 1 : 0, duration: duration))
        base.zPosition = selected ? Z.selectedBase : Z.base
    }

    func setDimmed(_ dimmed: Bool) {
        removeAction(forKey: "dim")
        run(.fadeAlpha(to: dimmed ? 0.42 : 1, duration: 0.1), withKey: "dim")
    }

    func resize(textures: TileTextures) {
        let side = textures.tileSize
        base.texture = textures.base(tile.type)
        base.size = CGSize(width: side, height: side)
        emoji.texture = textures.emoji(tile.type)
        emoji.size = CGSize(width: side, height: side)
        glow.texture = textures.glow(tile.type)
        glow.size = CGSize(width: side * 1.7, height: side * 1.7)
    }
}
