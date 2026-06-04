import SwiftUI

// MARK: - Console Layout Editor
//
// PUBG-/Brawl-Stars-style touch-control editor. The user drags each control
// around a demo game screen and tunes its size / opacity / visibility one by
// one. Every change is saved live so it applies the next time a game launches.

struct ControlLayoutEditorView: View {
    let onDone: () -> Void

    @State private var layout: ControlLayout = ControlLayoutStore.load()
    @State private var screen: ScreenLayout = ScreenLayoutStore.load()
    @State private var selected: ControlKind?
    @State private var dragKind: ControlKind?
    @State private var dragOrigin = CGPoint.zero
    @State private var pulse = false   // drives the blinking green glow on the selected control

    private let space = "ctlEditor"

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.black

                // Where the game will be — so controls are placed in context.
                DemoScreenView(screen: screen)
                    .allowsHitTesting(false)

                // Editable controls.
                ForEach(ControlKind.allCases) { kind in
                    editableControl(kind, geo: geo)
                }

                topBar
                    .frame(width: geo.size.width)

                if let sel = selected {
                    selectionPanel(sel)
                        .frame(width: geo.size.width)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .coordinateSpace(name: space)
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    // MARK: Editable control

    private func editableControl(_ kind: ControlKind, geo: GeometryProxy) -> some View {
        let cfg = layout[kind]
        let isSel = (selected == kind)
        // No frame around controls — just the button. The selected one gets a
        // blinking green glow. Overlay/shadow are anchored to the control's real
        // size so the touch target stays exactly the button (no giant boxes).
        return ControlView(kind: kind)
            .allowsHitTesting(false)
            .opacity(cfg.hidden ? 0.25 : max(cfg.opacity, 0.45))
            .overlay {
                if isSel {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green, lineWidth: 2.5)
                        .padding(-6)
                        .opacity(pulse ? 1.0 : 0.2)
                }
            }
            .scaleEffect(CGFloat(cfg.scale))
            .shadow(
                color: isSel ? Color.green.opacity(pulse ? 0.9 : 0.15) : .clear,
                radius: isSel ? 14 : 0
            )
            .contentShape(Rectangle())
            .position(x: CGFloat(cfg.x) * geo.size.width, y: CGFloat(cfg.y) * geo.size.height)
            .gesture(dragGesture(kind, geo: geo))
            .onTapGesture { selected = kind }
    }

    private func dragGesture(_ kind: ControlKind, geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(space))
            .onChanged { value in
                if dragKind != kind {
                    dragKind = kind
                    dragOrigin = CGPoint(x: layout[kind].x, y: layout[kind].y)
                    selected = kind
                }
                let nx = Double(dragOrigin.x) + Double(value.translation.width) / Double(geo.size.width)
                let ny = Double(dragOrigin.y) + Double(value.translation.height) / Double(geo.size.height)
                layout[kind].x = min(max(nx, 0.03), 0.97)
                layout[kind].y = min(max(ny, 0.05), 0.97)
            }
            .onEnded { _ in
                dragKind = nil
                ControlLayoutStore.save(layout)
            }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: resetAll) {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 1) {
                Text("Console Layout")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Text("Drag a control to move · tap to adjust")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.55))
            }

            Spacer()

            Button(action: { ControlLayoutStore.save(layout); onDone() }) {
                Text("Done")
                    .font(.subheadline.bold())
                    .foregroundColor(.black)
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(Capsule().fill(Color.green))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: Selection panel

    private func selectionPanel(_ kind: ControlKind) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(kind.displayName)
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button(action: { layout[kind].hidden.toggle(); ControlLayoutStore.save(layout) }) {
                    Label(
                        layout[kind].hidden ? "Show" : "Hide",
                        systemImage: layout[kind].hidden ? "eye" : "eye.slash"
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(layout[kind].hidden ? .green : .orange)
                }
                .buttonStyle(.plain)

                Button(action: { resetOne(kind) }) {
                    Image(systemName: "arrow.counterclockwise.circle")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)

                Button(action: { withAnimation { selected = nil } }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }

            sliderRow(title: "Size", value: bind(kind, \.scale), range: 0.6...1.7)
            sliderRow(title: "Opacity", value: bind(kind, \.opacity), range: 0.2...1.0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.10).opacity(0.96))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12)))
        )
        .frame(maxWidth: 460)
        .padding(.horizontal, 20)
        .padding(.top, 58)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 64, alignment: .leading)
            Slider(value: value, in: range)
                .tint(.green)
        }
    }

    // MARK: Helpers

    private func bind(_ kind: ControlKind, _ keyPath: WritableKeyPath<ControlConfig, Double>) -> Binding<Double> {
        Binding(
            get: { layout[kind][keyPath: keyPath] },
            set: { layout[kind][keyPath: keyPath] = $0; ControlLayoutStore.save(layout) }
        )
    }

    private func resetAll() {
        withAnimation { layout = .defaultLayout }
        selected = nil
        ControlLayoutStore.save(layout)
    }

    private func resetOne(_ kind: ControlKind) {
        layout[kind] = ControlLayout.defaultConfig(for: kind)
        ControlLayoutStore.save(layout)
    }
}
