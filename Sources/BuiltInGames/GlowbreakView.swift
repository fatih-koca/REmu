import SwiftUI
import UIKit

// MARK: - Playable SwiftUI view for the Glowbreak demo
//
// Mirrors CoilpedeView's shell (top strip, pause/ready/game-over overlays,
// gamepad hooks) with a Canvas-rendered neon brick-breaker inside. The
// TimelineView runs at up to 120 Hz; the game advances by real delta-time,
// so pacing is identical on 60 Hz and ProMotion panels.

struct GlowbreakView: View {
    @StateObject private var game = GlowbreakGame()
    let onExit: () -> Void

    @State private var lastTick: Date = Date()
    @State private var isPaused = false
    @State private var gameOverAdFired = false
    @State private var padHeld: CGFloat = 0     // -1 / 0 / +1 from d-pad holds

    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    private let softHaptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        GeometryReader { geo in
            let inset = geo.safeAreaInsets

            ZStack {
                Color.black
                arenaView

                VStack(spacing: 0) {
                    GameInfoTopStrip(
                        title: "Glowbreak",
                        subtitle: String(localized: "BUILT-IN"),
                        stats: [
                            (String(localized: "SCORE"), "\(game.score)"),
                            (String(localized: "BEST"),  "\(game.highScore)"),
                            (String(localized: "LVL"),   "\(game.level)"),
                            (String(localized: "LIVES"), "\(game.lives)"),
                        ],
                        onPause: {
                            softHaptic.impactOccurred()
                            isPaused = true
                        }
                    )
                    Spacer(minLength: 0)
                }
                .padding(.leading,  inset.leading  + 4)
                .padding(.trailing, inset.trailing + 4)
                .padding(.top,      max(inset.top,    4))
                .padding(.bottom,   max(inset.bottom, 4))

                if (game.state == .ready && game.score == 0 && game.level == 1)
                    || game.state == .gameOver, !isPaused {
                    overlayCard
                }

                if isPaused {
                    pauseOverlay
                }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            lastTick = Date()
            haptic.prepare()
            softHaptic.prepare()
            GameControllerManager.shared.onAction = { action in
                handleGamepadAction(action)
            }
        }
        .onDisappear {
            GameControllerManager.shared.onAction = nil
        }
        .onChange(of: game.brickHitEvents)  { _ in softHaptic.impactOccurred() }
        .onChange(of: game.paddleHitEvents) { _ in softHaptic.impactOccurred(intensity: 0.6) }
        .onChange(of: game.powerupEvents)   { _ in haptic.impactOccurred() }
        .onChange(of: game.lifeLostEvents)  { _ in
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        .background(
            TimelineView(.animation(minimumInterval: 1.0 / 120.0)) { context in
                Color.clear
                    .onChange(of: context.date) { _ in
                        advance(now: context.date)
                    }
            }
        )
    }

    // MARK: - Arena

    private var arenaView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.05, blue: 0.16),
                    Color(red: 0.03, green: 0.02, blue: 0.08),
                ],
                startPoint: .top, endPoint: .bottom
            )

            GeometryReader { proxy in
                Canvas { ctx, size in
                    draw(in: &ctx, size: size)
                }
                .onAppear { game.configure(size: proxy.size) }
                .onChange(of: proxy.size) { game.configure(size: $0) }
            }
        }
        .contentShape(Rectangle())
        .gesture(paddleGesture)
    }

    private var paddleGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                game.setPaddle(x: v.location.x)
            }
            .onEnded { v in
                if abs(v.translation.width) < 10 && abs(v.translation.height) < 10 {
                    softHaptic.impactOccurred()
                    game.startOrLaunch()
                }
            }
    }

    // MARK: - Canvas drawing

    private func draw(in ctx: inout GraphicsContext, size: CGSize) {
        // Bricks — body + faked glow halo (cheap: one translucent under-rect).
        for brick in game.bricks {
            let hue = game.hueForRow(brick.row)
            let bright = brick.hp >= 2
            let color = Color(hue: hue, saturation: 0.85, brightness: bright ? 1.0 : 0.82)

            let halo = Path(roundedRect: brick.rect.insetBy(dx: -2.5, dy: -2.5), cornerRadius: 6)
            ctx.fill(halo, with: .color(color.opacity(0.22)))

            let body = Path(roundedRect: brick.rect, cornerRadius: 4)
            ctx.fill(body, with: .color(color.opacity(bright ? 0.95 : 0.78)))
            if bright {
                ctx.stroke(body, with: .color(.white.opacity(0.7)), lineWidth: 1.4)
            }
        }

        // Power-ups — falling capsules with a letter.
        for pw in game.powerups {
            let r = CGRect(x: pw.pos.x - 14, y: pw.pos.y - 10, width: 28, height: 20)
            let tint: Color = pw.kind == .multiball ? .cyan : .orange
            ctx.fill(Path(roundedRect: r.insetBy(dx: -2, dy: -2), cornerRadius: 11), with: .color(tint.opacity(0.25)))
            ctx.fill(Path(roundedRect: r, cornerRadius: 9), with: .color(tint.opacity(0.85)))
            let letter = pw.kind == .multiball ? "M" : "W"
            ctx.draw(
                Text(letter).font(.system(size: 12, weight: .heavy)).foregroundColor(.black),
                at: pw.pos
            )
        }

        // Paddle — capsule, accent shifts while widened.
        let pw = game.paddleW
        let pRect = CGRect(x: game.paddleX - pw / 2, y: game.paddleY - game.paddleH / 2,
                           width: pw, height: game.paddleH)
        let paddleTint: Color = game.isWide ? .orange : .cyan
        ctx.fill(Path(roundedRect: pRect.insetBy(dx: -3, dy: -3), cornerRadius: 10),
                 with: .color(paddleTint.opacity(0.30)))
        ctx.fill(Path(roundedRect: pRect, cornerRadius: 7), with: .color(.white))

        // Balls — glow ring + white core.
        for ball in game.balls {
            let r = game.ballR
            let outer = CGRect(x: ball.pos.x - r * 2.1, y: ball.pos.y - r * 2.1,
                               width: r * 4.2, height: r * 4.2)
            ctx.fill(Path(ellipseIn: outer), with: .color(.cyan.opacity(0.22)))
            let core = CGRect(x: ball.pos.x - r, y: ball.pos.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: core), with: .color(.white))
        }

        // Particles
        for pt in game.particles {
            let s = 3.5 * pt.life + 1
            let rect = CGRect(x: pt.pos.x - s / 2, y: pt.pos.y - s / 2, width: s, height: s)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 1.2),
                     with: .color(Color(hue: pt.hue, saturation: 0.8, brightness: 1).opacity(pt.life)))
        }

        // Combo badge
        if game.combo >= 3, game.state == .playing {
            ctx.draw(
                Text("×\(game.combo)")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(hue: 0.52, saturation: 0.8, brightness: 1).opacity(0.9)),
                at: CGPoint(x: size.width / 2, y: 30)
            )
        }

        // Level-cleared banner / glued-ball hint
        if game.state == .levelCleared {
            ctx.draw(
                Text(String(format: NSLocalizedString("LEVEL %d", comment: "Glowbreak level banner"), game.level + 1))
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.92)),
                at: CGPoint(x: size.width / 2, y: size.height * 0.45)
            )
        } else if game.state == .ready, game.score > 0 || game.level > 1 || game.lives < 3 {
            ctx.draw(
                Text(NSLocalizedString("TAP TO LAUNCH", comment: "Glowbreak hint"))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55)),
                at: CGPoint(x: size.width / 2, y: size.height * 0.62)
            )
        }
    }

    // MARK: - Overlays (mirrors CoilpedeView)

    private var pauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()

            VStack(spacing: 14) {
                Text("Paused")
                    .font(.title).bold()
                    .foregroundColor(.white)

                VStack(spacing: 10) {
                    pauseAction("Resume", icon: "play.fill", tint: .green) {
                        isPaused = false
                        lastTick = Date()
                    }
                    pauseAction("Restart", icon: "arrow.clockwise", tint: .white) {
                        game.resetAll()
                        isPaused = false
                        lastTick = Date()
                    }
                    pauseAction("Exit", icon: "house.fill", tint: .red) {
                        onExit()
                    }
                }
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(white: 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.15))
                    )
            )
        }
    }

    private func pauseAction(
        _ title: LocalizedStringKey,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            softHaptic.impactOccurred()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 18)
                Text(title)
                    .font(.headline)
                Spacer()
            }
            .foregroundColor(tint)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(width: 200)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(tint.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(tint.opacity(0.35), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var overlayCard: some View {
        VStack(spacing: 14) {
            Text(LocalizedStringKey(game.state == .gameOver ? "Game Over" : "Glowbreak"))
                .font(.largeTitle).bold()
                .foregroundColor(.white)

            if game.state == .gameOver {
                Text("Score: \(game.score)")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.8))
            } else {
                Text("Smash the neon bricks")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
                Text("drag to move · tap to launch")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.45))
            }

            Button {
                haptic.impactOccurred()
                game.startOrLaunch()
            } label: {
                Text(LocalizedStringKey(game.state == .gameOver ? "Play Again" : "Start"))
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(Capsule().fill(Color.cyan))
            }
            .buttonStyle(.plain)

            if game.state == .gameOver, AdManager.shared.rewardedReady {
                Button {
                    AdManager.shared.showRewarded { game.reviveFromAd() }
                } label: {
                    Label(NSLocalizedString("Watch ad · +1 life", comment: "Rewarded revive"),
                          systemImage: "play.tv")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.25)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(30)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.7))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.15)))
        )
    }

    // MARK: - Gamepad

    private func handleGamepadAction(_ action: GamepadAction) {
        switch action {
        case .dpadLeft(let p):  padHeld = p ? -1 : (padHeld == -1 ? 0 : padHeld)
        case .dpadRight(let p): padHeld = p ?  1 : (padHeld ==  1 ? 0 : padHeld)
        case .leftStick(let x, _):
            padHeld = abs(x) > 0.25 ? CGFloat(x) : 0
        case .cross(let p) where p, .start(let p) where p:
            game.startOrLaunch()
        default: break
        }
    }

    // MARK: - Loop

    private func advance(now: Date) {
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        guard !isPaused else { return }
        if padHeld != 0 {
            game.movePaddle(dx: padHeld * 430 * CGFloat(min(dt, 1.0 / 30.0)))
        }
        game.tick(dt: dt)

        // Demo over — natural interstitial moment (fires once per game over).
        if game.state == .gameOver {
            if !gameOverAdFired {
                gameOverAdFired = true
                AdManager.shared.showInterstitialIfEligible(after: 0.8)
            }
        } else if gameOverAdFired {
            gameOverAdFired = false
        }
    }
}
