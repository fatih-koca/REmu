import SwiftUI

// MARK: - Live Controls Overlay
//
// Renders the touch controls at the user's saved positions/sizes during
// gameplay. Driven entirely by ControlLayout. Add `.ignoresSafeArea()` at the
// call site so the internal GeometryReader spans the full window and stays in
// the same coordinate space as the Metal canvas and the editor preview.

struct GameControlsOverlay: View {
    let layout: ControlLayout
    var onAction: (GamepadAction) -> Void
    var onFastForward: (Bool) -> Void = { _ in }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(ControlKind.allCases) { kind in
                    let cfg = layout[kind]
                    if !cfg.hidden {
                        ControlView(
                            kind: kind,
                            onAction: onAction,
                            onFastForward: onFastForward
                        )
                        .scaleEffect(CGFloat(cfg.scale))
                        .opacity(cfg.opacity)
                        .position(
                            x: CGFloat(cfg.x) * geo.size.width,
                            y: CGFloat(cfg.y) * geo.size.height
                        )
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Single Control Widget
//
// The visual + interactive widget for one control kind. Used live (fires
// GamepadAction) and, with `.allowsHitTesting(false)`, as the editor preview.

struct ControlView: View {
    let kind: ControlKind
    var onAction: (GamepadAction) -> Void = { _ in }
    var onFastForward: (Bool) -> Void = { _ in }

    var body: some View {
        switch kind {
        case .dpad:
            CompactDPad(onAction: onAction)
                .frame(width: CompactDPad.size, height: CompactDPad.size)
        case .leftStick:
            CompactAnalogStick { x, y in onAction(.leftStick(x: x, y: y)) }
                .frame(width: 78, height: 78)
        case .rightStick:
            CompactAnalogStick { x, y in onAction(.rightStick(x: x, y: y)) }
                .frame(width: 78, height: 78)
        case .faceTriangle:
            FaceButtonView(label: "△", color: .green) { onAction(.triangle($0)) }
        case .faceCross:
            FaceButtonView(label: "✕", color: .blue) { onAction(.cross($0)) }
        case .faceSquare:
            FaceButtonView(label: "□", color: .pink) { onAction(.square($0)) }
        case .faceCircle:
            FaceButtonView(label: "○", color: .red) { onAction(.circle($0)) }
        case .l1:
            CompactShoulder(label: "L1", color: .indigo) { onAction(.l1($0)) }
        case .l2:
            CompactShoulder(label: "L2", color: .purple) { onAction(.l2($0)) }
        case .r1:
            CompactShoulder(label: "R1", color: .indigo) { onAction(.r1($0)) }
        case .r2:
            CompactShoulder(label: "R2", color: .purple) { onAction(.r2($0)) }
        case .start:
            MetaButtonView(label: "START", tint: .green) { onAction(.start($0)) }
        case .select:
            MetaButtonView(label: "SELECT", tint: .orange) { onAction(.select($0)) }
        case .fastForward:
            MetaButtonView(label: "FF ▶▶", tint: .blue) { onFastForward($0) }
        }
    }
}

// MARK: - Demo Game Screen
//
// A faux game canvas drawn at the ScreenLayout rect so the user can position
// controls / size the screen relative to where the game actually appears. Used
// by both editors. Add `.ignoresSafeArea()` at the call site for full-window
// coordinates that match the live renderer.

struct DemoScreenView: View {
    let screen: ScreenLayout

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let fw = max(CGFloat(screen.width) * w, 1)
            let fh = max(CGFloat(screen.height) * h, 1)
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.13, blue: 0.22),
                            Color(red: 0.04, green: 0.05, blue: 0.09)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    VStack(spacing: 10) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 34))
                            .foregroundColor(.white.opacity(0.22))
                        Text("GAME SCREEN")
                            .font(.caption.bold())
                            .tracking(3)
                            .foregroundColor(.white.opacity(0.30))
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
                .frame(width: fw, height: fh)
                .position(
                    x: CGFloat(screen.x) * w + fw / 2,
                    y: CGFloat(screen.y) * h + fh / 2
                )
        }
    }
}
