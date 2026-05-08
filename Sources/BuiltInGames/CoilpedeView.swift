import SwiftUI
import UIKit

// MARK: - Playable SwiftUI view for the Coilpede demo

struct CoilpedeView: View {
    @StateObject private var game = CoilpedeGame()
    let onExit: () -> Void

    @State private var lastTick: Date = Date()
    @State private var isPaused: Bool = false
    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    private let softHaptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        GeometryReader { geo in
            // GeometryReader sits at the very root and DOES respect safe
            // area — so geo.safeAreaInsets reports real values (e.g. ~59pt
            // for the Dynamic Island side in landscape). We then expand
            // the inner ZStack to ignore safe area for the full-bleed
            // black + arena, and apply explicit padding to the overlays
            // for guaranteed Dynamic Island + rounded-corner clearance.
            let inset = geo.safeAreaInsets
            // hPad sits ON TOP of the system safe area. 18pt = compact
            // corner clearance, controls stay close to the edge.
            let hPad: CGFloat = 18

            ZStack {
                Color.black
                arenaView

                // Top strip only — bottom ad strip removed for now.
                VStack(spacing: 0) {
                    GameInfoTopStrip(
                        title: "Glowchase",
                        subtitle: "BUILT-IN",
                        stats: [
                            ("SCORE", "\(game.score)"),
                            ("BEST",  "\(game.highScore)"),
                        ],
                        onPause: {
                            softHaptic.impactOccurred()
                            isPaused = true
                        }
                    )
                    Spacer(minLength: 0)
                }
                // Hug the corners harder than the controls overlay — the
                // top strip only needs Dynamic Island clearance, not the
                // 18pt cushion the dpad uses.
                .padding(.leading,  inset.leading  + 4)
                .padding(.trailing, inset.trailing + 4)
                .padding(.top,      max(inset.top,    4))
                .padding(.bottom,   max(inset.bottom, 4))

                // Left + Right control overlays
                HStack(spacing: 0) {
                    coilpedeLeftColumn
                    Spacer(minLength: 0)
                    coilpedeRightColumn
                }
                .padding(.leading,  inset.leading  + hPad)
                .padding(.trailing, inset.trailing + hPad)
                .padding(.top,      max(inset.top,    4) + 56) // clear top strip
                .padding(.bottom,   max(inset.bottom, 4) + 40) // clear AD strip

                // Start / Game Over overlay
                if game.state != .playing && !isPaused {
                    overlayCard
                }

                // Pause overlay
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
        .background(
            // Timeline drives the game loop without a CADisplayLink
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                Color.clear
                    .onChange(of: context.date) { _ in
                        advanceIfNeeded(now: context.date)
                    }
            }
        )
    }

    // MARK: - Arena

    private var arenaView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.12, blue: 0.06),
                    Color(red: 0.04, green: 0.06, blue: 0.03),
                ],
                startPoint: .top, endPoint: .bottom
            )

            GeometryReader { proxy in
                let arena = arenaRect(in: proxy.size)
                let cell = min(
                    arena.width  / CGFloat(game.cols),
                    arena.height / CGFloat(game.rows)
                )

                ZStack {
                    arenaBackground(rect: arena, cell: cell)
                    leafShape(rect: arena, cell: cell)
                    creatureShape(rect: arena, cell: cell)
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(swipeGesture)
    }

    private func arenaRect(in size: CGSize) -> CGRect {
        // The arena now lives inside the middle column of the shell, so we
        // only need a small inner margin. Aspect ratio keeps the play field
        // centered both horizontally and vertically.
        let margin: CGFloat = 10
        let w = size.width - margin * 2
        let h = size.height - margin * 2
        let ratio = CGFloat(game.cols) / CGFloat(game.rows)
        var finalW = w
        var finalH = w / ratio
        if finalH > h {
            finalH = h
            finalW = h * ratio
        }
        return CGRect(
            x: (size.width - finalW) / 2,
            y: (size.height - finalH) / 2,
            width: finalW, height: finalH
        )
    }

    // MARK: - Drawing

    private func arenaBackground(rect: CGRect, cell: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.22, blue: 0.12),
                            Color(red: 0.12, green: 0.16, blue: 0.08),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                )

            // Subtle grid dots
            Canvas { ctx, _ in
                for x in stride(from: 0, to: game.cols, by: 2) {
                    for y in stride(from: 0, to: game.rows, by: 2) {
                        let p = CGPoint(
                            x: rect.minX + (CGFloat(x) + 0.5) * cell,
                            y: rect.minY + (CGFloat(y) + 0.5) * cell
                        )
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2)),
                            with: .color(Color.white.opacity(0.04))
                        )
                    }
                }
            }
        }
    }

    private func leafShape(rect: CGRect, cell: CGFloat) -> some View {
        let p = CGPoint(
            x: rect.minX + (CGFloat(game.leaf.x) + 0.5) * cell,
            y: rect.minY + (CGFloat(game.leaf.y) + 0.5) * cell
        )
        let size = cell * 0.82
        return ZStack {
            Circle()
                .fill(Color.orange.opacity(0.5))
                .blur(radius: 6)
                .frame(width: size * 1.5, height: size * 1.5)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.yellow, .orange, .red],
                        center: .center, startRadius: 0, endRadius: size / 2
                    )
                )
                .frame(width: size, height: size)
        }
        .position(p)
    }

    private func creatureShape(rect: CGRect, cell: CGFloat) -> some View {
        Canvas { ctx, _ in
            guard !game.segments.isEmpty else { return }

            let legPhase = Double(game.tickCount) * 0.6
            let segSize = cell * 0.78

            // Draw tail → head so head layers on top
            for (index, seg) in game.segments.enumerated().reversed() {
                let p = CGPoint(
                    x: rect.minX + (CGFloat(seg.x) + 0.5) * cell,
                    y: rect.minY + (CGFloat(seg.y) + 0.5) * cell
                )

                // Segmentler için renk gradient (baş daha koyu)
                let t = Double(index) / max(1, Double(game.segments.count - 1))
                let bodyColor = Color(
                    red:   0.28 - t * 0.10,
                    green: 0.64 - t * 0.16,
                    blue:  0.28 - t * 0.08
                )

                // Legs (alternating up/down)
                if index > 0 {
                    let phase = sin(legPhase + Double(index) * 0.8)
                    let dx = CGFloat(phase) * segSize * 0.35
                    let dy: CGFloat = 0
                    drawLeg(ctx: &ctx, from: p, offsetA: CGSize(width:  segSize * 0.45 + dx * 0.2, height: dy - segSize * 0.45))
                    drawLeg(ctx: &ctx, from: p, offsetA: CGSize(width: -segSize * 0.45 - dx * 0.2, height: dy - segSize * 0.45))
                    drawLeg(ctx: &ctx, from: p, offsetA: CGSize(width:  segSize * 0.45 + dx * 0.2, height: dy + segSize * 0.45))
                    drawLeg(ctx: &ctx, from: p, offsetA: CGSize(width: -segSize * 0.45 - dx * 0.2, height: dy + segSize * 0.45))
                }

                // Body segment
                let rect = CGRect(
                    x: p.x - segSize / 2, y: p.y - segSize / 2,
                    width: segSize, height: segSize
                )
                ctx.fill(
                    Path(roundedRect: rect, cornerRadius: segSize * 0.35),
                    with: .color(bodyColor)
                )

                // Subtle rim highlight
                ctx.stroke(
                    Path(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: segSize * 0.35),
                    with: .color(Color.white.opacity(0.1)),
                    lineWidth: 1
                )

                // Eyes on head
                if index == 0 {
                    drawEyes(ctx: &ctx, at: p, segSize: segSize)
                }
            }
        }
    }

    private func drawLeg(ctx: inout GraphicsContext, from: CGPoint, offsetA: CGSize) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: CGPoint(x: from.x + offsetA.width, y: from.y + offsetA.height))
        ctx.stroke(path, with: .color(Color(red: 0.16, green: 0.36, blue: 0.16)), lineWidth: 2)
    }

    private func drawEyes(ctx: inout GraphicsContext, at center: CGPoint, segSize: CGFloat) {
        let dir = game.direction.vector
        let offset = CGSize(width: CGFloat(dir.x) * segSize * 0.18, height: CGFloat(dir.y) * segSize * 0.18)
        let perp = CGSize(width: CGFloat(dir.y) * segSize * 0.2,  height: CGFloat(dir.x) * segSize * 0.2)

        let eyeL = CGPoint(x: center.x + offset.width + perp.width, y: center.y + offset.height + perp.height)
        let eyeR = CGPoint(x: center.x + offset.width - perp.width, y: center.y + offset.height - perp.height)
        let eyeSize = segSize * 0.22

        for e in [eyeL, eyeR] {
            ctx.fill(
                Path(ellipseIn: CGRect(x: e.x - eyeSize/2, y: e.y - eyeSize/2, width: eyeSize, height: eyeSize)),
                with: .color(.white)
            )
            ctx.fill(
                Path(ellipseIn: CGRect(x: e.x - eyeSize/4, y: e.y - eyeSize/4, width: eyeSize/2, height: eyeSize/2)),
                with: .color(.black)
            )
        }
    }

    // MARK: - Left / Right Columns
    //
    // Left column (top → bottom): Pause button at top, D-Pad in the middle.
    // Right column: just a subtle hint label so the shell stays symmetric
    // with the real emulator screen.

    private var coilpedeLeftColumn: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 8)

            dpadView

            Spacer(minLength: 8)
        }
        .padding(.top, 10)
        .padding(.bottom, 16)        // lower dpad further toward bottom edge
        .frame(maxHeight: .infinity)
        .frame(width: 110)
        .offset(x: -10, y: 30)        // sink dpad lower than before
    }

    private var coilpedeRightColumn: some View {
        VStack {
            Spacer()
            Text("Swipe\nor\nD-Pad")
                .multilineTextAlignment(.center)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.35))
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.35))
                )
            Spacer()
        }
        .frame(maxHeight: .infinity)
        .frame(width: 64)
        .offset(x: 28)                 // push hint label closer to right edge
    }

    private var dpadView: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 18, height: 18)

            dpadArrow(.up)    .offset(y: -41)
            dpadArrow(.down)  .offset(y:  41)
            dpadArrow(.left)  .offset(x: -41)
            dpadArrow(.right) .offset(x:  41)
        }
        .frame(width: 119, height: 119)   // 10% smaller than 132pt
    }

    private func dpadArrow(_ dir: CoilpedeDirection) -> some View {
        Button {
            softHaptic.impactOccurred()
            game.queueDirection(dir)
        } label: {
            Image(systemName: arrowSystem(dir))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.14)))
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func arrowSystem(_ dir: CoilpedeDirection) -> String {
        switch dir {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        }
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
                    pauseAction("Resume", icon: "play.fill", tint: .orange) {
                        isPaused = false
                        lastTick = Date()
                    }
                    pauseAction("Restart", icon: "arrow.clockwise", tint: .white) {
                        game.reset()  // wipe segments, score, etc.
                        game.start()  // .ready → .playing
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
        _ title: String,
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
            Text(game.state == .gameOver ? "Game Over" : "Glowchase")
                .font(.largeTitle).bold()
                .foregroundColor(.white)

            if game.state == .gameOver {
                Text("Score: \(game.score)")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.8))
            } else {
                Text("Guide the coil — chase the glow")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            }

            Button {
                haptic.impactOccurred()
                game.start()
            } label: {
                Text(game.state == .gameOver ? "Play Again" : "Start")
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(Capsule().fill(Color.orange))
            }
            .buttonStyle(.plain)
        }
        .padding(30)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.7))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.15)))
        )
    }

    // MARK: - Input

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                if abs(dx) > abs(dy) {
                    game.queueDirection(dx > 0 ? .right : .left)
                } else {
                    game.queueDirection(dy > 0 ? .down : .up)
                }
                softHaptic.impactOccurred()
            }
    }

    private func handleGamepadAction(_ action: GamepadAction) {
        switch action {
        case .dpadUp(let p)    where p: game.queueDirection(.up)
        case .dpadDown(let p)  where p: game.queueDirection(.down)
        case .dpadLeft(let p)  where p: game.queueDirection(.left)
        case .dpadRight(let p) where p: game.queueDirection(.right)
        case .leftStick(let x, let y):
            if abs(x) > 0.5 || abs(y) > 0.5 {
                if abs(x) > abs(y) { game.queueDirection(x > 0 ? .right : .left) }
                else               { game.queueDirection(y > 0 ? .down  : .up)   }
            }
        case .cross(let p) where p:
            game.start()
        default: break
        }
    }

    // MARK: - Loop

    private func advanceIfNeeded(now: Date) {
        guard game.state == .playing, !isPaused else { return }
        if now.timeIntervalSince(lastTick) >= game.currentTickInterval {
            let oldLen = game.segments.count
            game.tick()
            if game.segments.count > oldLen {
                haptic.impactOccurred()
            } else if game.state == .gameOver {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
            lastTick = now
        }
    }
}
