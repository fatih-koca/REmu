import SwiftUI
import UIKit

// MARK: - Button Identifiers

enum GamepadAction: Equatable {
    // Face buttons
    case cross(Bool), circle(Bool), square(Bool), triangle(Bool)
    // Shoulder
    case l1(Bool), l2(Bool), r1(Bool), r2(Bool)
    // D-Pad
    case dpadUp(Bool), dpadDown(Bool), dpadLeft(Bool), dpadRight(Bool)
    // Analog (normalized -1...1)
    case leftStick(x: Float, y: Float)
    case rightStick(x: Float, y: Float)
    // Meta
    case start(Bool), select(Bool), menu(Bool)
}

// MARK: - Layout Preferences
//
// Each control column publishes its true visual footprint (column frame +
// any subview that protrudes past the frame, like the analog stick when it's
// offset toward screen center). EmulatorScreenView reads these and feeds
// them to the Metal renderer so the game canvas never sneaks underneath the
// thumbsticks. Required because percentage-based offsets blow up on iPad
// otherwise.

struct LeftColumnVisualWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct RightColumnVisualWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Left Control Column
//
// Vertical strip on the LEFT edge in landscape (the user's left thumb).
// Pause button now lives on the top info strip — this column is purely
// gameplay controls so L1/L2 align with R1/R2 on the right column.
// Layout (top → bottom):
//   [L2]
//   [L1]
//   [Analog]   ← pulled toward screen center for thumb comfort
//   [D-Pad]    ← lifted upward off the bottom edge

struct LeftControlColumn: View {
    let screenSize: CGSize
    let onAction: (GamepadAction) -> Void

    var body: some View {
        // Modest inward shift so the analog stick clears the column rail but
        // doesn't drift toward the screen center. PreferenceKey publishes the
        // resulting visual extent so the renderer letterboxes around it.
        let centerPull = min(screenSize.width * 0.08, 70)
        // No vertical drop on the analog stick; D-pad lifts off the bottom
        // padding only enough for thumb reach. Together this keeps a clean
        // vertical gap between the two so they never visually overlap.
        let bottomLift = min(screenSize.height * 0.12, 60)

        let columnW: CGFloat = 106
        let analogProtrusion = max(0, centerPull + 78/2 - columnW/2)
        let visualWidth = columnW + analogProtrusion

        VStack(spacing: 14) {
            CompactShoulder(label: "L2", color: .purple) { onAction(.l2($0)) }
            CompactShoulder(label: "L1", color: .indigo) { onAction(.l1($0)) }

            Spacer(minLength: 8)

            CompactAnalogStick { x, y in onAction(.leftStick(x: x, y: y)) }
                .frame(width: 78, height: 78)
                .offset(x: centerPull, y: 0)

            Spacer(minLength: 8)

            CompactDPad(onAction: onAction)
                .frame(width: 92, height: 92)
                .scaleEffect(1.10)
                .offset(y: -bottomLift)
        }
        .padding(.top, 10)
        .padding(.bottom, 56)
        .frame(maxHeight: .infinity)
        .frame(width: columnW)
        .preference(key: LeftColumnVisualWidthKey.self, value: visualWidth)
    }
}

// MARK: - Right Control Column
//
// Vertical strip on the RIGHT edge in landscape (the user's right thumb).
// Layout (top → bottom):
//   [R2]
//   [R1]
//   [Analog]
//   [Face Buttons (× □ △ ○)]

struct RightControlColumn: View {
    let screenSize: CGSize
    let onAction: (GamepadAction) -> Void

    var body: some View {
        let centerPull = min(screenSize.width * 0.08, 70)
        let bottomLift = min(screenSize.height * 0.12, 60)

        let columnW: CGFloat = 110
        let analogProtrusion = max(0, centerPull + 78/2 - columnW/2)
        let visualWidth = columnW + analogProtrusion

        VStack(spacing: 14) {
            CompactShoulder(label: "R2", color: .purple) { onAction(.r2($0)) }
            CompactShoulder(label: "R1", color: .indigo) { onAction(.r1($0)) }

            Spacer(minLength: 8)

            CompactAnalogStick { x, y in onAction(.rightStick(x: x, y: y)) }
                .frame(width: 78, height: 78)
                .offset(x: -centerPull, y: 0)

            Spacer(minLength: 8)

            CompactFaceCluster(onAction: onAction)
                .frame(width: 102, height: 102)
                .offset(y: -bottomLift)
        }
        .padding(.top, 10)
        .padding(.bottom, 56)
        .frame(maxHeight: .infinity)
        .frame(width: columnW)
        .preference(key: RightColumnVisualWidthKey.self, value: visualWidth)
    }
}

// MARK: - Compact D-Pad
//
// Single 92×92 hit area driven by one DragGesture. The visible cross is
// purely cosmetic; finger position relative to the center decides which
// direction(s) to fire. A small deadzone around each axis lets the user
// trigger pure horizontal/vertical presses without inadvertent diagonals,
// while finger landings outside the deadzone fire BOTH neighbors so SNES
// diagonals (run + jump) feel natural. Sliding the thumb between
// directions correctly releases the old direction and presses the new
// one — the previous per-button gestures dropped these transitions.

private struct CompactDPad: View {
    let onAction: (GamepadAction) -> Void

    private static let size: CGFloat = 92
    private static let deadzone: CGFloat = 7

    @State private var pressed = DirSet()

    var body: some View {
        ZStack {
            // Cross-shaped frame
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.white.opacity(0.10))
                .frame(width: Self.size, height: 32)
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.white.opacity(0.10))
                .frame(width: 32, height: Self.size)
            // Center dot
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 20, height: 20)

            // Decorative chevrons — no longer hit targets, the gesture below
            // owns the entire square.
            VStack(spacing: 0) {
                chevron("chevron.up")
                Spacer().frame(height: 32)
                chevron("chevron.down")
            }
            HStack(spacing: 0) {
                chevron("chevron.left")
                Spacer().frame(width: 32)
                chevron("chevron.right")
            }
        }
        .frame(width: Self.size, height: Self.size)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in update(at: value.location) }
                .onEnded   { _ in releaseAll() }
        )
    }

    private func chevron(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.white.opacity(0.85))
            .frame(width: 32, height: 32)
            .allowsHitTesting(false)
    }

    private func update(at point: CGPoint) {
        let center = Self.size / 2
        let dx = point.x - center
        let dy = point.y - center
        let dz = Self.deadzone

        var next = DirSet()
        next.up    = dy < -dz
        next.down  = dy >  dz
        next.left  = dx < -dz
        next.right = dx >  dz

        if next.up    != pressed.up    { onAction(.dpadUp(next.up));       haptic() }
        if next.down  != pressed.down  { onAction(.dpadDown(next.down));   haptic() }
        if next.left  != pressed.left  { onAction(.dpadLeft(next.left));   haptic() }
        if next.right != pressed.right { onAction(.dpadRight(next.right)); haptic() }
        pressed = next
    }

    private func releaseAll() {
        if pressed.up    { onAction(.dpadUp(false))    }
        if pressed.down  { onAction(.dpadDown(false))  }
        if pressed.left  { onAction(.dpadLeft(false))  }
        if pressed.right { onAction(.dpadRight(false)) }
        pressed = DirSet()
    }

    private func haptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private struct DirSet: Equatable {
        var up = false, down = false, left = false, right = false
    }
}

// MARK: - Compact Face Button Cluster (× □ △ ○)

private struct CompactFaceCluster: View {
    let onAction: (GamepadAction) -> Void

    var body: some View {
        ZStack {
            faceBtn("△", color: .green, offset: CGSize(width: 0, height: -36)) {
                onAction(.triangle($0))
            }
            faceBtn("✕", color: .blue,  offset: CGSize(width: 0, height:  36)) {
                onAction(.cross($0))
            }
            faceBtn("□", color: .pink,  offset: CGSize(width: -36, height: 0)) {
                onAction(.square($0))
            }
            faceBtn("○", color: .red,   offset: CGSize(width:  36, height: 0)) {
                onAction(.circle($0))
            }
        }
    }

    private func faceBtn(
        _ label: String,
        color: Color,
        offset: CGSize,
        handler: @escaping (Bool) -> Void
    ) -> some View {
        HapticButton(haptic: .medium) { handler($0) } label: {
            ZStack {
                Circle()
                    .fill(color.opacity(0.22))
                    .overlay(Circle().stroke(color.opacity(0.55), lineWidth: 1.4))
                    .frame(width: 40, height: 40)
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(color)
            }
            // Visual stays at 40pt but the hit target grows into the dead
            // space between buttons. Each button keeps its own gesture so
            // multi-button combos (X+△ etc.) still register as
            // simultaneous presses.
            .frame(width: 56, height: 56)
            .contentShape(Rectangle())
        }
        .offset(offset)
    }
}

// MARK: - Compact Analog Stick

private struct CompactAnalogStick: View {
    let onChange: (Float, Float) -> Void

    @State private var thumbOffset: CGSize = .zero
    private let radius: CGFloat = 32
    private let baseSize: CGFloat = 78
    private let thumbSize: CGFloat = 40

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1.2))
                .frame(width: baseSize, height: baseSize)

            Circle()
                .fill(Color.white.opacity(0.28))
                .frame(width: thumbSize, height: thumbSize)
                .offset(thumbOffset)
                .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let clamped = clampToCircle(value.translation, maxRadius: radius)
                    thumbOffset = clamped
                    onChange(
                        Float(clamped.width / radius),
                        Float(clamped.height / radius)
                    )
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.2)) { thumbOffset = .zero }
                    onChange(0, 0)
                }
        )
    }

    private func clampToCircle(_ offset: CGSize, maxRadius: CGFloat) -> CGSize {
        let dist = sqrt(offset.width * offset.width + offset.height * offset.height)
        guard dist > maxRadius else { return offset }
        let scale = maxRadius / dist
        return CGSize(width: offset.width * scale, height: offset.height * scale)
    }
}

// MARK: - Compact Shoulder Button (trapezoid feel via slanted gradient)

private struct CompactShoulder: View {
    let label: String
    let color: Color
    let handler: (Bool) -> Void

    var body: some View {
        HapticButton(haptic: .medium) { handler($0) } label: {
            Text(label)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .frame(width: 58, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.25), color.opacity(0.10)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(color.opacity(0.5), lineWidth: 1.2)
                        )
                )
        }
    }
}

// MARK: - Start / Select Bar
//
// Two pill buttons at the bottom-center of the in-game screen. Sized small
// and washed-down so they don't compete with the face buttons / D-pad for
// thumb attention, but live in the natural resting zone between the two
// control columns where SNES intro-skip and pause flows are reachable in
// one motion.

struct StartSelectBar: View {
    let onAction: (GamepadAction) -> Void
    /// Hold-to-fast-forward: true on press, false on release. Wired by the
    /// emulator screen to the core's frame multiplier.
    var onFastForward: (Bool) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 14) {
            metaButton(label: "SELECT", tint: Color.orange) { onAction(.select($0)) }
            metaButton(label: "START",  tint: Color.green)  { onAction(.start($0)) }
            metaButton(label: "FF ▶▶",  tint: Color.blue)   { onFastForward($0) }
        }
    }

    private func metaButton(
        label: String,
        tint: Color,
        handler: @escaping (Bool) -> Void
    ) -> some View {
        HapticButton(haptic: .light) { handler($0) } label: {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.0)
                .foregroundColor(Color.white.opacity(0.9))
                .frame(width: 64, height: 26)
                .background(
                    Capsule()
                        .fill(tint.opacity(0.45))
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1)
                        )
                )
        }
    }
}

// MARK: - Pause Button

struct PauseButton: View {
    let onPause: () -> Void

    var body: some View {
        HapticButton(haptic: .light) { isDown in
            if isDown { onPause() }
        } label: {
            Image(systemName: "pause.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 42, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.white.opacity(0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.white.opacity(0.28), lineWidth: 1)
                        )
                )
        }
    }
}

// MARK: - Haptic Button (press + release tracking)

struct HapticButton<Label: View>: View {
    let haptic: UIImpactFeedbackGenerator.FeedbackStyle
    let handler: (Bool) -> Void
    @ViewBuilder let label: () -> Label
    @State private var isPressed = false

    var body: some View {
        label()
            .scaleEffect(isPressed ? 0.88 : 1.0)
            .animation(.easeInOut(duration: 0.08), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            handler(true)
                            UIImpactFeedbackGenerator(style: haptic).impactOccurred()
                        }
                    }
                    .onEnded { _ in
                        if isPressed {
                            isPressed = false
                            handler(false)
                        }
                    }
            )
    }
}
