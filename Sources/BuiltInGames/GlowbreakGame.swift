import Foundation
import SwiftUI

// MARK: - Glowbreak — original neon brick-breaker (pure logic)
//
// %100 özgün, telifsiz bir tuğla-kırma oyunu. Tema: neon/glow (Glowchase'in
// kardeşi). Combo sayacı, düşen güçlendirmeler (çoklu top, geniş raket),
// seviye desenleri ve parçacık efektleri. Mantık framework'ten bağımsızdır;
// GlowbreakView çizim + dokunuşu üstlenir.

enum GlowbreakState { case ready, playing, levelCleared, gameOver }

struct GBBall: Identifiable {
    let id = UUID()
    var pos: CGPoint
    var vel: CGVector
}

struct GBBrick: Identifiable {
    let id: Int
    var rect: CGRect
    var hp: Int
    let row: Int
}

enum GBPowerKind { case multiball, widePaddle }

struct GBPower: Identifiable {
    let id = UUID()
    var kind: GBPowerKind
    var pos: CGPoint
}

struct GBParticle: Identifiable {
    let id = UUID()
    var pos: CGPoint
    var vel: CGVector
    var life: Double      // 1 → 0
    var hue: Double
}

final class GlowbreakGame: ObservableObject {

    // Field in points — set once by the view when geometry is known.
    private(set) var field = CGSize(width: 850, height: 390)

    @Published private(set) var state: GlowbreakState = .ready
    @Published private(set) var score = 0
    @Published private(set) var highScore = UserDefaults.standard.integer(forKey: "glowbreak.highScore")
    @Published private(set) var lives = 3
    @Published private(set) var level = 1
    @Published private(set) var combo = 0

    @Published private(set) var balls: [GBBall] = []
    @Published private(set) var bricks: [GBBrick] = []
    @Published private(set) var powerups: [GBPower] = []
    @Published private(set) var particles: [GBParticle] = []

    @Published private(set) var paddleX: CGFloat = 425

    // Event counters — the view observes deltas to fire haptics without the
    // logic layer knowing UIKit exists.
    @Published private(set) var brickHitEvents = 0
    @Published private(set) var paddleHitEvents = 0
    @Published private(set) var lifeLostEvents = 0
    @Published private(set) var powerupEvents = 0

    // MARK: Tunables

    let ballR: CGFloat = 6
    let paddleH: CGFloat = 13
    private var wideRemaining: TimeInterval = 0
    private var levelClearTimer: TimeInterval = 0

    var isWide: Bool { wideRemaining > 0 }
    var paddleW: CGFloat {
        let base = max(field.width * 0.13, 92)
        return isWide ? base * 1.55 : base
    }
    var paddleY: CGFloat { field.height - 30 }

    private var ballSpeed: CGFloat {
        let scale = field.height / 390
        return min(330 + CGFloat(level - 1) * 28, 560) * scale
    }

    // MARK: Lifecycle

    /// Called by the view once real geometry is known. Only rebuilds while a
    /// fresh game is sitting on the ready screen (landscape size is stable).
    func configure(size: CGSize) {
        guard size.width > 100, size.height > 100, size != field else { return }
        field = size
        if state == .ready && score == 0 && level == 1 {
            resetAll()
        }
    }

    func resetAll() {
        score = 0
        lives = 3
        level = 1
        combo = 0
        wideRemaining = 0
        powerups = []
        particles = []
        paddleX = field.width / 2
        buildLevel()
        glueBall()
        state = .ready
    }

    /// Start button / tap: from gameOver does a full reset to ready; from
    /// ready launches the glued ball.
    func startOrLaunch() {
        switch state {
        case .gameOver:
            resetAll()
        case .ready:
            launch()
        default:
            break
        }
    }

    private func launch() {
        guard state == .ready, !balls.isEmpty else { return }
        // -75°…-105°: always upward, slight random tilt.
        let deg = Double.random(in: -105 ... -75)
        let rad = deg * .pi / 180
        balls[0].vel = CGVector(dx: cos(rad) * ballSpeed, dy: sin(rad) * ballSpeed)
        state = .playing
    }

    func setPaddle(x: CGFloat) {
        let half = paddleW / 2
        paddleX = min(max(x, half + 6), field.width - half - 6)
        if state == .ready { glueBallToPaddle() }
    }

    func movePaddle(dx: CGFloat) {
        setPaddle(x: paddleX + dx)
    }

    private func glueBall() {
        balls = [GBBall(pos: gluedPos(), vel: .zero)]
    }

    private func glueBallToPaddle() {
        guard state == .ready, !balls.isEmpty else { return }
        balls[0].pos = gluedPos()
    }

    private func gluedPos() -> CGPoint {
        CGPoint(x: paddleX, y: paddleY - paddleH / 2 - ballR - 1)
    }

    // MARK: Level patterns

    private func buildLevel() {
        let cols = 11, rows = 5
        let sideMargin: CGFloat = max(field.width * 0.075, 56)
        let top: CGFloat = 52
        let gap: CGFloat = 5
        let brickH: CGFloat = 18
        let brickW = (field.width - sideMargin * 2 - gap * CGFloat(cols - 1)) / CGFloat(cols)

        var out: [GBBrick] = []
        var idx = 0
        for r in 0..<rows {
            for c in 0..<cols {
                // Pattern per level: 0 full · 1 checker · 2 pyramid · 3 hollow frame
                let pattern = (level - 1) % 4
                let centered = abs(c - cols / 2)
                let keep: Bool
                switch pattern {
                case 1:  keep = (r + c) % 2 == 0
                case 2:  keep = centered <= r + 1
                case 3:  keep = r == 0 || r == rows - 1 || c == 0 || c == cols - 1 || (r + c) % 3 == 0
                default: keep = true
                }
                guard keep else { continue }

                let rect = CGRect(
                    x: sideMargin + CGFloat(c) * (brickW + gap),
                    y: top + CGFloat(r) * (brickH + gap),
                    width: brickW, height: brickH
                )
                // From level 2 on, the top rows take two hits.
                let hp = (level >= 2 && r < 2) ? 2 : 1
                out.append(GBBrick(id: idx, rect: rect, hp: hp, row: r))
                idx += 1
            }
        }
        bricks = out
    }

    // MARK: Simulation

    func tick(dt rawDT: TimeInterval) {
        let dt = min(rawDT, 1.0 / 30.0)

        if wideRemaining > 0 { wideRemaining = max(0, wideRemaining - dt) }
        updateParticles(dt)

        switch state {
        case .playing:
            updateBalls(dt)
            updatePowerups(dt)
            if bricks.isEmpty {
                state = .levelCleared
                levelClearTimer = 1.4
            }
        case .levelCleared:
            levelClearTimer -= dt
            if levelClearTimer <= 0 {
                level += 1
                powerups = []
                buildLevel()
                glueBall()
                state = .ready
            }
        default:
            break
        }
    }

    private func updateBalls(_ dt: TimeInterval) {
        // Substep so a fast ball can't tunnel through bricks/paddle.
        let maxStep: CGFloat = 7
        let speed = ballSpeed
        let steps = max(1, Int((speed * CGFloat(dt) / maxStep).rounded(.up)))
        let stepDT = CGFloat(dt) / CGFloat(steps)

        for _ in 0..<steps {
            var kept: [GBBall] = []
            for var ball in balls {
                ball.pos.x += ball.vel.dx * stepDT
                ball.pos.y += ball.vel.dy * stepDT

                // Walls
                if ball.pos.x < ballR { ball.pos.x = ballR; ball.vel.dx = abs(ball.vel.dx) }
                if ball.pos.x > field.width - ballR { ball.pos.x = field.width - ballR; ball.vel.dx = -abs(ball.vel.dx) }
                if ball.pos.y < ballR { ball.pos.y = ballR; ball.vel.dy = abs(ball.vel.dy) }

                // Paddle
                let pRect = CGRect(x: paddleX - paddleW / 2, y: paddleY - paddleH / 2,
                                   width: paddleW, height: paddleH)
                if ball.vel.dy > 0,
                   ball.pos.y + ballR >= pRect.minY, ball.pos.y - ballR <= pRect.maxY,
                   ball.pos.x >= pRect.minX - ballR, ball.pos.x <= pRect.maxX + ballR {
                    // Reflect upward; exit angle follows the hit offset.
                    let offset = (ball.pos.x - paddleX) / (paddleW / 2)   // -1…1
                    let maxTilt: CGFloat = 0.74                            // ≈48°
                    let tilt = max(-maxTilt, min(maxTilt, offset * 0.74))
                    let ang = -CGFloat.pi / 2 + tilt
                    ball.vel = CGVector(dx: cos(ang) * speed, dy: sin(ang) * speed)
                    ball.pos.y = pRect.minY - ballR
                    combo = 0
                    paddleHitEvents += 1
                }

                // Bricks
                if let hit = bricks.firstIndex(where: { circleHits($0.rect, ball.pos) }) {
                    let rect = bricks[hit].rect
                    // Resolve on the axis of least penetration.
                    let fromLeft   = abs(ball.pos.x - rect.minX)
                    let fromRight  = abs(rect.maxX - ball.pos.x)
                    let fromTop    = abs(ball.pos.y - rect.minY)
                    let fromBottom = abs(rect.maxY - ball.pos.y)
                    let minX = min(fromLeft, fromRight), minY = min(fromTop, fromBottom)
                    if minX < minY { ball.vel.dx = fromLeft < fromRight ? -abs(ball.vel.dx) : abs(ball.vel.dx) }
                    else           { ball.vel.dy = fromTop < fromBottom ? -abs(ball.vel.dy) : abs(ball.vel.dy) }

                    bricks[hit].hp -= 1
                    brickHitEvents += 1
                    if bricks[hit].hp <= 0 {
                        combo += 1
                        score += 10 * combo
                        spawnBurst(at: CGPoint(x: rect.midX, y: rect.midY),
                                   hue: hueForRow(bricks[hit].row))
                        maybeDropPower(at: CGPoint(x: rect.midX, y: rect.midY))
                        bricks.remove(at: hit)
                    }
                }

                // Floor
                if ball.pos.y - ballR > field.height + 12 { continue }   // ball lost
                kept.append(ball)
            }
            balls = kept
            if balls.isEmpty { loseLife(); return }
        }
    }

    private func circleHits(_ rect: CGRect, _ p: CGPoint) -> Bool {
        let cx = max(rect.minX, min(p.x, rect.maxX))
        let cy = max(rect.minY, min(p.y, rect.maxY))
        let dx = p.x - cx, dy = p.y - cy
        return dx * dx + dy * dy <= ballR * ballR
    }

    private func loseLife() {
        lives -= 1
        combo = 0
        powerups = []
        wideRemaining = 0
        lifeLostEvents += 1
        if lives <= 0 {
            state = .gameOver
            if score > highScore {
                highScore = score
                UserDefaults.standard.set(highScore, forKey: "glowbreak.highScore")
            }
        } else {
            glueBall()
            state = .ready
        }
    }

    // MARK: Power-ups

    private func maybeDropPower(at p: CGPoint) {
        guard powerups.count < 2, Double.random(in: 0..<1) < 0.13 else { return }
        let kind: GBPowerKind = Bool.random() ? .multiball : .widePaddle
        powerups.append(GBPower(kind: kind, pos: p))
    }

    private func updatePowerups(_ dt: TimeInterval) {
        let fall = 150 * (field.height / 390) * CGFloat(dt)
        var kept: [GBPower] = []
        for var pw in powerups {
            pw.pos.y += fall
            let pRect = CGRect(x: paddleX - paddleW / 2 - 8, y: paddleY - paddleH / 2 - 6,
                               width: paddleW + 16, height: paddleH + 12)
            if pRect.contains(pw.pos) {
                apply(pw.kind)
                powerupEvents += 1
                continue
            }
            if pw.pos.y < field.height + 16 { kept.append(pw) }
        }
        powerups = kept
    }

    private func apply(_ kind: GBPowerKind) {
        switch kind {
        case .widePaddle:
            wideRemaining = 10
        case .multiball:
            guard !balls.isEmpty, balls.count < 6 else { return }
            // Split every ball into a fan of three (capped at 6 total).
            var spawned: [GBBall] = []
            for ball in balls where spawned.count + balls.count < 6 {
                for tilt in [-0.45, 0.45] {
                    let ang = atan2(ball.vel.dy, ball.vel.dx) + CGFloat(tilt)
                    let sp = max(hypot(ball.vel.dx, ball.vel.dy), ballSpeed * 0.9)
                    spawned.append(GBBall(pos: ball.pos,
                                          vel: CGVector(dx: cos(ang) * sp, dy: sin(ang) * sp)))
                }
            }
            balls.append(contentsOf: spawned.prefix(6 - balls.count))
        }
    }

    // MARK: Particles

    func hueForRow(_ row: Int) -> Double {
        // Neon ramp: pink → purple → blue → cyan → green
        [0.89, 0.76, 0.62, 0.52, 0.38][row % 5]
    }

    private func spawnBurst(at p: CGPoint, hue: Double) {
        guard particles.count < 80 else { return }
        for _ in 0..<7 {
            let ang = Double.random(in: 0..<(2 * .pi))
            let sp = Double.random(in: 40...170)
            particles.append(GBParticle(
                pos: p,
                vel: CGVector(dx: cos(ang) * sp, dy: sin(ang) * sp - 30),
                life: 1.0, hue: hue
            ))
        }
    }

    private func updateParticles(_ dt: TimeInterval) {
        guard !particles.isEmpty else { return }
        var kept: [GBParticle] = []
        for var pt in particles {
            pt.life -= dt * 2.1
            guard pt.life > 0 else { continue }
            pt.vel.dy += 260 * dt          // gravity
            pt.pos.x += pt.vel.dx * dt
            pt.pos.y += pt.vel.dy * dt
            kept.append(pt)
        }
        particles = kept
    }
}
