import SpriteKit
import UIKit

// MARK: - Types

struct DotPixel {
    var radius: CGFloat
    var color: UIColor

    static let off = DotPixel(radius: 0.4, color: UIColor(white: 0.78, alpha: 1.0))
    static let lit = DotPixel(radius: 0.8, color: UIColor(red: 0.15, green: 0.15, blue: 0.13, alpha: 1.0))
}

struct DotFrame {
    var pixels: [DotPixel]

    static let gridSize = 64
    static let count = gridSize * gridSize

    init() {
        pixels = [DotPixel](repeating: .off, count: Self.count)
    }

    init(pixels: [DotPixel]) {
        assert(pixels.count == Self.count)
        self.pixels = pixels
    }

    subscript(col: Int, row: Int) -> DotPixel {
        get { pixels[row * Self.gridSize + col] }
        set { pixels[row * Self.gridSize + col] = newValue }
    }
}

enum TransitionStyle {
    case shrinkGrow
    case decayRegrow
    case crtShutdown
}

// MARK: - Scene

class DotGridScene: SKScene {

    private let gridSize = DotFrame.gridSize
    private var dots: [SKSpriteNode] = []
    private var edgeAlpha: [CGFloat] = []
    private var dotSpacing: CGFloat = 0
    private var circleTexture: SKTexture!

    // Animation state
    private var targetFrame = DotFrame()
    private var isAnimating = false
    private var entrancePlayed = false

    // Touch ripple
    private var touchLocation: CGPoint?
    private var rippleActive = false

    // MARK: - Setup

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        anchorPoint = .zero
        setupDots()
    }

    private func setupDots() {
        // Create shared circle texture once
        let dotDiameter: CGFloat = 8
        let shape = SKShapeNode(circleOfRadius: dotDiameter / 2)
        shape.fillColor = .white
        shape.strokeColor = .clear
        circleTexture = view!.texture(from: shape)!

        dotSpacing = size.width / CGFloat(gridSize)
        let halfSpacing = dotSpacing / 2

        dots.reserveCapacity(gridSize * gridSize)
        edgeAlpha.reserveCapacity(gridSize * gridSize)

        let fadeZone: CGFloat = 8.0

        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let sprite = SKSpriteNode(texture: circleTexture)
                sprite.position = CGPoint(
                    x: CGFloat(col) * dotSpacing + halfSpacing,
                    y: size.height - (CGFloat(row) * dotSpacing + halfSpacing)
                )
                sprite.setScale(DotPixel.off.radius * dotSpacing / 8)
                sprite.color = DotPixel.off.color
                sprite.colorBlendFactor = 1.0
                sprite.alpha = 0 // hidden initially for entrance
                addChild(sprite)
                dots.append(sprite)

                // Compute per-dot edge alpha (quadratic easing for softer falloff)
                let edgeDist = CGFloat(min(col, row, gridSize - 1 - col, gridSize - 1 - row))
                let t = min(edgeDist / fadeZone, 1.0)
                edgeAlpha.append(t * t)
            }
        }
    }

    // MARK: - Entrance Animation

    func playEntranceAnimation(completion: (() -> Void)? = nil) {
        guard !entrancePlayed else {
            completion?()
            return
        }
        entrancePlayed = true

        let totalDuration: TimeInterval = 0.5
        let maxDiag = CGFloat(gridSize + gridSize - 2)

        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let idx = row * gridSize + col
                let diag = CGFloat(col + row)
                let delay = (diag / maxDiag) * totalDuration

                let sprite = dots[idx]
                let alpha = edgeAlpha[idx]
                sprite.run(
                    .sequence([
                        .wait(forDuration: delay),
                        .group([
                            .fadeAlpha(to: alpha, duration: 0.15),
                            .scale(to: DotPixel.off.radius * dotSpacing / 8, duration: 0.15)
                        ])
                    ])
                )
            }
        }

        // Fire completion after full animation
        run(.sequence([
            .wait(forDuration: totalDuration + 0.2),
            .run { completion?() }
        ]))
    }

    // MARK: - Frame Application

    func applyFrame(_ frame: DotFrame, animated: Bool = true) {
        targetFrame = frame
        let duration: TimeInterval = animated ? 0.2 : 0

        for i in 0..<DotFrame.count {
            let pixel = frame.pixels[i]
            let sprite = dots[i]
            let targetScale = pixel.radius * dotSpacing / 8

            let alpha = edgeAlpha.isEmpty ? 1.0 : edgeAlpha[i]
            if animated {
                sprite.run(.group([
                    .scale(to: targetScale, duration: duration),
                    .colorize(with: pixel.color, colorBlendFactor: 1.0, duration: duration),
                    .fadeAlpha(to: alpha, duration: duration)
                ]))
            } else {
                sprite.setScale(targetScale)
                sprite.color = pixel.color
                sprite.alpha = alpha
            }
        }
    }

    // MARK: - Transitions

    func transitionToFrame(_ frame: DotFrame, style: TransitionStyle, completion: (() -> Void)? = nil) {
        switch style {
        case .shrinkGrow:
            shrinkGrowTransition(to: frame, completion: completion)
        case .decayRegrow:
            decayRegrowTransition(to: frame, completion: completion)
        case .crtShutdown:
            crtShutdownTransition(to: frame, completion: completion)
        }
    }

    private func shrinkGrowTransition(to frame: DotFrame, completion: (() -> Void)?) {
        guard !isAnimating else { return }
        isAnimating = true

        let shrinkDuration: TimeInterval = 0.2
        let growDuration: TimeInterval = 0.25

        // Phase 1: shrink all to zero
        for sprite in dots {
            sprite.run(.scale(to: 0, duration: shrinkDuration))
        }

        // Phase 2: swap frame and grow back
        run(.sequence([
            .wait(forDuration: shrinkDuration + 0.05),
            .run { [weak self] in
                guard let self else { return }
                self.applyFrame(frame, animated: false)
                // Now scale up with edge alpha
                for i in 0..<DotFrame.count {
                    let pixel = frame.pixels[i]
                    let targetScale = pixel.radius * self.dotSpacing / 8
                    let alpha = self.edgeAlpha.isEmpty ? 1.0 : self.edgeAlpha[i]
                    self.dots[i].setScale(0)
                    self.dots[i].alpha = 0
                    self.dots[i].run(.group([
                        .scale(to: targetScale, duration: growDuration),
                        .fadeAlpha(to: alpha, duration: growDuration)
                    ]))
                }
            },
            .wait(forDuration: growDuration + 0.05),
            .run { [weak self] in
                self?.isAnimating = false
                completion?()
            }
        ]))
    }

    private func decayRegrowTransition(to frame: DotFrame, completion: (() -> Void)?) {
        guard !isAnimating else { return }
        isAnimating = true

        let decaySpread: TimeInterval = 0.3
        let decayDuration: TimeInterval = 0.12
        let gap: TimeInterval = 0.05
        let regrowSpread: TimeInterval = 0.3
        let regrowDuration: TimeInterval = 0.12

        // Pre-generate random delays for deterministic animation within this transition
        let decayDelays = (0..<DotFrame.count).map { _ in Double.random(in: 0...decaySpread) }
        let regrowDelays = (0..<DotFrame.count).map { _ in Double.random(in: 0...regrowSpread) }

        // Phase 1: Decay — each dot shrinks to 0 after a random delay
        for i in 0..<DotFrame.count {
            let sprite = dots[i]
            sprite.run(.sequence([
                .wait(forDuration: decayDelays[i]),
                .scale(to: 0, duration: decayDuration)
            ]))
        }

        // Phase 2: After all dots have decayed, swap and regrow
        let phase2Start = decaySpread + decayDuration + gap
        run(.sequence([
            .wait(forDuration: phase2Start),
            .run { [weak self] in
                guard let self else { return }
                self.targetFrame = frame
                for i in 0..<DotFrame.count {
                    let sprite = self.dots[i]
                    let pixel = frame.pixels[i]
                    let targetScale = pixel.radius * self.dotSpacing / 8
                    let alpha = self.edgeAlpha.isEmpty ? 1.0 : self.edgeAlpha[i]

                    // Swap color instantly at scale 0
                    sprite.color = pixel.color
                    sprite.setScale(0)
                    sprite.alpha = 0

                    // Regrow after random delay
                    sprite.run(.sequence([
                        .wait(forDuration: regrowDelays[i]),
                        .group([
                            .scale(to: targetScale, duration: regrowDuration),
                            .fadeAlpha(to: alpha, duration: regrowDuration)
                        ])
                    ]))
                }
            },
            .wait(forDuration: regrowSpread + regrowDuration + 0.05),
            .run { [weak self] in
                self?.isAnimating = false
                completion?()
            }
        ]))
    }

    private func crtShutdownTransition(to frame: DotFrame, completion: (() -> Void)?) {
        // Collapse rows to center line, then expand with new frame
        guard !isAnimating else { return }
        isAnimating = true

        let collapseDuration: TimeInterval = 0.2
        let expandDuration: TimeInterval = 0.25
        let centerY = size.height / 2

        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let idx = row * gridSize + col
                let sprite = dots[idx]
                let targetPos = CGPoint(x: sprite.position.x, y: centerY)
                sprite.run(.group([
                    .move(to: targetPos, duration: collapseDuration),
                    .scale(to: 0, duration: collapseDuration)
                ]))
            }
        }

        run(.sequence([
            .wait(forDuration: collapseDuration + 0.05),
            .run { [weak self] in
                guard let self else { return }
                let halfSpacing = self.dotSpacing / 2
                // Reset positions and apply new frame
                for row in 0..<self.gridSize {
                    for col in 0..<self.gridSize {
                        let idx = row * self.gridSize + col
                        let sprite = self.dots[idx]
                        let pixel = frame.pixels[idx]
                        let originalY = self.size.height - (CGFloat(row) * self.dotSpacing + halfSpacing)
                        sprite.position.y = centerY
                        sprite.color = pixel.color
                        sprite.setScale(0)
                        sprite.alpha = 0

                        let targetScale = pixel.radius * self.dotSpacing / 8
                        let alpha = self.edgeAlpha.isEmpty ? 1.0 : self.edgeAlpha[idx]
                        sprite.run(.group([
                            .move(to: CGPoint(x: sprite.position.x, y: originalY), duration: expandDuration),
                            .scale(to: targetScale, duration: expandDuration),
                            .fadeAlpha(to: alpha, duration: expandDuration)
                        ]))
                    }
                }
                self.targetFrame = frame
            },
            .wait(forDuration: expandDuration + 0.05),
            .run { [weak self] in
                self?.isAnimating = false
                completion?()
            }
        ]))
    }

    // MARK: - Touch Handling (Ripple)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        touchLocation = touch.location(in: self)
        rippleActive = true
        applyRipple()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        touchLocation = touch.location(in: self)
        applyRipple()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        rippleActive = false
        touchLocation = nil
        // Animate back to target frame
        applyFrame(targetFrame, animated: true)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        rippleActive = false
        touchLocation = nil
        applyFrame(targetFrame, animated: true)
    }

    private func applyRipple() {
        guard let center = touchLocation else { return }
        let rippleRadius: CGFloat = dotSpacing * 8 // affects ~8 dots radius

        for i in 0..<dots.count {
            let sprite = dots[i]
            let dist = hypot(sprite.position.x - center.x, sprite.position.y - center.y)
            let influence = max(0, 1.0 - (dist / rippleRadius))
            let gaussian = influence * influence // quadratic falloff

            let basePixel = targetFrame.pixels[i]
            let baseScale = basePixel.radius * dotSpacing / 8
            let bumpScale = baseScale + gaussian * dotSpacing * 0.15

            // Blend color toward accent
            let accentColor = UIColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 1.0)
            let blendedColor = blendColor(from: basePixel.color, to: accentColor, amount: gaussian * 0.6)

            let alpha = edgeAlpha.isEmpty ? 1.0 : edgeAlpha[i]
            sprite.removeAllActions()
            sprite.setScale(bumpScale)
            sprite.color = blendedColor
            sprite.alpha = alpha
        }
    }

    private func blendColor(from: UIColor, to: UIColor, amount: CGFloat) -> UIColor {
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        from.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        to.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        let t = min(max(amount, 0), 1)
        return UIColor(
            red: fr + (tr - fr) * t,
            green: fg + (tg - fg) * t,
            blue: fb + (tb - fb) * t,
            alpha: fa + (ta - fa) * t
        )
    }
}
