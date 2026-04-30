import SwiftUI
import MetalKit

// MARK: - SwiftUI Bridge

struct EmulatorScreenView: View {
    let rom: ROMEntry
    let onExit: () -> Void

    @State private var showMenu = false
    @State private var saveMessage: String?
    @State private var coreLoadFailed = false

    var body: some View {
        GeometryReader { geo in
            let inset = geo.safeAreaInsets
            // hPad sits ON TOP of the system safe area (which already
            // covers the Dynamic Island). 18pt = compact corner clearance,
            // controls stay close to the edge for natural thumb reach.
            let hPad: CGFloat = 18

            ZStack {
                Color.black
                MetalViewRepresentable(rom: rom)

                // Top + Bottom strips
                VStack(spacing: 0) {
                    GameInfoTopStrip(
                        title: rom.title,
                        subtitle: rom.console.rawValue,
                        stats: [("FPS", "60")],
                        onPause: { showMenu.toggle() }
                    )
                    Spacer(minLength: 0)
                    AdBottomStrip()
                }
                .padding(.leading,  inset.leading  + hPad)
                .padding(.trailing, inset.trailing + hPad)
                .padding(.top,      max(inset.top,    4))
                .padding(.bottom,   max(inset.bottom, 4))

                // Left + Right control columns
                HStack(spacing: 0) {
                    LeftControlColumn(screenSize: geo.size, onAction: handleGamepadAction)
                    Spacer(minLength: 0)
                    RightControlColumn(screenSize: geo.size, onAction: handleGamepadAction)
                }
                .padding(.leading,  inset.leading  + hPad)
                .padding(.trailing, inset.trailing + hPad)
                .padding(.top,      max(inset.top,    4) + 56)
                .padding(.bottom,   max(inset.bottom, 4) + 40)

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

                // In-game menu modal
                if showMenu {
                    InGameMenuView(
                        rom: rom,
                        onExit: onExit,
                        onDismiss: { showMenu = false }
                    ) { msg in
                        showToast(msg)
                    }
                }

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

                Text("Emülatör çekirdeği yüklenemedi")
                    .font(.headline).bold()
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("\(rom.console.rawValue) için Libretro çekirdeği (\(rom.console.coreIdentifier)) henüz uygulamaya gömülü değil.\n\nROM kütüphanen sorunsuz, ancak gerçek emülasyon için core .dylib dosyalarını uygulamaya eklemen gerekiyor.\n\nŞu an Coilpede demosu sorunsuz oynanır.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)

                Button(action: onExit) {
                    Text("Kütüphaneye dön")
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

    func makeUIViewController(context: Context) -> MetalGameViewController {
        let vc = MetalGameViewController()
        vc.rom = rom
        return vc
    }

    func updateUIViewController(_ uiViewController: MetalGameViewController, context: Context) {}
}

// MARK: - Metal View Controller

final class MetalGameViewController: UIViewController {
    var rom: ROMEntry?

    private var mtkView: MTKView!
    private var renderer: MetalRenderer!
    private var displayLink: CADisplayLink?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupMetal()
        startEmulation()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        displayLink?.invalidate()
        AudioEngine.shared.stop()
        GameControllerManager.shared.onAction = nil
        CoreBridgeWrapper.shared.stopCore()
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

        // Tell SwiftUI parent so it can render an error overlay.
        NotificationCenter.default.post(
            name: ok ? .remuCoreLoaded : .remuCoreLoadFailed,
            object: rom.console.coreIdentifier
        )

        guard ok else { return }   // don't bother starting frame loop if no core

        // CoreBridge calls back on each video frame; we drive MTKView from there.
        CoreBridgeWrapper.shared.onVideoFrame = { [weak self] pixelBuffer in
            self?.renderer.update(with: pixelBuffer)
            self?.mtkView.draw()
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
        CoreBridgeWrapper.shared.runFrame()
    }
}

// MARK: - Metal Renderer

final class MetalRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState!
    private var texture: MTLTexture?
    private var vertexBuffer: MTLBuffer!

    // Capacity: 4 vertices × (xy + uv) × 4 bytes — re-written each draw call to
    // keep the game letterboxed inside the drawable as the device rotates or
    // multitasks. Backed by .storageModeShared so we can memcpy directly.
    private static let kVertexFloatCount = 4 * 4

    init(device: MTLDevice, view: MTKView) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        super.init()
        buildPipeline(view: view)
        vertexBuffer = device.makeBuffer(
            length: Self.kVertexFloatCount * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )
    }

    /// Recompute clip-space corners for an aspect-fit quad so the game
    /// pixels keep their native ratio (SNES 256×224 → ~8:7) regardless of
    /// the iPhone/iPad display they're rendered on. The letterbox / pillarbox
    /// area falls back to the MTKView's clear color (black).
    private func updateVertexBuffer(viewSize: CGSize, textureWidth: Int, textureHeight: Int) {
        guard viewSize.width > 0, viewSize.height > 0,
              textureWidth > 0, textureHeight > 0 else { return }

        let viewAR = Float(viewSize.width)  / Float(viewSize.height)
        let texAR  = Float(textureWidth)    / Float(textureHeight)

        var sx: Float = 1
        var sy: Float = 1
        if texAR > viewAR {
            // Game is wider than the view — fit width, letterbox top/bottom.
            sy = viewAR / texAR
        } else {
            // Game is taller (or equal) — fit height, pillarbox left/right.
            sx = texAR / viewAR
        }

        let verts: [Float] = [
            -sx,  sy, 0, 0,
             sx,  sy, 1, 0,
            -sx, -sy, 0, 1,
             sx, -sy, 1, 1,
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

        // Aspect-fit the game inside whatever drawable size the OS gave us.
        updateVertexBuffer(
            viewSize: view.drawableSize,
            textureWidth: texture.width,
            textureHeight: texture.height
        )

        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
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
        vertex Fragment vert(uint vid [[vertex_id]], constant float4* v [[buffer(0)]]) {
            Fragment out;
            out.pos = float4(v[vid].xy, 0, 1);
            out.uv = v[vid].zw;
            return out;
        }
        fragment float4 frag(Fragment in [[stage_in]], texture2d<float> tex [[texture(0)]]) {
            constexpr sampler s(filter::linear);
            return tex.sample(s, in.uv);
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
    let onMessage: (String) -> Void

    var body: some View {
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
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.15)))
            )
        }
    }

    private var menuHeader: some View {
        VStack(spacing: 4) {
            Text(rom.title)
                .font(.headline)
                .foregroundColor(.white)
            Text(rom.console.rawValue)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(16)
    }

    private var menuActions: some View {
        VStack(spacing: 0) {
            menuButton("Save State", icon: "arrow.down.circle") {
                performSave()
            }
            menuButton("Load State", icon: "arrow.up.circle") {
                performLoad()
            }
            Divider().background(Color.white.opacity(0.1))
            menuButton("Exit to Library", icon: "house", tint: .red) {
                onExit()
            }
        }
        .padding(.vertical, 8)
    }

    private func menuButton(
        _ title: String,
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
            onMessage("Save failed")
            return
        }
        do {
            _ = try SaveStateManager.shared.saveState(romID: rom.id, stateData: data)
            onMessage("State saved")
        } catch {
            onMessage("Save error: \(error.localizedDescription)")
        }
        onDismiss()
    }

    private func performLoad() {
        do {
            guard let data = try SaveStateManager.shared.loadLatestState(for: rom.id) else {
                onMessage("No save found")
                return
            }
            CoreBridgeWrapper.shared.deserializeState(data)
            onMessage("State loaded")
        } catch {
            onMessage("Load error")
        }
        onDismiss()
    }
}
