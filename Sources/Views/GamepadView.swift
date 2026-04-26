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
        // Net layout offsets after successive tweaks:
        //   joystick   → 28% inward  (35% in, then 7% back toward edge)
        //              + 7% downward (new)
        //   bottom row → 18% up      (25% up, then 7% pulled back down)
        //   D-pad      → 10% larger  (5% + 4% + 1%)
        let centerPull = screenSize.width  * 0.28 / 2
        let analogDrop = screenSize.height * 0.07
        let bottomLift = screenSize.height * 0.18

        VStack(spacing: 14) {
            CompactShoulder(label: "L2", color: .purple) { onAction(.l2($0)) }
            CompactShoulder(label: "L1", color: .indigo) { onAction(.l1($0)) }

            Spacer(minLength: 8)

            CompactAnalogStick { x, y in onAction(.leftStick(x: x, y: y)) }
                .frame(width: 78, height: 78)
                .offset(x: centerPull, y: analogDrop)

            Spacer(minLength: 8)

            CompactDPad(onAction: onAction)
                .frame(width: 92, height: 92)
                .scaleEffect(1.10)
                .offset(y: -bottomLift)
        }
        .padding(.top, 10)
        .padding(.bottom, 56)
        .frame(maxHeight: .infinity)
        .frame(width: 106)
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
        let centerPull = screenSize.width  * 0.28 / 2
        let analogDrop = screenSize.height * 0.07
        let bottomLift = screenSize.height * 0.18

        VStack(spacing: 14) {
            CompactShoulder(label: "R2", color: .purple) { onAction(.r2($0)) }
            CompactShoulder(label: "R1", color: .indigo) { onAction(.r1($0)) }

            Spacer(minLength: 8)

            CompactAnalogStick { x, y in onAction(.rightStick(x: x, y: y)) }
                .frame(width: 78, height: 78)
                .offset(x: -centerPull, y: analogDrop)

            Spacer(minLength: 8)

            CompactFaceCluster(onAction: onAction)
                .frame(width: 102, height: 102)
                .offset(y: -bottomLift)
        }
        .padding(.top, 10)
        .padding(.bottom, 56)
        .frame(maxHeight: .infinity)
        .frame(width: 110)
    }
}

// MARK: - Compact D-Pad

private struct CompactDPad: View {
    let onAction: (GamepadAction) -> Void

    var body: some View {
        ZStack {
            // Cross-shaped frame
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.white.opacity(0.10))
                .frame(width: 92, height: 32)
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.white.opacity(0.10))
                .frame(width: 32, height: 92)
            // Center dot
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 20, height: 20)

            // Hit areas with arrows
            VStack(spacing: 0) {
                arrowButton("chevron.up")    { onAction(.dpadUp($0)) }
                Spacer().frame(height: 32)
                arrowButton("chevron.down")  { onAction(.dpadDown($0)) }
            }
            HStack(spacing: 0) {
                arrowButton("chevron.left")  { onAction(.dpadLeft($0)) }
                Spacer().frame(width: 32)
                arrowButton("chevron.right") { onAction(.dpadRight($0)) }
            }
        }
    }

    private func arrowButton(
        _ icon: String,
        handler: @escaping (Bool) -> Void
    ) -> some View {
        HapticButton(haptic: .light) { handler($0) } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 32, height: 32)
        }
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
