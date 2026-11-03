import EmojiMatchCore
import SpriteKit
import UIKit

/// Renders the board and forwards touches. Holds no rules: everything it draws comes from the
/// session's engine state and events.
@MainActor
final class GameScene: SKScene {
    /// Margin inside the scene so glows and pops at the board edge aren't clipped.
    static let padding: CGFloat = 8

    enum Timing {
        static let pop = 0.18
        static let gravity = 0.30
        static let reshuffle = 0.28
        static let reducedPop = 0.1
        static let reducedSettle = 0.12
        static let intro = 0.5
        static let reducedIntro = 0.15
    }

    weak var session: GameSession?
    var reduceMotion: () -> Bool = { UIAccessibility.isReduceMotionEnabled }

    private var textures: TileTextures?
    private var tileNodes: [Int: TileNode] = [:]
    private let boardLayer = SKNode()
    private let stringLayer = SKNode()
    private let stringOuter = SKShapeNode()
    private let stringMiddle = SKShapeNode()
    private let stringCore = SKShapeNode()
    private var stringTip: SKSpriteNode?
    private var activeTouch: UITouch?
    private var fingerLocation: CGPoint?
    private var clock = RoundClock()
    private var builtBoard = false
    private(set) var lastCallout: String?

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = .clear
        addChild(boardLayer)
        addChild(stringLayer)
        for (node, width, alpha) in [(stringOuter, 0.36, 0.22), (stringMiddle, 0.18, 0.55), (stringCore, 0.07, 1.0)] as [(SKShapeNode, CGFloat, CGFloat)] {
            node.lineCap = .round
            node.lineJoin = .round
            node.fillColor = .clear
            node.alpha = alpha
            node.userData = ["width": width]
            node.isAntialiased = true
            node.zPosition = TileNode.Z.string
            stringLayer.addChild(node)
        }
        stringCore.strokeColor = .white
        stringLayer.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Geometry

    private var tileSize: CGFloat {
        guard let config = session?.engine.config else { return 0 }
        return min(
            (size.width - Self.padding * 2) / CGFloat(config.columns),
            (size.height - Self.padding * 2) / CGFloat(config.rows)
        )
    }

    func scenePoint(_ position: Position) -> CGPoint {
        scenePoint(BoardPoint(center: position))
    }

    private func scenePoint(_ point: BoardPoint) -> CGPoint {
        guard let config = session?.engine.config else { return .zero }
        let side = tileSize
        return CGPoint(
            x: (CGFloat(point.x) - CGFloat(config.columns) / 2) * side,
            y: (CGFloat(config.rows) / 2 - CGFloat(point.y)) * side
        )
    }

    private func boardPoint(_ location: CGPoint) -> BoardPoint {
        guard let config = session?.engine.config, tileSize > 0 else { return BoardPoint(x: -1, y: -1) }
        return BoardPoint(
            x: Double(location.x / tileSize + CGFloat(config.columns) / 2),
            y: Double(CGFloat(config.rows) / 2 - location.y / tileSize)
        )
    }

    // MARK: - Lifecycle

    override func didMove(to view: SKView) { layoutBoard() }

    override func didChangeSize(_ oldSize: CGSize) { layoutBoard() }

    private func layoutBoard() {
        guard let session, tileSize > 1 else { return }
        if textures?.tileSize != tileSize {
            textures = TileTextures(tileSize: tileSize)
            for node in tileNodes.values { node.resize(textures: textures!) }
            let tip = stringTip ?? SKSpriteNode(texture: textures!.spark)
            tip.size = CGSize(width: tileSize * 0.45, height: tileSize * 0.45)
            tip.zPosition = TileNode.Z.string + 1
            if stringTip == nil {
                stringLayer.addChild(tip)
                stringTip = tip
            }
            for node in [stringOuter, stringMiddle, stringCore] {
                node.lineWidth = (node.userData?["width"] as? CGFloat ?? 0.1) * tileSize
            }
        }
        if !builtBoard {
            builtBoard = true
            buildBoard(session.engine.board)
        }
        for position in session.engine.board.positions {
            guard let node = tileNodes[session.engine.board[position].id], !node.hasActions() else { continue }
            node.position = scenePoint(position)
        }
    }

    private func buildBoard(_ board: Board) {
        guard let textures else { return }
        let animated = !reduceMotion()
        for position in board.positions {
            let tile = board[position]
            let node = TileNode(tile: tile, textures: textures)
            let target = scenePoint(position)
            tileNodes[tile.id] = node
            boardLayer.addChild(node)
            if animated {
                node.position = CGPoint(x: target.x, y: target.y + tileSize * 0.6)
                node.alpha = 0
                node.setScale(0.8)
                let delay = Double(board.rows - position.row) * 0.025
                let settle = SKAction.group([
                    .move(to: target, duration: 0.25),
                    .fadeIn(withDuration: 0.2),
                    .scale(to: 1, duration: 0.25),
                ])
                settle.timingMode = .easeOut
                node.run(.sequence([.wait(forDuration: delay), settle]))
            } else {
                node.position = target
                node.alpha = 0
                node.run(.fadeIn(withDuration: Timing.reducedIntro))
            }
        }
    }

    var introDuration: TimeInterval { reduceMotion() ? Timing.reducedIntro : Timing.intro }

    /// The first frame after any pause reports no elapsed time.
    func resetClock() { clock.reset() }

    override func update(_ currentTime: TimeInterval) {
        session?.frame(delta: clock.delta(now: currentTime))
        drawString()
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        fingerLocation = touch.location(in: self)
        session?.touchDown(at: boardPoint(touch.location(in: self)))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        for sample in event?.coalescedTouches(for: touch) ?? [touch] {
            session?.touchMoved(to: boardPoint(sample.location(in: self)))
        }
        fingerLocation = touch.location(in: self)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { endTouch(touches) }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { endTouch(touches) }

    private func endTouch(_ touches: Set<UITouch>) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        activeTouch = nil
        fingerLocation = nil
        session?.touchUp()
    }

    /// Forget the current finger; the system may never deliver its end after backgrounding.
    func forgetTouch() {
        activeTouch = nil
        fingerLocation = nil
    }

    // MARK: - Events

    /// Applies an engine event visually. For a match, returns how long the animation takes.
    @discardableResult
    func apply(_ event: GameEvent) -> TimeInterval? {
        switch event {
        case .tileSelected(let tile, _, _):
            tileNodes[tile.id]?.setSelected(true, reduceMotion: reduceMotion())
            refreshDimming()
            prepareString()
        case .selectionCancelled(let positions):
            guard let board = session?.engine.board else { return nil }
            for position in positions {
                tileNodes[board[position].id]?.setSelected(false, reduceMotion: reduceMotion())
            }
            refreshDimming()
            fadeOutString()
        case .matched(let resolution):
            return animate(resolution)
        case .resolvingFinished:
            refreshDimming()
        case .roundStarted, .roundEnded:
            break
        }
        return nil
    }

    private func refreshDimming() {
        guard let engine = session?.engine else { return }
        for position in engine.board.positions {
            guard let node = tileNodes[engine.board[position].id] else { continue }
            let dimmed = engine.phase == .selecting
                && !engine.selection.contains(position)
                && !engine.canExtend(to: position)
            node.setDimmed(dimmed)
        }
    }

    // MARK: - String

    private func prepareString() {
        guard let engine = session?.engine, let first = engine.selection.first else { return }
        let color = EmojiCatalog.entry(for: engine.board[first].type).glow
        stringOuter.strokeColor = color
        stringMiddle.strokeColor = color
        stringLayer.removeAllActions()
        stringLayer.alpha = 1
        stringLayer.isHidden = false
    }

    private func drawString() {
        guard let engine = session?.engine, engine.phase == .selecting, !engine.selection.isEmpty, tileSize > 0 else { return }
        let path = CGMutablePath()
        path.addLines(between: engine.selection.map { scenePoint($0) })
        var tip = scenePoint(engine.selection[engine.selection.count - 1])
        if let finger = fingerLocation {
            // The loose end follows the finger but goes taut at the remaining length.
            let reach = CGFloat(engine.remainingLength) * tileSize
            let dx = finger.x - tip.x, dy = finger.y - tip.y
            let distance = hypot(dx, dy)
            let scale = distance > reach && distance > 0 ? reach / distance : 1
            let taut = distance > reach
            tip = CGPoint(x: tip.x + dx * scale, y: tip.y + dy * scale)
            stringTip?.color = .systemRed
            stringTip?.colorBlendFactor = taut ? 0.9 : 0
        }
        path.addLine(to: tip)
        setStringPath(path, tip: tip)
    }

    private func setStringPath(_ path: CGPath, tip: CGPoint) {
        stringOuter.path = path
        stringMiddle.path = path
        stringCore.path = path
        stringTip?.position = tip
    }

    private func fadeOutString() {
        stringLayer.removeAllActions()
        stringLayer.run(.sequence([.fadeOut(withDuration: 0.12), .hide()]))
    }

    // MARK: - Match animation

    private func animate(_ resolution: MatchResolution) -> TimeInterval {
        let reduced = reduceMotion()
        let path = CGMutablePath()
        path.addLines(between: resolution.cleared.map { scenePoint($0.position) })
        setStringPath(path, tip: scenePoint(resolution.cleared[resolution.cleared.count - 1].position))
        let color = EmojiCatalog.entry(for: resolution.cleared[0].tile.type).glow
        stringOuter.strokeColor = color
        stringMiddle.strokeColor = color
        stringTip?.colorBlendFactor = 0
        stringLayer.alpha = 1
        stringLayer.isHidden = false
        fadeOutString()

        let tier = ComboTier(grabSize: resolution.cleared.count)
        // Combos pop one tile after another along the string.
        let stagger = reduced || tier == .none ? 0 : min(0.035, 0.14 / Double(resolution.cleared.count - 1))
        let popDuration = (reduced ? Timing.reducedPop : Timing.pop) + stagger * Double(resolution.cleared.count - 1)
        let vanishDuration = reduced ? Timing.reducedPop : Timing.pop
        for (index, cleared) in resolution.cleared.enumerated() {
            guard let node = tileNodes.removeValue(forKey: cleared.tile.id) else { continue }
            node.setSelected(true, reduceMotion: reduced)
            let vanish: SKAction = reduced
                ? .fadeOut(withDuration: vanishDuration)
                : .group([.scale(to: 1.45, duration: vanishDuration), .fadeOut(withDuration: vanishDuration)])
            vanish.timingMode = .easeOut
            let delay = stagger * Double(index)
            node.removeAllActions()
            node.run(.sequence([.wait(forDuration: delay), vanish, .removeFromParent()]))
            if !reduced { burstSparks(at: node.position, type: cleared.tile.type, delay: delay) }
        }
        let points = resolution.cleared.map { scenePoint($0.position) }
        showBadge("+\(resolution.points)", over: points, lift: 0, reduced: reduced)
        if resolution.raisedMultiplier {
            showBadge("×\(resolution.multiplier)!", over: points, lift: tileSize * 0.6, reduced: reduced)
        }
        if tier != .none {
            celebrate(tier, type: resolution.cleared[0].tile.type, over: points, reduced: reduced)
        }

        for node in tileNodes.values { node.setDimmed(false) }

        let fall = reduced ? Timing.reducedSettle : Timing.gravity
        for move in resolution.moves {
            guard let node = tileNodes[move.tile.id] else { continue }
            moveTile(node, to: scenePoint(move.to), delay: popDuration, duration: fall, reduced: reduced)
        }
        if let textures {
            for spawn in resolution.spawns {
                let node = TileNode(tile: spawn.tile, textures: textures)
                tileNodes[spawn.tile.id] = node
                boardLayer.addChild(node)
                let target = scenePoint(spawn.to)
                if reduced {
                    node.position = target
                    node.alpha = 0
                    node.run(.sequence([.wait(forDuration: popDuration), .fadeIn(withDuration: fall)]))
                } else {
                    node.position = CGPoint(x: target.x, y: scenePoint(Position(spawn.entryRow, spawn.to.column)).y)
                    moveTile(node, to: target, delay: popDuration, duration: fall, reduced: false)
                }
            }
        }

        var total = popDuration + fall
        if !resolution.reshuffle.isEmpty {
            let glide = reduced ? Timing.reducedSettle : Timing.reshuffle
            for move in resolution.reshuffle {
                guard let node = tileNodes[move.tile.id] else { continue }
                let action = SKAction.move(to: scenePoint(move.to), duration: glide)
                action.timingMode = .easeInEaseOut
                node.run(.sequence([.wait(forDuration: total), action]), withKey: "reshuffle")
            }
            total += glide
        }
        return total
    }

    private func moveTile(_ node: TileNode, to target: CGPoint, delay: TimeInterval, duration: TimeInterval, reduced: Bool) {
        if reduced {
            node.run(.sequence([.wait(forDuration: delay), .move(to: target, duration: duration)]))
            return
        }
        let fall = SKAction.move(to: target, duration: duration * 0.85)
        fall.timingMode = .easeIn
        let squash = SKAction.sequence([
            .group([.scaleX(to: 1.06, duration: duration * 0.07), .scaleY(to: 0.92, duration: duration * 0.07)]),
            .group([.scaleX(to: 1, duration: duration * 0.08), .scaleY(to: 1, duration: duration * 0.08)]),
        ])
        node.run(.sequence([.wait(forDuration: delay), fall, squash]))
    }

    private func burstSparks(at center: CGPoint, type: Int, delay: TimeInterval) {
        guard let textures else { return }
        let color = EmojiCatalog.entry(for: type).glow
        for index in 0..<8 {
            let angle = CGFloat(index) / 8 * 2 * .pi + .random(in: -0.2...0.2)
            let spark = SKSpriteNode(texture: textures.spark)
            spark.size = CGSize(width: tileSize * 0.28, height: tileSize * 0.28)
            spark.color = color
            spark.colorBlendFactor = 1
            spark.position = center
            spark.alpha = 0
            spark.zPosition = TileNode.Z.effects
            boardLayer.addChild(spark)
            let travel = tileSize * .random(in: 0.5...0.85)
            let flight = SKAction.group([
                .move(by: CGVector(dx: cos(angle) * travel, dy: sin(angle) * travel), duration: 0.32),
                .fadeOut(withDuration: 0.32),
                .scale(to: 0.3, duration: 0.32),
            ])
            flight.timingMode = .easeOut
            spark.run(.sequence([.wait(forDuration: delay), .fadeIn(withDuration: 0), flight, .removeFromParent()]))
        }
    }

    // MARK: - Combo animation

    /// Bigger grabs layer on more: callout, then rings and flying emoji, then shake, then flash.
    private func celebrate(_ tier: ComboTier, type: Int, over points: [CGPoint], reduced: Bool) {
        let center = CGPoint(
            x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
            y: points.map(\.y).reduce(0, +) / CGFloat(points.count)
        )
        if let title = tier.title { showCallout(title, tier: tier, awayFrom: center, reduced: reduced) }
        guard !reduced else { return }
        let color = EmojiCatalog.entry(for: type).glow
        showRings(at: center, count: tier.rawValue, color: color)
        launchEmoji(type: type, from: points, count: tier.rawValue * 5)
        if tier >= .great { shakeBoard(strength: tier.rawValue - 1) }
        if tier >= .amazing { flashBoard(color: color) }
    }

    /// Sits in the half of the board away from the grab so it doesn't cover the point badges.
    private func showCallout(_ text: String, tier: ComboTier, awayFrom center: CGPoint, reduced: Bool) {
        guard let textures else { return }
        lastCallout = text
        let callout = SKSpriteNode(texture: textures.badge(text))
        let scale = min(1 + 0.12 * CGFloat(tier.rawValue), (size.width - Self.padding * 2) / callout.size.width)
        callout.position = CGPoint(x: 0, y: center.y > 0 ? -size.height * 0.16 : size.height * 0.16)
        callout.zPosition = TileNode.Z.effects + 2
        boardLayer.addChild(callout)
        if reduced {
            callout.setScale(scale)
            callout.run(.sequence([.wait(forDuration: 0.6), .fadeOut(withDuration: 0.2), .removeFromParent()]))
            return
        }
        callout.setScale(0.3)
        callout.zRotation = -0.12
        let grow = SKAction.scale(to: scale * 1.2, duration: 0.14)
        grow.timingMode = .easeOut
        let settle = SKAction.group([.scale(to: scale, duration: 0.1), .rotate(toAngle: 0, duration: 0.1)])
        callout.run(.sequence([
            grow,
            settle,
            .wait(forDuration: 0.4),
            .group([.fadeOut(withDuration: 0.22), .moveBy(x: 0, y: tileSize * 0.4, duration: 0.22)]),
            .removeFromParent(),
        ]))
    }

    private func showRings(at center: CGPoint, count: Int, color: UIColor) {
        for index in 0..<count {
            let ring = SKShapeNode(circleOfRadius: tileSize * 0.5)
            ring.strokeColor = color
            ring.lineWidth = tileSize * 0.08
            ring.fillColor = .clear
            ring.position = center
            ring.alpha = 0
            ring.zPosition = TileNode.Z.effects - 1
            boardLayer.addChild(ring)
            let expand = SKAction.group([
                .scale(to: 2.5 + CGFloat(count), duration: 0.45),
                .fadeOut(withDuration: 0.45),
            ])
            expand.timingMode = .easeOut
            ring.run(.sequence([
                .wait(forDuration: Double(index) * 0.08),
                .fadeIn(withDuration: 0),
                expand,
                .removeFromParent(),
            ]))
        }
    }

    /// The popped emoji leap out of the board, tumble, and fall away.
    private func launchEmoji(type: Int, from points: [CGPoint], count: Int) {
        guard let textures, !points.isEmpty else { return }
        for index in 0..<count {
            let piece = SKSpriteNode(texture: textures.emoji(type))
            piece.size = CGSize(width: tileSize * 0.8, height: tileSize * 0.8)
            piece.position = points[index % points.count]
            piece.zPosition = TileNode.Z.effects
            boardLayer.addChild(piece)
            let drift = tileSize * .random(in: -1.6...1.6)
            let rise = SKAction.moveBy(x: drift * 0.4, y: tileSize * .random(in: 0.9...2), duration: 0.24)
            rise.timingMode = .easeOut
            let drop = SKAction.moveBy(x: drift * 0.6, y: -tileSize * .random(in: 2.5...4), duration: 0.46)
            drop.timingMode = .easeIn
            piece.run(.sequence([
                .group([
                    .sequence([rise, drop]),
                    .rotate(byAngle: .random(in: -4...4), duration: 0.7),
                    .sequence([.wait(forDuration: 0.4), .fadeOut(withDuration: 0.3)]),
                ]),
                .removeFromParent(),
            ]))
        }
    }

    private func shakeBoard(strength: Int) {
        let amount = tileSize * 0.04 * CGFloat(strength)
        var steps: [SKAction] = []
        for step in 0..<6 {
            let sign: CGFloat = step.isMultiple(of: 2) ? 1 : -1
            let fade = CGFloat(6 - step) / 6
            steps.append(.move(to: CGPoint(x: sign * amount * fade, y: -sign * amount * fade * 0.5), duration: 0.035))
        }
        steps.append(.move(to: .zero, duration: 0.03))
        boardLayer.removeAction(forKey: "shake")
        boardLayer.run(.sequence(steps), withKey: "shake")
    }

    /// Deliberately faint and single: a color wash, not a strobe.
    private func flashBoard(color: UIColor) {
        let flash = SKSpriteNode(color: color, size: size)
        flash.alpha = 0.22
        flash.zPosition = TileNode.Z.effects - 2
        boardLayer.addChild(flash)
        flash.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
    }

    private func showBadge(_ text: String, over points: [CGPoint], lift: CGFloat, reduced: Bool) {
        guard let textures else { return }
        let badge = SKSpriteNode(texture: textures.badge(text))
        let x = points.map(\.x).reduce(0, +) / CGFloat(points.count)
        let y = points.map(\.y).reduce(0, +) / CGFloat(points.count)
        let halfWidth = badge.size.width / 2
        badge.position = CGPoint(x: min(max(x, -size.width / 2 + halfWidth), size.width / 2 - halfWidth), y: y + lift)
        badge.zPosition = TileNode.Z.effects + 1
        boardLayer.addChild(badge)
        if reduced {
            badge.run(.sequence([.wait(forDuration: 0.45), .fadeOut(withDuration: 0.2), .removeFromParent()]))
        } else {
            badge.setScale(0.6)
            let pop = SKAction.scale(to: 1, duration: 0.14)
            pop.timingMode = .easeOut
            let rise = SKAction.moveBy(x: 0, y: tileSize * 0.8, duration: 0.7)
            rise.timingMode = .easeOut
            badge.run(.sequence([
                .group([pop, rise, .sequence([.wait(forDuration: 0.45), .fadeOut(withDuration: 0.25)])]),
                .removeFromParent(),
            ]))
        }
    }

    // MARK: - Inspection for tests

    var liveTileCount: Int { tileNodes.count }
}
