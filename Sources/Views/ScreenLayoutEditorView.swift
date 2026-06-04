import SwiftUI

// MARK: - Screen Layout Editor
//
// Drag / pinch the game canvas to position and size it, pick the aspect mode,
// and toggle pixel smoothing — all on a demo screen with the controls faintly
// previewed so the user sees the whole picture. Saved live.

struct ScreenLayoutEditorView: View {
    let onDone: () -> Void

    @State private var screen: ScreenLayout = ScreenLayoutStore.load()
    @State private var controls: ControlLayout = ControlLayoutStore.load()
    @State private var dragOrigin: CGPoint?
    @State private var magStart: CGSize?

    private let space = "scrEditor"

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.black

                Rectangle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    .allowsHitTesting(false)

                screenRectView(geo)

                // Faint, non-interactive controls so the screen is sized in context.
                GameControlsOverlay(layout: controls, onAction: { _ in })
                    .allowsHitTesting(false)
                    .opacity(0.35)

                topBar.frame(width: geo.size.width)

                panel
                    .frame(width: geo.size.width)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .coordinateSpace(name: space)
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
    }

    // MARK: Draggable / resizable screen

    private func screenRectView(_ geo: GeometryProxy) -> some View {
        let w = geo.size.width, h = geo.size.height
        let fw = max(CGFloat(screen.width) * w, 60)
        let fh = max(CGFloat(screen.height) * h, 60)
        return RoundedRectangle(cornerRadius: 6)
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
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.system(size: 30))
                        .foregroundColor(.cyan.opacity(0.5))
                    Text("GAME SCREEN")
                        .font(.caption.bold()).tracking(3)
                        .foregroundColor(.white.opacity(0.4))
                    Text("drag to move · pinch to resize")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.3))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.cyan.opacity(0.8), lineWidth: 2)
            )
            .frame(width: fw, height: fh)
            .position(
                x: CGFloat(screen.x) * w + fw / 2,
                y: CGFloat(screen.y) * h + fh / 2
            )
            .gesture(dragGesture(geo))
            .simultaneousGesture(magGesture)
    }

    private func dragGesture(_ geo: GeometryProxy) -> some Gesture {
        DragGesture(coordinateSpace: .named(space))
            .onChanged { value in
                if dragOrigin == nil { dragOrigin = CGPoint(x: screen.x, y: screen.y) }
                let nx = Double(dragOrigin!.x) + Double(value.translation.width) / Double(geo.size.width)
                let ny = Double(dragOrigin!.y) + Double(value.translation.height) / Double(geo.size.height)
                screen.x = min(max(nx, 0), max(0, 1 - screen.width))
                screen.y = min(max(ny, 0), max(0, 1 - screen.height))
            }
            .onEnded { _ in
                dragOrigin = nil
                ScreenLayoutStore.save(screen)
            }
    }

    private var magGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if magStart == nil {
                    magStart = CGSize(width: screen.width, height: screen.height)
                }
                let cx = screen.x + screen.width / 2
                let cy = screen.y + screen.height / 2
                let nw = min(max(Double(magStart!.width) * Double(value), 0.25), 1.0)
                let nh = min(max(Double(magStart!.height) * Double(value), 0.25), 1.0)
                screen.width = nw
                screen.height = nh
                screen.x = min(max(cx - nw / 2, 0), 1 - nw)
                screen.y = min(max(cy - nh / 2, 0), 1 - nh)
            }
            .onEnded { _ in
                magStart = nil
                ScreenLayoutStore.save(screen)
            }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: resetScreen) {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 1) {
                Text("Screen Layout")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Text("Drag / pinch the game screen")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.55))
            }

            Spacer()

            Button(action: { ScreenLayoutStore.save(screen); onDone() }) {
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

    // MARK: Bottom panel

    private var panel: some View {
        VStack(spacing: 14) {
            sliderRow(title: "Width", value: widthBinding, range: 0.3...1.0)
            sliderRow(title: "Height", value: heightBinding, range: 0.3...1.0)

            HStack {
                Text("Smooth Pixels")
                    .font(.subheadline).foregroundColor(.white.opacity(0.85))
                Spacer()
                Toggle("", isOn: smoothBinding).labelsHidden().tint(.cyan)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.10).opacity(0.96))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12)))
        )
        .frame(maxWidth: 460)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 64, alignment: .leading)
            Slider(value: value, in: range)
                .tint(.cyan)
        }
    }

    // MARK: Bindings

    private var smoothBinding: Binding<Bool> {
        Binding(get: { screen.smooth },
                set: { screen.smooth = $0; ScreenLayoutStore.save(screen) })
    }

    // Width / height keep the rect centered while resizing.
    private var widthBinding: Binding<Double> {
        Binding(
            get: { screen.width },
            set: { newW in
                let cx = screen.x + screen.width / 2
                screen.width = newW
                screen.x = min(max(cx - newW / 2, 0), max(0, 1 - newW))
                ScreenLayoutStore.save(screen)
            }
        )
    }

    private var heightBinding: Binding<Double> {
        Binding(
            get: { screen.height },
            set: { newH in
                let cy = screen.y + screen.height / 2
                screen.height = newH
                screen.y = min(max(cy - newH / 2, 0), max(0, 1 - newH))
                ScreenLayoutStore.save(screen)
            }
        )
    }

    private func resetScreen() {
        withAnimation { screen = .defaultLayout }
        ScreenLayoutStore.save(screen)
    }
}
