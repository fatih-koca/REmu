import Foundation
import AVFoundation

/// Streams 16-bit stereo interleaved audio coming from a Libretro core into
/// AVAudioEngine. Designed around a pull-based AVAudioSourceNode (the right
/// shape for emulator audio): the engine calls our render block on the
/// real-time audio thread and we hand it the samples the core most recently
/// produced. This avoids the per-batch `scheduleBuffer` scheduler — which
/// produced the click/jitter we hit earlier — and gives a clean, deterministic
/// teardown: stopping the engine immediately silences the speaker instead of
/// playing out a queue of already-scheduled buffers.
final class AudioEngine {
    static let shared = AudioEngine()

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let channels: AVAudioChannelCount = 2

    /// Resolved per-core after `start()`. 0 before the first core loads.
    private(set) var sampleRate: Double = 0

    private var format: AVAudioFormat!
    private var ringBuffer: RingBuffer!
    private var isRunning = false

    private init() {}

    // MARK: Lifecycle

    /// Call AFTER `CoreBridgeWrapper.shared.loadCore(...)` succeeds — `start()`
    /// reads the core's native sample rate at this moment.
    func start() {
        guard !isRunning else { return }

        let native = rn_audio_sample_rate()
        sampleRate = native > 0 ? native : 44_100

        guard let fmt = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        ) else {
            print("[AudioEngine] could not build AVAudioFormat for \(sampleRate) Hz")
            return
        }
        self.format = fmt

        // ~2 s of stereo headroom (sampleRate × 2 channels × 2 seconds).
        // Larger than strictly needed for steady-state, but iOS can stall the
        // main thread for ~1 s during a screenshot capture — bigger buffer
        // means the AVAudioSourceNode keeps pulling real samples through that
        // window instead of falling through to silence.
        ringBuffer = RingBuffer(capacity: Int(sampleRate * 4))

        configureAudioSession()

        // Pull-based source: AVAudioEngine asks us for `frameCount` frames on
        // the audio render thread; we copy them out of the ring buffer. If
        // we're underrun (the core hasn't produced enough yet) we fill the
        // remainder with silence — a brief duck rather than the click-storm
        // that scheduling-based playback produced.
        let source = AVAudioSourceNode(format: fmt) { [weak self] _, _, frameCount, abl -> OSStatus in
            guard let self else { return noErr }
            let bufferList = UnsafeMutableAudioBufferListPointer(abl)
            let n = Int(frameCount)

            let leftRaw  = bufferList[0].mData?.assumingMemoryBound(to: Float.self)
            let rightRaw = bufferList[1].mData?.assumingMemoryBound(to: Float.self)

            // Pull stereo-interleaved int16s out of the ring buffer.
            let pulled = self.ringBuffer.copyOut(maxSamples: n * 2)

            let actualFrames = pulled.count / 2
            if let leftRaw, let rightRaw {
                for i in 0..<actualFrames {
                    leftRaw[i]  = Float(pulled[i * 2])     / 32767.0
                    rightRaw[i] = Float(pulled[i * 2 + 1]) / 32767.0
                }
                // Pad trailing frames with silence on underrun.
                if actualFrames < n {
                    for i in actualFrames..<n {
                        leftRaw[i]  = 0
                        rightRaw[i] = 0
                    }
                }
            }
            return noErr
        }

        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: fmt)
        sourceNode = source

        do {
            try engine.start()
            isRunning = true
            registerCoreCallback()
        } catch {
            print("[AudioEngine] start failed: \(error)")
        }
    }

    func stop() {
        guard isRunning else { return }

        // Mark stopped FIRST so any in-flight enqueue() bails before touching
        // the buffer we're about to tear down.
        isRunning = false

        // Detach the registered libretro audio callback so a stale retro_run
        // can't call back into a half-torn-down engine.
        rn_set_audio_callback(nil, nil)

        engine.stop()
        if let sourceNode {
            engine.detach(sourceNode)
        }
        sourceNode = nil
        ringBuffer?.reset()

        // Release the audio session so other apps regain control immediately
        // (and so we don't keep "playing" silently in the background).
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Core → Audio pipeline

    private func registerCoreCallback() {
        rn_set_audio_callback({ samples, frameCount, ud in
            guard let samples, let ud else { return }
            let engine = Unmanaged<AudioEngine>.fromOpaque(ud).takeUnretainedValue()
            engine.enqueue(samples: samples, frames: Int(frameCount))
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    /// Called by Libretro on each audio batch (int16 stereo interleaved).
    /// Runs on whatever thread the core's run loop is on (currently main).
    private func enqueue(samples: UnsafePointer<Int16>, frames: Int) {
        guard isRunning, let ringBuffer else { return }
        ringBuffer.write(samples: samples, count: frames * 2)
    }

    // MARK: Session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default,
                                    options: [.mixWithOthers])
            // Don't fight the device's native rate — AVAudioEngine's mixer
            // resamples between our format (e.g. 32040 Hz for SNES) and the
            // hardware rate (typically 48 kHz). Setting setPreferredSampleRate
            // here causes audible reconfiguration glitches on rate-mismatched
            // cores like SNES9x.
            try session.setPreferredIOBufferDuration(0.020)   // ~20 ms — robust under mild jitter
            try session.setActive(true)
        } catch {
            print("[AudioEngine] session error: \(error)")
        }
    }
}

// MARK: - Ring buffer (single-producer / single-consumer, locked)

private final class RingBuffer {
    private var buffer: [Int16]
    private let capacity: Int
    private var readIndex = 0
    private var writeIndex = 0
    private let lock = NSLock()

    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = [Int16](repeating: 0, count: capacity)
    }

    func write(samples: UnsafePointer<Int16>, count: Int) {
        lock.lock(); defer { lock.unlock() }
        for i in 0..<count {
            buffer[writeIndex] = samples[i]
            writeIndex = (writeIndex + 1) % capacity
            if writeIndex == readIndex {
                // Overflow → advance read so we drop oldest, never block writer.
                readIndex = (readIndex + 1) % capacity
            }
        }
    }

    /// Atomically pull up to `maxSamples` samples; returns however many were
    /// actually available. Empty array on underrun (the source node will pad
    /// with silence). The lock here is brief — a memcpy at worst — and held
    /// on the audio thread for tens of microseconds in practice.
    func copyOut(maxSamples: Int) -> [Int16] {
        lock.lock(); defer { lock.unlock() }
        let available: Int = {
            if writeIndex >= readIndex { return writeIndex - readIndex }
            return capacity - readIndex + writeIndex
        }()
        let n = min(available, maxSamples)
        guard n > 0 else { return [] }

        var out = [Int16](repeating: 0, count: n)
        for i in 0..<n {
            out[i] = buffer[readIndex]
            readIndex = (readIndex + 1) % capacity
        }
        return out
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        readIndex = 0
        writeIndex = 0
    }
}
