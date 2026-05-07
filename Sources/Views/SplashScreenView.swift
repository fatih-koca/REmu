import SwiftUI

// MARK: - Splash Screen
//
// Plays once on app launch. Modern-retro vibe: synthwave gradient logo
// in the centre, a flock of small retro-game glyphs (Space Invader,
// Pac-Man ghost, mushroom, joystick…) drifting back and forth around
// the edges, then auto-dismisses with a fade.

struct SplashScreenView: View {
    let onFinish: () -> Void

    @State private var sprites = SplashSprite.deck
    @State private var logoScale: CGFloat = 0.7
    @State private var logoOpacity: Double = 0
    @State private var taglineOpacity: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background

                // Floating retro glyphs around the edges
                ForEach(sprites.indices, id: \.self) { i in
                    FloatingSprite(sprite: sprites[i], canvas: geo.size)
                }

                // Centre logo
                VStack(spacing: 10) {
                    Text("REmu")
                        .font(.system(size: 76, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.55, green: 0.95, blue: 1.00),
                                    Color(red: 0.85, green: 0.55, blue: 1.00),
                                    Color(red: 1.00, green: 0.45, blue: 0.75),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color(red: 0.4, green: 0.9, blue: 1.0).opacity(0.55),
                                radius: 16, x: 0, y: 0)
                        .shadow(color: Color(red: 1.0, green: 0.4, blue: 0.8).opacity(0.4),
                                radius: 28, x: 0, y: 0)
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)

                    Text("R E T R O   E M U L A T O R")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .tracking(4)
                        .foregroundColor(.white.opacity(0.55))
                        .opacity(taglineOpacity)
                }

                // Subtle scanline overlay — sells the retro feel without
                // overpowering the gradient logo.
                scanlines
                    .allowsHitTesting(false)
            }
        }
        .onAppear { animateIn() }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.02, blue: 0.16),
                    Color(red: 0.02, green: 0.02, blue: 0.06),
                    Color.black,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Soft neon glow blobs anchored to the corners.
            RadialGradient(
                colors: [Color(red: 0.35, green: 0.20, blue: 0.65).opacity(0.45),
                         .clear],
                center: .topLeading,
                startRadius: 0, endRadius: 420
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color(red: 0.95, green: 0.30, blue: 0.55).opacity(0.30),
                         .clear],
                center: .bottomTrailing,
                startRadius: 0, endRadius: 460
            )
            .ignoresSafeArea()
        }
    }

    private var scanlines: some View {
        Canvas { ctx, size in
            let line = CGFloat(2)
            let gap = CGFloat(3)
            var y = CGFloat(0)
            while y < size.height {
                ctx.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: line)),
                    with: .color(.white.opacity(0.018))
                )
                y += line + gap
            }
        }
        .blendMode(.plusLighter)
    }

    // MARK: - Animation

    private func animateIn() {
        withAnimation(.spring(response: 0.7, dampingFraction: 0.62)) {
            logoScale = 1.0
            logoOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.6).delay(0.35)) {
            taglineOpacity = 1.0
        }
        // Kick the sprites: each starts its own infinite drift on appear.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.7) {
            onFinish()
        }
    }
}

// MARK: - Sprite definitions

private struct SplashSprite {
    let glyph: String
    let start: CGPoint     // normalised 0…1
    let end: CGPoint
    let size: CGFloat
    let rotationStart: Double
    let rotationEnd: Double
    let duration: Double
    let delay: Double
    let opacity: Double

    /// Hand-placed deck — characters cluster at the edges so the centre
    /// stays clean for the logo. Coordinates avoid the middle ~40% band.
    static let deck: [SplashSprite] = [
        // Top row
        .init(glyph: "👾", start: .init(x: 0.06, y: 0.12), end: .init(x: 0.13, y: 0.18),
              size: 36, rotationStart: -8, rotationEnd: 8,  duration: 3.4, delay: 0.0,  opacity: 0.85),
        .init(glyph: "🕹️", start: .init(x: 0.92, y: 0.10), end: .init(x: 0.86, y: 0.16),
              size: 34, rotationStart: 12, rotationEnd: -6, duration: 3.0, delay: 0.4,  opacity: 0.75),
        .init(glyph: "🪙", start: .init(x: 0.30, y: 0.08), end: .init(x: 0.34, y: 0.13),
              size: 26, rotationStart: -15, rotationEnd: 15, duration: 2.6, delay: 0.2,  opacity: 0.8),
        .init(glyph: "⭐",  start: .init(x: 0.70, y: 0.06), end: .init(x: 0.66, y: 0.12),
              size: 24, rotationStart: 0, rotationEnd: 25,  duration: 2.4, delay: 0.55, opacity: 0.85),

        // Middle band (only at far edges so it doesn't crash into the logo)
        .init(glyph: "🍄", start: .init(x: 0.04, y: 0.46), end: .init(x: 0.10, y: 0.54),
              size: 32, rotationStart: -6, rotationEnd: 10,  duration: 3.2, delay: 0.1,  opacity: 0.85),
        .init(glyph: "🎮", start: .init(x: 0.95, y: 0.50), end: .init(x: 0.89, y: 0.42),
              size: 30, rotationStart: 8, rotationEnd: -10,  duration: 3.6, delay: 0.6,  opacity: 0.8),
        .init(glyph: "💎", start: .init(x: 0.93, y: 0.78), end: .init(x: 0.87, y: 0.84),
              size: 24, rotationStart: -12, rotationEnd: 6,  duration: 2.8, delay: 0.25, opacity: 0.8),
        .init(glyph: "❤️", start: .init(x: 0.07, y: 0.82), end: .init(x: 0.13, y: 0.76),
              size: 22, rotationStart: 0, rotationEnd: 18,   duration: 2.2, delay: 0.5,  opacity: 0.75),

        // Bottom row
        .init(glyph: "👻", start: .init(x: 0.32, y: 0.90), end: .init(x: 0.28, y: 0.84),
              size: 32, rotationStart: 6, rotationEnd: -8,   duration: 3.0, delay: 0.3,  opacity: 0.8),
        .init(glyph: "🚀", start: .init(x: 0.68, y: 0.88), end: .init(x: 0.74, y: 0.82),
              size: 28, rotationStart: -20, rotationEnd: -5, duration: 3.2, delay: 0.0,  opacity: 0.78),
        .init(glyph: "🔑", start: .init(x: 0.18, y: 0.30), end: .init(x: 0.13, y: 0.36),
              size: 22, rotationStart: 5, rotationEnd: -25,  duration: 2.6, delay: 0.7,  opacity: 0.7),
        .init(glyph: "🏆", start: .init(x: 0.84, y: 0.30), end: .init(x: 0.90, y: 0.36),
              size: 24, rotationStart: -8, rotationEnd: 10,  duration: 2.9, delay: 0.45, opacity: 0.75),
    ]
}

// MARK: - Floating sprite view

private struct FloatingSprite: View {
    let sprite: SplashSprite
    let canvas: CGSize

    @State private var animate = false

    var body: some View {
        let pos = animate ? sprite.end : sprite.start
        let rot = animate ? sprite.rotationEnd : sprite.rotationStart

        Text(sprite.glyph)
            .font(.system(size: sprite.size))
            .opacity(sprite.opacity)
            .rotationEffect(.degrees(rot))
            .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
            .position(x: pos.x * canvas.width, y: pos.y * canvas.height)
            .animation(
                .easeInOut(duration: sprite.duration)
                    .repeatForever(autoreverses: true)
                    .delay(sprite.delay),
                value: animate
            )
            .onAppear {
                // Stagger the start so the swarm doesn't move in lockstep.
                DispatchQueue.main.asyncAfter(deadline: .now() + sprite.delay) {
                    animate = true
                }
            }
    }
}
