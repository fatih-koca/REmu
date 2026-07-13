import SwiftUI
import UIKit

// MARK: - Playable SwiftUI view for the Lumo demo
//
// Side-scrolling neon platformer. Same shell as the other built-in demos
// (top strip, pause/ready/game-over overlays, gamepad hooks); the world is
// Canvas-rendered with parallax layers and a camera that follows the spark.

struct LumoView: View {
    @StateObject private var game = LumoGame()
    let onExit: () -> Void

    @State private var lastTick: Date = Date()
    @State private var isPaused = false
    @State private var gameOverAdFired = false
    @State private var leftHeld = false
    @State private var rightHeld = false
    @State private var stickX: CGFloat = 0

    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    private let softHaptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        GeometryReader { geo in
            let inset = geo.safeAreaInsets
            let hPad: CGFloat = 18

            ZStack {
                Color.black
                arenaView

                VStack(spacing: 0) {
                    GameInfoTopStrip(
                        title: "Lumo",
                        subtitle: String(localized: "BUILT-IN"),
                        stats: [
                            (String(localized: "SCORE"), "\(game.score)"),
                            (String(localized: "BEST"),  "\(game.highScore)"),
                            (String(localized: "LVL"),   "\(game.level)/\(game.levelCount)"),
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

                // Touch controls: ‹ › left cluster, JUMP right.
                HStack {
                    HStack(spacing: 14) {
                        holdButton("chevron.left")  { leftHeld  = $0; syncMove() }
                        holdButton("chevron.right") { rightHeld = $0; syncMove() }
                    }
                    Spacer()
                    HapticButton(haptic: .light) { down in
                        if down { game.pressJump() } else { game.releaseJump() }
                    } label: {
                        Text("JUMP")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .tracking(1)
                            .foregroundColor(.white)
                            .frame(width: 76, height: 76)
                            .background(Circle().fill(Color.cyan.opacity(0.22)))
                            .overlay(Circle().stroke(Color.cyan.opacity(0.55), lineWidth: 1.6))
                    }
                }
                .padding(.leading,  inset.leading  + hPad)
                .padding(.trailing, inset.trailing + hPad)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, max(inset.bottom, 4) + 14)

                if (game.state == .ready && game.level == 1 && game.score == 0 && game.lives == 3)
                    || game.state == .gameOver || game.state == .won, !isPaused {
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
        .onChange(of: game.crystalEvents) { _ in softHaptic.impactOccurred() }
        .onChange(of: game.stompEvents)   { _ in haptic.impactOccurred() }
        .onChange(of: game.bounceEvents)  { _ in haptic.impactOccurred(intensity: 0.7) }
        .onChange(of: game.hurtEvents)    { _ in
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

    private func holdButton(_ symbol: String, handler: @escaping (Bool) -> Void) -> some View {
        HapticButton(haptic: .light) { down in
            handler(down)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 62, height: 62)
                .background(Circle().fill(Color.white.opacity(0.10)))
                .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 1.4))
        }
    }

    private func syncMove() {
        let dir: CGFloat = (rightHeld ? 1 : 0) - (leftHeld ? 1 : 0)
        game.setMove(dir != 0 ? dir : stickX)
    }

    // MARK: - Arena

    private var arenaView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.06, blue: 0.22),
                    Color(red: 0.14, green: 0.07, blue: 0.32),
                    Color(red: 0.05, green: 0.03, blue: 0.12),
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
        .ignoresSafeArea()
    }

    // MARK: - Canvas drawing

    private func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let t = game.tile
        let cam = game.camX

        drawBackdrop(&ctx, size: size, cam: cam)

        // Visible tile columns
        let c0 = max(0, Int(cam / t) - 1)
        let c1 = min(game.cols - 1, Int((cam + size.width) / t) + 1)
        guard c1 >= c0 else { return }

        // Tiles
        for r in 0..<game.rows.count {
            for c in c0...c1 {
                let ch = game.tileChar(c, r)
                let x = CGFloat(c) * t - cam
                let y = CGFloat(r) * t
                switch ch {
                case "X":
                    // Bright indigo body + subtle outline so blocks clearly
                    // separate from the dark backdrop.
                    let rect = CGRect(x: x, y: y, width: t + 0.5, height: t + 0.5)
                    ctx.fill(Path(rect), with: .color(Color(red: 0.26, green: 0.20, blue: 0.55)))
                    ctx.fill(Path(CGRect(x: x, y: y + t * 0.55, width: t + 0.5, height: t * 0.45)),
                             with: .color(Color(red: 0.19, green: 0.14, blue: 0.43)))
                    ctx.stroke(Path(rect), with: .color(.white.opacity(0.10)), lineWidth: 1)
                    if game.tileChar(c, r - 1) != "X" {
                        // Exposed top — neon edge
                        let edge = CGRect(x: x, y: y, width: t + 0.5, height: 3.6)
                        let neon: Color = r >= game.rows.count - 2 ? .cyan : Color(hue: 0.73, saturation: 0.65, brightness: 1)
                        ctx.fill(Path(roundedRect: edge, cornerRadius: 1.8), with: .color(neon.opacity(0.95)))
                    }
                case "^":
                    let spike = Path { p in
                        p.move(to: CGPoint(x: x + t * 0.1, y: y + t))
                        p.addLine(to: CGPoint(x: x + t * 0.5, y: y + t * 0.25))
                        p.addLine(to: CGPoint(x: x + t * 0.9, y: y + t))
                        p.closeSubpath()
                    }
                    ctx.fill(spike, with: .color(Color(hue: 0.93, saturation: 0.75, brightness: 1).opacity(0.95)))
                case "b":
                    let pad = CGRect(x: x + t * 0.08, y: y + t * 0.18, width: t * 0.84, height: t * 0.3)
                    ctx.fill(Path(roundedRect: pad.insetBy(dx: -2, dy: -2), cornerRadius: 8), with: .color(.green.opacity(0.25)))
                    ctx.fill(Path(roundedRect: pad, cornerRadius: 6), with: .color(Color(hue: 0.39, saturation: 0.8, brightness: 0.95)))
                    let base = CGRect(x: x, y: y + t * 0.52, width: t, height: t * 0.48)
                    ctx.fill(Path(base), with: .color(Color(red: 0.26, green: 0.20, blue: 0.55)))
                default:
                    break
                }
            }
        }

        // Crystals — pulsing diamonds
        let pulse = 1 + 0.12 * sin(game.time * 5)
        for cr in game.crystals where !cr.taken {
            let p = game.pointFor(CGFloat(cr.col) + 0.5, CGFloat(cr.row) + 0.5)
            guard p.x - cam > -30, p.x - cam < size.width + 30 else { continue }
            let s = t * 0.30 * pulse
            var d = Path()
            d.move(to: CGPoint(x: p.x - cam, y: p.y - s))
            d.addLine(to: CGPoint(x: p.x - cam + s * 0.72, y: p.y))
            d.addLine(to: CGPoint(x: p.x - cam, y: p.y + s))
            d.addLine(to: CGPoint(x: p.x - cam - s * 0.72, y: p.y))
            d.closeSubpath()
            ctx.fill(d, with: .color(Color(hue: 0.52, saturation: 0.65, brightness: 1).opacity(0.95)))
            ctx.stroke(d, with: .color(.white.opacity(0.85)), lineWidth: 1.2)
        }

        // Beacon
        drawBeacon(&ctx, cam: cam, t: t)

        // Enemies — gloom blobs
        for e in game.enemies where e.alive {
            let p = game.pointFor(e.x, e.y)
            let x = p.x - cam
            guard x > -40, x < size.width + 40 else { continue }
            let wob = sin(game.time * 7 + Double(e.x)) * 1.6
            let body = CGRect(x: x - t * 0.4, y: p.y - t * 0.26 + wob, width: t * 0.8, height: t * 0.58)
            ctx.fill(Path(ellipseIn: body.insetBy(dx: -2.5, dy: -2.5)), with: .color(Color(hue: 0.76, saturation: 0.6, brightness: 0.5).opacity(0.5)))
            ctx.fill(Path(ellipseIn: body), with: .color(Color(hue: 0.74, saturation: 0.58, brightness: 0.62)))
            // Eyes + frown
            let eyeY = body.midY - 3
            for dx in [-t * 0.13, t * 0.13] {
                ctx.fill(Path(ellipseIn: CGRect(x: x + dx - 3, y: eyeY - 3, width: 6, height: 6)), with: .color(.white))
                ctx.fill(Path(ellipseIn: CGRect(x: x + dx + (e.dir > 0 ? -1.4 : -2.6), y: eyeY - 1.6, width: 3.2, height: 3.2)), with: .color(Color(red: 0.1, green: 0.06, blue: 0.22)))
            }
        }

        // Particles
        for pt in game.particles {
            let s = 3.2 * pt.life + 1
            let rect = CGRect(x: pt.pos.x - cam - s / 2, y: pt.pos.y - s / 2, width: s, height: s)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 1.2),
                     with: .color(Color(hue: pt.hue, saturation: 0.75, brightness: 1).opacity(pt.life)))
        }

        // Lumo — the spark
        drawPlayer(&ctx, cam: cam, t: t)

        // Banners
        if game.state == .levelCleared {
            let txt = game.level >= game.levelCount
                ? NSLocalizedString("All beacons lit!", comment: "Lumo win banner")
                : String(format: NSLocalizedString("LEVEL %d", comment: ""), game.level + 1)
            ctx.draw(
                Text(txt)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.92)),
                at: CGPoint(x: size.width / 2, y: size.height * 0.4)
            )
        } else if game.state == .ready, !(game.level == 1 && game.score == 0 && game.lives == 3) {
            ctx.draw(
                Text(NSLocalizedString("TAP TO LAUNCH", comment: ""))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55)),
                at: CGPoint(x: size.width / 2, y: size.height * 0.34)
            )
        }
    }

    private func drawBackdrop(_ ctx: inout GraphicsContext, size: CGSize, cam: CGFloat) {
        // Stars (slow parallax)
        let starSeed: [(CGFloat, CGFloat, CGFloat)] = [
            (60, 40, 1.6), (220, 90, 1.2), (390, 50, 1.7), (560, 100, 1.1),
            (700, 45, 1.5), (840, 85, 1.3), (130, 130, 1.0), (480, 140, 1.2),
        ]
        let span: CGFloat = 960
        let sOff = (cam * 0.1).truncatingRemainder(dividingBy: span)
        for rep in 0...1 {
            for (sx, sy, r) in starSeed {
                let x = sx - sOff + CGFloat(rep) * span
                guard x > -5, x < size.width + 5 else { continue }
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: sy, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity(0.55)))
            }
        }

        // Hills (mid parallax)
        let hillSpan: CGFloat = 520
        let hOff = (cam * 0.3).truncatingRemainder(dividingBy: hillSpan)
        let baseY = size.height * 0.72
        var hills = Path()
        var x: CGFloat = -hOff - hillSpan
        while x < size.width + hillSpan {
            hills.move(to: CGPoint(x: x, y: size.height))
            hills.addLine(to: CGPoint(x: x, y: baseY))
            hills.addQuadCurve(to: CGPoint(x: x + hillSpan / 2, y: baseY - 70),
                               control: CGPoint(x: x + hillSpan * 0.22, y: baseY - 78))
            hills.addQuadCurve(to: CGPoint(x: x + hillSpan, y: baseY),
                               control: CGPoint(x: x + hillSpan * 0.78, y: baseY - 78))
            hills.addLine(to: CGPoint(x: x + hillSpan, y: size.height))
            hills.closeSubpath()
            x += hillSpan
        }
        ctx.fill(hills, with: .color(Color(red: 0.17, green: 0.10, blue: 0.40).opacity(0.55)))

        // Retro grid (faster parallax)
        var grid = Path()
        let gSpan: CGFloat = 110
        let gOff = (cam * 0.5).truncatingRemainder(dividingBy: gSpan)
        var gx: CGFloat = -gOff
        while gx < size.width {
            grid.move(to: CGPoint(x: gx, y: baseY + 8))
            grid.addLine(to: CGPoint(x: gx - 14, y: size.height))
            gx += gSpan
        }
        for gy in [baseY + 22, baseY + 48, baseY + 82] {
            grid.move(to: CGPoint(x: 0, y: gy))
            grid.addLine(to: CGPoint(x: size.width, y: gy))
        }
        ctx.stroke(grid, with: .color(Color(hue: 0.73, saturation: 0.7, brightness: 0.9).opacity(0.18)), lineWidth: 1)
    }

    private func drawBeacon(_ ctx: inout GraphicsContext, cam: CGFloat, t: CGFloat) {
        let p = game.pointFor(game.beacon.x, game.beacon.y)
        let x = p.x - cam
        guard x > -80, x < game.field.width + 80 else { return }
        let lit = game.state == .levelCleared || game.state == .won
        let glowR = t * (lit ? 2.6 : 1.3) * (1 + 0.06 * sin(game.time * 4))
        ctx.fill(Path(ellipseIn: CGRect(x: x - glowR, y: p.y - t * 0.7 - glowR, width: glowR * 2, height: glowR * 2)),
                 with: .color(Color(hue: 0.11, saturation: 0.65, brightness: 1).opacity(lit ? 0.4 : 0.18)))
        // Pole
        let pole = CGRect(x: x - t * 0.1, y: p.y - t * 0.55, width: t * 0.2, height: t * 1.0)
        ctx.fill(Path(roundedRect: pole, cornerRadius: 3), with: .color(Color(red: 0.23, green: 0.16, blue: 0.10)))
        // Lamp
        let lamp = CGRect(x: x - t * 0.18, y: p.y - t * 0.88, width: t * 0.36, height: t * 0.36)
        ctx.fill(Path(ellipseIn: lamp), with: .color(Color(hue: 0.12, saturation: lit ? 0.75 : 0.3, brightness: lit ? 1 : 0.55)))
        ctx.stroke(Path(ellipseIn: lamp), with: .color(.white.opacity(0.75)), lineWidth: 1.4)
    }

    private func drawPlayer(_ ctx: inout GraphicsContext, cam: CGFloat, t: CGFloat) {
        // Blink while invulnerable
        if game.invulnerable > 0,
           Int(game.time * 10) % 2 == 0,
           game.state == .playing {
            return
        }
        let p = game.pointFor(game.px, game.py)
        let x = p.x - cam
        let s = t * 0.62

        // Glow
        let glowR = s * 1.6
        ctx.fill(Path(ellipseIn: CGRect(x: x - glowR, y: p.y - glowR, width: glowR * 2, height: glowR * 2)),
                 with: .color(.cyan.opacity(0.20)))

        // Body
        let body = CGRect(x: x - s / 2, y: p.y - s / 2, width: s, height: s)
        ctx.fill(Path(roundedRect: body, cornerRadius: s * 0.34), with: .color(Color(red: 0.68, green: 0.96, blue: 1.0)))
        ctx.stroke(Path(roundedRect: body, cornerRadius: s * 0.34), with: .color(.white.opacity(0.9)), lineWidth: 1.4)

        // Face (eyes lead in the facing direction)
        let look = game.facing * s * 0.07
        for dx in [-s * 0.17, s * 0.17] {
            ctx.fill(Path(ellipseIn: CGRect(x: x + dx + look - 2.2, y: p.y - s * 0.1 - 2.2, width: 4.4, height: 4.4)),
                     with: .color(Color(red: 0.04, green: 0.15, blue: 0.25)))
        }
        var smile = Path()
        smile.move(to: CGPoint(x: x - s * 0.14 + look, y: p.y + s * 0.18))
        smile.addQuadCurve(to: CGPoint(x: x + s * 0.16 + look, y: p.y + s * 0.16),
                           control: CGPoint(x: x + look, y: p.y + s * 0.3))
        ctx.stroke(smile, with: .color(Color(red: 0.04, green: 0.15, blue: 0.25)), lineWidth: 1.6)

        // Antenna
        var ant = Path()
        ant.move(to: CGPoint(x: x, y: p.y - s / 2))
        ant.addQuadCurve(to: CGPoint(x: x + game.facing * 4, y: p.y - s / 2 - s * 0.42),
                         control: CGPoint(x: x - game.facing * 2, y: p.y - s / 2 - s * 0.25))
        ctx.stroke(ant, with: .color(Color(red: 0.68, green: 0.96, blue: 1.0)), lineWidth: 2.2)
        ctx.fill(Path(ellipseIn: CGRect(x: x + game.facing * 4 - 3, y: p.y - s / 2 - s * 0.42 - 3, width: 6, height: 6)),
                 with: .color(Color(hue: 0.13, saturation: 0.7, brightness: 1)))
    }

    // MARK: - Overlays

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
            Text(overlayTitle)
                .font(.largeTitle).bold()
                .foregroundColor(.white)

            if game.state == .gameOver || game.state == .won {
                Text("Score: \(game.score)")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.8))
            } else {
                Text("Light the beacons")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            }

            Button {
                haptic.impactOccurred()
                game.startOrLaunch()
            } label: {
                Text(LocalizedStringKey(game.state == .ready ? "Start" : "Play Again"))
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

    private var overlayTitle: LocalizedStringKey {
        switch game.state {
        case .won:      return "All beacons lit!"
        case .gameOver: return "Game Over"
        default:        return "Lumo"
        }
    }

    // MARK: - Gamepad

    private func handleGamepadAction(_ action: GamepadAction) {
        switch action {
        case .dpadLeft(let p):  leftHeld = p;  syncMove()
        case .dpadRight(let p): rightHeld = p; syncMove()
        case .leftStick(let x, _):
            stickX = abs(x) > 0.25 ? CGFloat(x) : 0
            syncMove()
        case .cross(let p):
            if p { game.pressJump() } else { game.releaseJump() }
        case .start(let p) where p:
            game.startOrLaunch()
        default: break
        }
    }

    // MARK: - Loop

    private func advance(now: Date) {
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        guard !isPaused else { return }
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
