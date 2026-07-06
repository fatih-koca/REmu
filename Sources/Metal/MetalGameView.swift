import SwiftUI
import MetalKit

// MARK: - SwiftUI Bridge

// Which layout editor the in-game Settings sheet requested (presented after
// the sheet dismisses, like ContentView's LayoutEditor flow).
private enum GameEditor: String, Identifiable {
    case controls, screen
    var id: String { rawValue }
}

struct EmulatorScreenView: View {
    let rom: ROMEntry
    let onExit: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var showMenu = false
    @State private var showSaveStates = false
    // Full Settings (same sheet as the home screen) reachable from the pause
    // menu; editors it requests open over the game, mirroring ContentView's
    // sheet → fullScreenCover flow.
    @State private var showSettings = false
    @State private var pendingEditor: GameEditor?
    @State private var activeEditor: GameEditor?
    @State private var fastForward = false
    @State private var saveMessage: String?
    @State private var coreLoadFailed = false
    // User-customized control + screen layouts, edited from Settings via the
    // PUBG-style editors. Loaded on appear so edits made just before launching
    // a game apply immediately.
    @State private var controlLayout: ControlLayout = ControlLayoutStore.load()
    @State private var screenLayout: ScreenLayout = ScreenLayoutStore.load()
    /// Live measured FPS from the display link (the old chip was a hard-coded "60").
    @State private var measuredFPS: Double = 0

    var body: some View {
        ZStack {
            // Game + controls handles its own safe-area logic via the
            // GeometryReader inside `gameAndControls`. We must NOT put
            // .ignoresSafeArea() on the outer ZStack — doing so makes the
            // inner GeometryReader read zero-valued safeAreaInsets, which
            // collapses the column horizontal padding and shoves all the
            // buttons against the rounded-corner edge of the device.
            gameAndControls
        }
        // Menu rendered at body level so it centers within the SAFE AREA
        // (i.e., visually centered between top and home indicator). Inside
        // gameAndControls's inner ZStack the .ignoresSafeArea() consumes
        // the insets, which made every nested attempt at safe-aware
        // centering read zero and pin the card to the physical pixel
        // center — visually low because the home indicator chops the
        // bottom 21pt off the perceived screen.
        .overlay(menuOverlay)
        .sheet(isPresented: $showSaveStates) {
            SaveStatesView(romID: rom.id, onMessage: { showToast($0) })
        }
        // Full Settings from the pause menu — the exact same sheet as the
        // home screen. If it requests a layout editor, present that editor
        // over the game once the sheet closes, then re-apply the layouts so
        // edits take effect on the RUNNING game immediately.
        .sheet(isPresented: $showSettings, onDismiss: {
            reloadLayouts()
            if let pending = pendingEditor {
                pendingEditor = nil
                activeEditor = pending
            }
        }) {
            SettingsView(
                onEditScreen:   { pendingEditor = .screen;   showSettings = false },
                onEditControls: { pendingEditor = .controls; showSettings = false }
            )
        }
        .fullScreenCover(item: $activeEditor) { editor in
            switch editor {
            case .controls:
                ControlLayoutEditorView { activeEditor = nil; reloadLayouts() }
            case .screen:
                ScreenLayoutEditorView { activeEditor = nil; reloadLayouts() }
            }
        }
        .onAppear {
            // Pick up any layout edits made from Settings before launching.
            controlLayout = ControlLayoutStore.load()
            screenLayout  = ScreenLayoutStore.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .remuFPSUpdate)) { note in
            if let fps = note.object as? Double { measuredFPS = fps }
        }
        .onChange(of: scenePhase) { phase in
            // Auto-save when the app is sent to the background so progress is
            // never lost if iOS terminates it. Skipped on the menu/dialog
            // pause states (nothing meaningful changed there).
            if phase == .background, !coreLoadFailed { autoSave() }
        }
    }

    /// Re-read the saved layouts so Settings/editor changes (screen rect,
    /// filter, smoothing, control positions) apply to the running game.
    private func reloadLayouts() {
        controlLayout = ControlLayoutStore.load()
        screenLayout  = ScreenLayoutStore.load()
    }

    /// Snapshot the running game into a single auto-save slot (replaces the
    /// previous auto-save). Used on backgrounding and on exit to library.
    private func autoSave() {
        guard let data = CoreBridgeWrapper.shared.serializeState() else { return }
        _ = try? SaveStateManager.shared.saveState(
            romID: rom.id, stateData: data,
            screenshot: GameSnapshot.shared.thumbnail(), isAuto: true)
    }

    @ViewBuilder
    private var menuOverlay: some View {
        if showMenu {
            InGameMenuView(
                rom: rom,
                onExit: { autoSave(); onExit() },
                onDismiss: { showMenu = false },
                onShowSaveStates: {
                    showMenu = false
                    showSaveStates = true
                },
                onOpenSettings: {
                    showMenu = false
                    showSettings = true
                }
            ) { msg in
                showToast(msg)
            }
        }
    }

    private var gameAndControls: some View {
        GeometryReader { geo in
            let inset = geo.safeAreaInsets
            // hPad sits ON TOP of the system safe area. 4pt keeps L1/L2/R1/R2
            // hugging the rounded-corner safe edge for thumb reach.
            let hPad: CGFloat = 4

            ZStack {
                Color.black
                // Game is pulled flush to the physical top edge — pause/FPS
                // chips float on top as translucent overlays. Bottom keeps a
                // 3% breathing margin so the canvas doesn't hug the home
                // indicator on every device size.
                MetalViewRepresentable(
                    rom: rom,
                    safeAreaInsets: rendererInsets(geo: geo),
                    // Freeze the core's clock while the in-game menu is up,
                    // while the save-states picker sheet is open, or while a
                    // core-load failure dialog is shown — no point spinning a
                    // half-loaded core in the background.
                    isPaused: showMenu || coreLoadFailed || showSaveStates
                              || showSettings || activeEditor != nil,
                    fastForward: fastForward,
                    aspectMode: screenLayout.aspectMode,
                    smoothing: screenLayout.smooth,
                    filter: screenLayout.filter
                )
                // The `.ignoresSafeArea()` on the outer ZStack does not
                // automatically propagate into a UIViewControllerRepresentable
                // (SwiftUI re-applies the window safe area to it), which is
                // what was pushing the canvas ~50pt below the physical top
                // edge even when we asked for top=0. This forces it through.
                .ignoresSafeArea()

                // Top strip only — bottom ad strip removed for now,
                // can be reintroduced when the AdMob SDK is wired in.
                VStack(spacing: 0) {
                    // Clean strip: just pause + a LIVE fps chip (no title /
                    // console label — they wasted space over the game).
                    GameInfoTopStrip(
                        stats: [("FPS", measuredFPS > 0
                            ? String(format: "%.1f", locale: .current, measuredFPS)
                            : "—")],
                        onPause: { showMenu.toggle() }
                    )
                    Spacer(minLength: 0)
                }
                .padding(.leading,  inset.leading  + hPad)
                .padding(.trailing, inset.trailing + hPad)
                .padding(.top,      max(inset.top,    4))
                .padding(.bottom,   max(inset.bottom, 4))

                // Touch controls — freely positioned per the user's saved
                // layout (Settings -> Console Layout). ignoresSafeArea puts the
                // overlay in full-window coordinates so it lines up with the
                // Metal canvas and the editor preview.
                GameControlsOverlay(
                    layout: controlLayout,
                    onAction: handleGamepadAction,
                    onFastForward: { fastForward = $0 }
                )
                .ignoresSafeArea()
                .allowsHitTesting(!showMenu && !coreLoadFailed)

                // Toast
                if let msg = saveMessage {
                    VStack {
                        Spacer()
                        Text(msg)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(8)
                            .foregroundColor(.green)
                            .padding(.bottom, 60)
                            .transition(.opacity)
                    }
                }

                // In-game menu is now rendered at body-level overlay so
                // it centers within the SAFE AREA, not the physical pixel
                // center which appears low due to the home indicator.

                // Core load failure overlay
                if coreLoadFailed {
                    coreFailedOverlay
                }
            }
            .ignoresSafeArea()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .remuCoreLoadFailed)
        ) { _ in
            coreLoadFailed = true
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .remuCoreLoaded)
        ) { _ in
            coreLoadFailed = false
        }
    }

    private var coreFailedOverlay: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 38))
                    .foregroundColor(.orange)

                Text("Couldn't start this game")
                    .font(.headline).bold()
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("\(rom.console.displayName) couldn't be started. This system may be unsupported on this device, or a required BIOS file is missing — PlayStation games need a BIOS file you provide yourself. The built-in Glowchase demo always works.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)

                Button(action: onExit) {
                    Text("Back to Library")
                        .font(.headline)
                        .foregroundColor(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.orange))
                }
                .buttonStyle(.plain)
            }
            .padding(28)
            .frame(maxWidth: 420)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(white: 0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.15))
                    )
            )
            .padding(.horizontal, 24)
        }
    }

    /// Letterbox insets (points, full-window relative) for the Metal canvas,
    /// derived from the user's screen-layout rect. The MTKView spans the entire
    /// window, so the rect is expressed relative to the full window: geo.size is
    /// inset by the safe area, so we add it back to recover the true window size.
    private func rendererInsets(geo: GeometryProxy) -> EdgeInsets {
        let safe = geo.safeAreaInsets
        let fullW = geo.size.width  + safe.leading + safe.trailing
        let fullH = geo.size.height + safe.top     + safe.bottom
        let r = screenLayout
        return EdgeInsets(
            top:      max(r.y * fullH, 0),
            leading:  max(r.x * fullW, 0),
            bottom:   max((1 - (r.y + r.height)) * fullH, 0),
            trailing: max((1 - (r.x + r.width))  * fullW, 0)
        )
    }

    private func handleGamepadAction(_ action: GamepadAction) {
        // Forward button events to CoreBridge
        CoreBridgeWrapper.shared.handleInput(action)
    }

    private func showToast(_ message: String) {
        saveMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            saveMessage = nil
        }
    }
}


// MARK: - UIViewControllerRepresentable

struct MetalViewRepresentable: UIViewControllerRepresentable {
    let rom: ROMEntry
    let safeAreaInsets: EdgeInsets
    /// True while the in-game menu (or any other overlay that should
    /// freeze gameplay) is showing. Controlled by SwiftUI; the controller
    /// stops the CADisplayLink while paused so retro_run is not called
    /// and the core's clock does not advance behind the menu.
    let isPaused: Bool
    /// True while the hold-to-fast-forward button is pressed. The controller
    /// then runs several core frames per display tick (and mutes audio).
    let fastForward: Bool
    /// Screen options from Settings: 0 fit / 1 fill / 2 integer, and whether
    /// to smooth (linear) or keep sharp (nearest) pixels.
    let aspectMode: Int
    let smoothing: Bool
    let filter: Int

    func makeUIViewController(context: Context) -> MetalGameViewController {
        let vc = MetalGameViewController()
        vc.rom = rom
        vc.applySafeAreaInsets(safeAreaInsets)
        return vc
    }

    func updateUIViewController(_ uiViewController: MetalGameViewController, context: Context) {
        // Insets shift when the device rotates or the on-screen keyboard
        // appears; forward every update to the renderer.
        uiViewController.applySafeAreaInsets(safeAreaInsets)
        uiViewController.setPaused(isPaused)
        uiViewController.setFastForward(fastForward)
        uiViewController.setScreenOptions(aspectMode: aspectMode, smoothing: smoothing, filter: filter)
    }
}

// MARK: - Metal View Controller

final class MetalGameViewController: UIViewController {
    var rom: ROMEntry?

    private var mtkView: MTKView!
    private var renderer: MetalRenderer!
    private var displayLink: CADisplayLink?

    /// 1 = normal speed; > 1 while the fast-forward button is held (run N core
    /// frames per display tick). `suppressVideo` skips the draw on the
    /// intermediate frames so only the last of each batch is presented.
    private var fastForwardFrames = 1
    private var suppressVideo = false

    /// Real FPS measurement: presented frames counted over ~1s windows and
    /// published to SwiftUI. One presented frame per tick (fast-forward's
    /// extra core frames are headless, so they don't inflate the number).
    private var fpsFrameCount = 0
    private var fpsWindowStart: CFTimeInterval = CACurrentMediaTime()

    /// Buffered insets from SwiftUI — applied on the renderer if it's already
    /// up, otherwise stashed and replayed at setupMetal() time.
    private var pendingInsets: EdgeInsets = EdgeInsets()
    // Same pattern for the screen options — the first SwiftUI update can land
    // before viewDidLoad creates the renderer, so we stash and replay.
    private var pendingAspectMode = 0
    private var pendingSmoothing = true
    private var pendingFilter = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupMetal()
        renderer.safeInsetsPt = (
            top:      pendingInsets.top,
            leading:  pendingInsets.leading,
            bottom:   pendingInsets.bottom,
            trailing: pendingInsets.trailing
        )
        renderer.aspectMode = pendingAspectMode
        renderer.smoothing  = pendingSmoothing
        renderer.filter     = pendingFilter
        startEmulation()
    }

    /// Called by MetalViewRepresentable on every SwiftUI state update so the
    /// renderer's letterbox stays aligned with the current safe-area geometry.
    func applySafeAreaInsets(_ insets: EdgeInsets) {
        pendingInsets = insets
        renderer?.safeInsetsPt = (
            top:      insets.top,
            leading:  insets.leading,
            bottom:   insets.bottom,
            trailing: insets.trailing
        )
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        displayLink?.invalidate()
        AudioEngine.shared.stop()
        GameControllerManager.shared.onAction = nil
        CoreBridgeWrapper.shared.stopCore()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // SwiftUI's UIViewControllerRepresentable refuses to honor parent
        // .ignoresSafeArea() — it positions this VC's view INSIDE the
        // window's safe area no matter what the SwiftUI hierarchy does.
        // Force the MTKView to span the entire window in our parent's
        // coordinate space so the renderer's drawableSize matches the
        // physical screen and our top/bottom insets behave as advertised.
        guard let window = view.window else { return }
        view.clipsToBounds = false
        let windowFrameInView = view.convert(window.bounds, from: nil)
        if mtkView.frame != windowFrameInView {
            mtkView.autoresizingMask = []
            mtkView.frame = windowFrameInView
        }
    }

    // MARK: Metal Setup

    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal not supported on this device")
        }

        mtkView = MTKView(frame: view.bounds, device: device)
        mtkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = false
        mtkView.isPaused = true           // driven by CoreBridge frame callbacks
        mtkView.enableSetNeedsDisplay = false
        // Letterbox / pillarbox bars (anywhere the aspect-fit quad doesn't
        // cover) fall through to this clear color.
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.addSubview(mtkView)

        renderer = MetalRenderer(device: device, view: mtkView)
        mtkView.delegate = renderer
    }

    // MARK: Emulation

    private func startEmulation() {
        guard let rom else { return }

        let ok = CoreBridgeWrapper.shared.loadCore(
            identifier: rom.console.coreIdentifier,
            romPath: rom.filePath.path
        )

        // Defer the post one runloop tick so the SwiftUI host has finished
        // mounting EmulatorScreenView and its `.onReceive` is subscribed —
        // posting synchronously here can fire before the listener is wired
        // up, which left the "core failed" overlay stuck off-screen on a
        // black render surface.
        let coreId = rom.console.coreIdentifier
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: ok ? .remuCoreLoaded : .remuCoreLoadFailed,
                object: coreId
            )
        }

        guard ok else { return }   // don't bother starting frame loop if no core

        // CoreBridge calls back on each video frame; we drive MTKView from there.
        CoreBridgeWrapper.shared.onVideoFrame = { [weak self] pixelBuffer in
            guard let self, !self.suppressVideo else { return }
            GameSnapshot.shared.store(pixelBuffer)   // for save-state thumbnails
            self.renderer.update(with: pixelBuffer)
            self.mtkView.draw()
        }

        // Fiziksel gamepad bağlıysa input'u ortak handler'a yolla
        GameControllerManager.shared.onAction = { action in
            CoreBridgeWrapper.shared.handleInput(action)
        }

        // AudioEngine reads the core's native sample rate (rn_audio_sample_rate)
        // when start() runs, so it MUST come after a successful loadCore.
        AudioEngine.shared.start()

        // Match the core's reported FPS — SNES NTSC ≈ 60.0988, PAL ≈ 50, etc.
        // CADisplayLink will round to the nearest panel rate; the AV-info value
        // is the upper bound we ask for.
        let coreFPS = CoreBridgeWrapper.shared.videoFPS
        let preferred = coreFPS > 0 ? Float(coreFPS) : 60
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: 30,
            maximum: 120,
            preferred: preferred
        )
        link.add(to: .main, forMode: .common)
        self.displayLink = link

        CoreBridgeWrapper.shared.startCore()
    }

    @objc private func tick() {
        let frames = fastForwardFrames
        if frames <= 1 {
            CoreBridgeWrapper.shared.runFrame()
        } else {
            // Fast-forward: advance N-1 frames "headless" (video suppressed),
            // then run the final frame normally so only it is presented. Keeps
            // FF cheap on the GPU and dodges the present-throttle of drawing
            // every frame.
            suppressVideo = true
            for _ in 0..<(frames - 1) {
                CoreBridgeWrapper.shared.runFrame()
            }
            suppressVideo = false
            CoreBridgeWrapper.shared.runFrame()
        }

        // Live FPS: publish the measured presented-frame rate ~once a second.
        // Sent as a Double so the chip can show one decimal (59.7, 60.1…) —
        // detailed enough to tell NTSC pacing from a real slowdown.
        fpsFrameCount += 1
        let now = CACurrentMediaTime()
        let elapsed = now - fpsWindowStart
        if elapsed >= 1.0 {
            let fps = Double(fpsFrameCount) / elapsed
            fpsFrameCount = 0
            fpsWindowStart = now
            NotificationCenter.default.post(name: .remuFPSUpdate, object: fps)
        }
    }

    /// Freeze (or resume) the core's clock. Pausing the CADisplayLink
    /// stops `tick()`, which means `retro_run` is no longer called — game
    /// state freezes, video stays on its last drawn frame, and the audio
    /// ring buffer drains within ~100 ms (the AudioEngine's underrun fade
    /// handles the silence boundary). Resuming flips it back without any
    /// state restoration: the next tick simply runs the next frame.
    func setPaused(_ paused: Bool) {
        displayLink?.isPaused = paused
    }

    /// Hold-to-fast-forward. Runs the core a few extra frames per display tick
    /// and mutes audio — the N× sample flood would otherwise overrun the audio
    /// ring buffer into a stutter. 3× is a comfortable speed-up that most
    /// software cores sustain on-device without dropping below real-time.
    func setFastForward(_ on: Bool) {
        fastForwardFrames = on ? 3 : 1
        AudioEngine.shared.setMuted(on)
    }

    /// Aspect mode (0 fit / 1 fill / 2 integer) and texture smoothing, set
    /// from Settings → Screen. Stashed too, in case the renderer isn't up yet.
    func setScreenOptions(aspectMode: Int, smoothing: Bool, filter: Int) {
        pendingAspectMode = aspectMode
        pendingSmoothing  = smoothing
        pendingFilter     = filter
        renderer?.aspectMode = aspectMode
        renderer?.smoothing  = smoothing
        renderer?.filter     = filter
    }
}

// MARK: - Metal Renderer

/// Mirrors the `Uniforms` struct in the fragment shader (mode + source size).
private struct ScreenUniforms {
    var mode: UInt32
    var texW: Float
    var texH: Float
}

final class MetalRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState!
    private var texture: MTLTexture?
    private var vertexBuffer: MTLBuffer!

    /// Screen options (set from Settings via the controller).
    /// 0 = Fit (letterbox, preserve aspect), 1 = Fill (stretch to edges),
    /// 2 = Integer (largest whole-number pixel multiple — sharpest).
    var aspectMode: Int = 0
    /// true = linear sampling (smooth), false = nearest (sharp retro pixels).
    var smoothing: Bool = true
    /// Retro screen filter: 0 None · 1 Scanlines · 2 CRT · 3 LCD grid.
    var filter: Int = 0
    private var nearestSampler: MTLSamplerState!
    private var linearSampler: MTLSamplerState!

    /// Safe-area insets in POINTS, set from SwiftUI. We respect them when
    /// computing the aspect-fit rectangle so the game stays out of the
    /// rounded-corner / Dynamic-Island / home-indicator regions on iPhone
    /// — content was visibly clipping at the bottom edge before this.
    var safeInsetsPt: (top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) =
        (0, 0, 0, 0)

    // Capacity: 4 vertices × (xy + uv) × 4 bytes — re-written each draw call to
    // keep the game letterboxed inside the drawable as the device rotates or
    // multitasks. Backed by .storageModeShared so we can memcpy directly.
    private static let kVertexFloatCount = 4 * 4

    init(device: MTLDevice, view: MTKView) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        super.init()
        buildPipeline(view: view)
        buildSamplers()
        vertexBuffer = device.makeBuffer(
            length: Self.kVertexFloatCount * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )
    }

    private func buildSamplers() {
        let d = MTLSamplerDescriptor()
        d.minFilter = .nearest; d.magFilter = .nearest
        nearestSampler = device.makeSamplerState(descriptor: d)
        d.minFilter = .linear;  d.magFilter = .linear
        linearSampler  = device.makeSamplerState(descriptor: d)
    }

    /// Aspect-fit the game texture inside (drawable − safe-area insets).
    /// We compute everything in PIXEL space then map to clip space at the
    /// end so the math stays straightforward and asymmetric insets (a notch
    /// only on the leading edge in landscape) center correctly.
    private func updateVertexBuffer(viewSize: CGSize,
                                    contentScale: CGFloat,
                                    textureWidth: Int,
                                    textureHeight: Int) {
        guard viewSize.width > 0, viewSize.height > 0,
              textureWidth > 0, textureHeight > 0 else { return }

        // drawableSize is in pixels; safe-area insets are in points.
        // Multiply insets by the device scale so we can subtract directly.
        let s = Float(contentScale)
        let topPx     = Float(safeInsetsPt.top)      * s
        let leadPx    = Float(safeInsetsPt.leading)  * s
        let botPx     = Float(safeInsetsPt.bottom)   * s
        let trailPx   = Float(safeInsetsPt.trailing) * s

        let viewW = Float(viewSize.width)
        let viewH = Float(viewSize.height)

        // Effective canvas the game is allowed to occupy.
        let availW = max(viewW - leadPx - trailPx, 1)
        let availH = max(viewH - topPx  - botPx,   1)

        // Size the game rect inside that canvas per the chosen aspect mode.
        let texAR  = Float(textureWidth) / Float(textureHeight)
        var fitW: Float
        var fitH: Float
        switch aspectMode {
        case 1: // Fill — stretch to the whole canvas, ignoring aspect ratio.
            fitW = availW
            fitH = availH
        case 2: // Integer — largest whole-number multiple of the native size.
            let scale = max(1, floor(min(availW / Float(textureWidth),
                                         availH / Float(textureHeight))))
            fitW = Float(textureWidth)  * scale
            fitH = Float(textureHeight) * scale
        default: // 0 = Fit — letterbox, preserve aspect.
            fitW = availW
            fitH = availW / texAR
            if fitH > availH {
                fitH = availH
                fitW = availH * texAR
            }
        }

        // Center the fit rect inside the SAFE canvas (which itself is offset
        // from the view origin by the leading / top insets).
        let cx = leadPx + availW * 0.5
        let cy = topPx  + availH * 0.5
        let left   = cx - fitW * 0.5
        let right  = cx + fitW * 0.5
        let topPos = cy - fitH * 0.5
        let botPos = cy + fitH * 0.5

        // Convert pixel coords → clip space (-1..+1, +Y up).
        func toClipX(_ px: Float) -> Float { (px / viewW) * 2 - 1 }
        func toClipY(_ py: Float) -> Float { 1 - (py / viewH) * 2 }

        let cl = toClipX(left)
        let cr = toClipX(right)
        let ct = toClipY(topPos)
        let cb = toClipY(botPos)

        let verts: [Float] = [
            cl, ct, 0, 0,    // top-left
            cr, ct, 1, 0,    // top-right
            cl, cb, 0, 1,    // bottom-left
            cr, cb, 1, 1,    // bottom-right
        ]
        memcpy(vertexBuffer.contents(), verts,
               verts.count * MemoryLayout<Float>.stride)
    }

    func update(with pixelBuffer: PixelBuffer) {
        let width  = Int(pixelBuffer.width)
        let height = Int(pixelBuffer.height)
        guard width > 0, height > 0, let data = pixelBuffer.data else { return }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = MTLTextureUsage.shaderRead
        texture = device.makeTexture(descriptor: descriptor)
        texture?.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: data,
            bytesPerRow: width * 4
        )
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard
            let drawable = view.currentDrawable,
            let descriptor = view.currentRenderPassDescriptor,
            let texture
        else { return }

        // Aspect-fit the game inside whatever drawable size the OS gave us,
        // minus the safe-area insets we received from SwiftUI.
        updateVertexBuffer(
            viewSize: view.drawableSize,
            contentScale: view.contentScaleFactor,
            textureWidth: texture.width,
            textureHeight: texture.height
        )

        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(smoothing ? linearSampler : nearestSampler, index: 0)
        var u = ScreenUniforms(mode: UInt32(max(0, filter)),
                               texW: Float(texture.width), texH: Float(texture.height))
        encoder.setFragmentBytes(&u, length: MemoryLayout<ScreenUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func buildPipeline(view: MTKView) {
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        struct Vertex { float2 pos [[attribute(0)]]; float2 uv [[attribute(1)]]; };
        struct Fragment { float4 pos [[position]]; float2 uv; };
        struct Uniforms { uint mode; float texW; float texH; };
        vertex Fragment vert(uint vid [[vertex_id]], constant float4* v [[buffer(0)]]) {
            Fragment out;
            out.pos = float4(v[vid].xy, 0, 1);
            out.uv = v[vid].zw;
            return out;
        }
        fragment float4 frag(Fragment in [[stage_in]],
                             texture2d<float> tex [[texture(0)]],
                             sampler s [[sampler(0)]],
                             constant Uniforms& u [[buffer(0)]]) {
            float2 uv = in.uv;

            // CRT (mode 2): gentle barrel curvature; black outside the curve.
            if (u.mode == 2u) {
                float2 c = uv - 0.5;
                uv = uv + c * dot(c, c) * 0.10;
                if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
                    return float4(0.0, 0.0, 0.0, 1.0);
            }

            float4 col = tex.sample(s, uv);

            if (u.mode == 1u || u.mode == 2u) {
                // Scanlines locked to source pixel rows.
                float l = sin(uv.y * u.texH * 3.14159265);
                col.rgb *= mix(0.70, 1.0, l * l);
            }
            if (u.mode == 2u) {
                // Aperture mask on source columns + vignette for CRT depth.
                float m = sin(uv.x * u.texW * 3.14159265);
                col.rgb *= mix(0.88, 1.0, m * m);
                float2 vc = uv - 0.5;
                col.rgb *= 1.0 - dot(vc, vc) * 0.45;
                col.rgb *= 1.08;   // recover a little brightness lost to the mask
            }
            if (u.mode == 3u) {
                // LCD grid: thin dark gutters between source pixels (handhelds).
                float2 g = fract(uv * float2(u.texW, u.texH));
                float gx = smoothstep(0.0, 0.10, g.x) * smoothstep(0.0, 0.10, 1.0 - g.x);
                float gy = smoothstep(0.0, 0.10, g.y) * smoothstep(0.0, 0.10, 1.0 - g.y);
                col.rgb *= mix(0.80, 1.0, gx * gy);
            }
            return col;
        }
        """
        let library = try! device.makeLibrary(source: source, options: nil)
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "vert")
        desc.fragmentFunction = library.makeFunction(name: "frag")
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        pipelineState = try! device.makeRenderPipelineState(descriptor: desc)
    }
}

// MARK: - In-Game Menu

struct InGameMenuView: View {
    let rom: ROMEntry
    let onExit: () -> Void
    let onDismiss: () -> Void
    let onShowSaveStates: () -> Void
    let onOpenSettings: () -> Void
    let onMessage: (String) -> Void

    var body: some View {
        // Mounted as a body-level overlay on EmulatorScreenView, so the
        // outer ZStack's safe-area-respecting frame already centers this
        // card at the visual midpoint (above the home indicator). No
        // manual offset needed.
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                menuHeader
                Divider().background(Color.white.opacity(0.1))
                menuActions
            }
            .frame(width: 260)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(white: 0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.15))
                    )
            )
        }
    }

    private var menuHeader: some View {
        VStack(spacing: 4) {
            Text(rom.title)
                .font(.headline)
                .foregroundColor(.white)
            Text(rom.console.displayName)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(16)
    }

    private var menuActions: some View {
        VStack(spacing: 0) {
            // First action: a clearly labelled "Resume" so users don't have to
            // discover that tapping outside the card also dismisses it. The
            // background tap still works for muscle memory. Tinted green to
            // read as a "go / play" signal — pairs naturally with the red
            // "Exit to Library" at the bottom.
            menuButton("Resume", icon: "play.fill", tint: .green) {
                onDismiss()
            }
            Divider().background(Color.white.opacity(0.1))
            menuButton("Quick Save", icon: "bolt.fill", tint: .green) {
                performSave()
            }
            menuButton("Quick Load", icon: "arrow.up.circle") {
                performLoad()
            }
            menuButton("Save States", icon: "square.stack.3d.up") {
                onShowSaveStates()
            }
            Divider().background(Color.white.opacity(0.1))
            menuButton("Settings", icon: "gearshape") {
                onOpenSettings()
            }
            Divider().background(Color.white.opacity(0.1))
            menuButton("Exit to Library", icon: "house", tint: .red) {
                onExit()
            }
        }
        .padding(.vertical, 8)
    }

    private func menuButton(
        _ title: LocalizedStringKey,
        icon: String,
        tint: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundColor(tint)
                Text(title)
                    .foregroundColor(tint)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private func performSave() {
        guard let data = CoreBridgeWrapper.shared.serializeState() else {
            onMessage(String(localized: "Save failed"))
            return
        }
        do {
            _ = try SaveStateManager.shared.saveState(
                romID: rom.id, stateData: data,
                screenshot: GameSnapshot.shared.thumbnail())
            onMessage(String(localized: "State saved"))
        } catch {
            onMessage("\(String(localized: "Save error")): \(error.localizedDescription)")
        }
        onDismiss()
    }

    private func performLoad() {
        do {
            guard let data = try SaveStateManager.shared.loadLatestState(for: rom.id) else {
                onMessage(String(localized: "No save found"))
                return
            }
            CoreBridgeWrapper.shared.deserializeState(data)
            onMessage(String(localized: "State loaded"))
        } catch {
            onMessage(String(localized: "Load error"))
        }
        onDismiss()
    }
}
