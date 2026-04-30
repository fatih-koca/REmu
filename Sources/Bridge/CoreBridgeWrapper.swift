import Foundation

// Swift-facing singleton that wraps the C CoreBridge API.

typealias PixelBuffer = RNPixelBuffer   // bridged from CoreBridge.h via bridging header

final class CoreBridgeWrapper {
    static let shared = CoreBridgeWrapper()
    private init() {}

    var onVideoFrame: ((PixelBuffer) -> Void)?

    // MARK: Lifecycle

    @discardableResult
    func loadCore(identifier: String, romPath: String) -> Bool {
        rn_set_video_callback({ frame, ud in
            guard let frame, let ud else { return }
            let wrapper = Unmanaged<CoreBridgeWrapper>.fromOpaque(ud).takeUnretainedValue()
            wrapper.onVideoFrame?(frame.pointee)
        }, Unmanaged.passUnretained(self).toOpaque())

        let ok = rn_core_load(identifier, romPath)
        if !ok {
            print("[CoreBridgeWrapper] Failed to load core: \(identifier)")
        }
        return ok
    }

    func startCore()  { rn_core_start() }
    func stopCore()   { rn_core_stop() }
    func resetCore()  { rn_core_reset() }
    func runFrame()   { rn_core_run_frame() }

    // MARK: AV info (populated after a successful loadCore)

    /// Native audio sample rate reported by the core, in Hz. 0 if no core loaded.
    var audioSampleRate: Double { rn_audio_sample_rate() }

    /// Native frame rate reported by the core (e.g. SNES NTSC ≈ 60.0988).
    var videoFPS: Double { rn_video_fps() }

    /// Base output resolution reported by the core after retro_load_game.
    var videoBaseSize: (width: Int, height: Int) {
        (Int(rn_video_base_width()), Int(rn_video_base_height()))
    }

    // MARK: Input

    func handleInput(_ action: GamepadAction) {
        switch action {
        case .leftStick(let x, let y):   rn_input_set_analog(0, x, y)
        case .rightStick(let x, let y):  rn_input_set_analog(1, x, y)
        default: updateButtonMask(action)
        }
    }

    private var buttonMask: UInt32 = 0

    private func updateButtonMask(_ action: GamepadAction) {
        switch action {
        case .cross(let d):    toggle(RN_BTN_CROSS.rawValue, d)
        case .circle(let d):   toggle(RN_BTN_CIRCLE.rawValue, d)
        case .square(let d):   toggle(RN_BTN_SQUARE.rawValue, d)
        case .triangle(let d): toggle(RN_BTN_TRIANGLE.rawValue, d)
        case .l1(let d):       toggle(RN_BTN_L1.rawValue, d)
        case .l2(let d):       toggle(RN_BTN_L2.rawValue, d)
        case .r1(let d):       toggle(RN_BTN_R1.rawValue, d)
        case .r2(let d):       toggle(RN_BTN_R2.rawValue, d)
        case .start(let d):    toggle(RN_BTN_START.rawValue, d)
        case .select(let d):   toggle(RN_BTN_SELECT.rawValue, d)
        case .dpadUp(let d):   toggle(RN_BTN_DPAD_UP.rawValue, d)
        case .dpadDown(let d): toggle(RN_BTN_DPAD_DN.rawValue, d)
        case .dpadLeft(let d): toggle(RN_BTN_DPAD_LT.rawValue, d)
        case .dpadRight(let d):toggle(RN_BTN_DPAD_RT.rawValue, d)
        default: break
        }
        rn_input_set_buttons(buttonMask)
    }

    private func toggle(_ bit: UInt32, _ on: Bool) {
        if on { buttonMask |= bit } else { buttonMask &= ~bit }
    }

    // MARK: Save States

    func serializeState() -> Data? {
        let size = rn_state_size()
        guard size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard rn_state_save(&buffer, size) else { return nil }
        return Data(buffer)
    }

    func deserializeState(_ data: Data) {
        data.withUnsafeBytes { ptr in
            _ = rn_state_load(ptr.baseAddress, data.count)
        }
    }
}
