import Foundation
import AVFoundation
import os.lock

/// Streams 16-bit stereo interleaved audio coming from a Libretro core into
/// AVAudioEngine. Designed around a pull-based AVAudioSourceNode (the right
/// shape for emulator audio): the engine calls our render block on the
/// real-time audio thread and we hand it the samples the core most recently
/// produced. This avoids the per-batch `scheduleBuffer` scheduler — which
/// produced the click/jitter we hit earlier — and gives a clean, deterministic
/// teardown: stopping the engine immediately silences the speaker instead of
/// playing out a queue of already-scheduled buffers.
///
/// Thread-safety note: producer is the core's main thread, consumer is the
/// real-time audio render thread. The ring buffer uses `os_unfair_lock`
/// (not `NSLock`) so a momentary main-thread stall — e.g. iOS pausing us
/// for ~1 s during a screenshot capture — doesn't trigger the priority
/// inversion that produced an audible crackle.
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

    /// Tracks whether the previous render call ran out of samples. Used to
    /// fade audio in smoothly when the buffer recovers, mirroring the
    /// fade-out we apply when underrun begins. Eliminates the boundary
    /// clicks that show up as "crackle" when the producer stalls.
    private var wasUnderrun = false

    private var interruptionObserver: NSObjectProtocol?

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
        // The render block won't actually run that far ahead; this just
        // gives the producer room to dump a backlog after a stall without
        // overwriting still-unread samples.
        ringBuffer = RingBuffer(capacity: Int(sampleRate * 4))

        configureAudioSession()
        registerInterruptionObserver()

        // Pull-based source: AVAudioEngine asks us for `frameCount` frames on
        // the audio render thread; we copy them out of the ring buffer.
        let source = AVAudioSourceNode(format: fmt) { [weak self] _, _, frameCount, abl -> OSStatus in
            guard let self else { return noErr }
            self.render(frameCount: Int(frameCount), abl: abl)
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
        wasUnderrun = false

        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }

        // Release the audio session so other apps regain control immediately
        // (and so we don't keep "playing" silently in the background).
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Render

    /// Copies samples out of the ring buffer into the audio render block's
    /// output buffers. Smooths the boundary on partial reads:
    ///
    ///   - On underrun (we got fewer samples than requested), the trailing
    ///     padding ramps from the last real sample down to silence over a
    ///     short window instead of jumping to 0 — that step is what the user
    ///     hears as a click during a screenshot stall.
    ///   - On recovery (we WERE underrun and now have samples again), the
    ///     leading frames ramp from 0 up to the real signal so the buffer
    ///     refill doesn't pop either.
    private func render(frameCount n: Int, abl: UnsafeMutablePointer<AudioBufferList>) {
        let bufferList = UnsafeMutableAudioBufferListPointer(abl)
        guard let leftRaw  = bufferList[0].mData?.assumingMemoryBound(to: Float.self),
              let rightRaw = bufferList[1].mData?.assumingMemoryBound(to: Float.self)
        else { return }

        // Pull stereo-interleaved int16s out of the ring buffer.
        let pulled = ringBuffer.copyOut(maxSamples: n * 2)
        let actualFrames = pulled.count / 2

        // Fade-in window if we're recovering from a previous underrun.
        // ~5 ms at the engine's sample rate.
        let fadeInLen = wasUnderrun
            ? min(actualFrames, Int(sampleRate * 0.005))
            : 0

        for i in 0..<actualFrames {
            var l = Float(pulled[i * 2])     / 32767.0
            var r = Float(pulled[i * 2 + 1]) / 32767.0
            if i < fadeInLen {
                let t = Float(i + 1) / Float(fadeInLen + 1)
                l *= t
                r *= t
            }
            leftRaw[i]  = l
            rightRaw[i] = r
        }

        if actualFrames < n {
            // Underrun: ramp the last real sample to silence over a short
            // window, then hold silence for the rest of the requested frames.
            let fadeOutLen = min(n - actualFrames, Int(sampleRate * 0.005))
            let lastL = actualFrames > 0 ? leftRaw[actualFrames - 1]  : 0
            let lastR = actualFrames > 0 ? rightRaw[actualFrames - 1] : 0
            for i in 0..<fadeOutLen {
                let t = Float(i + 1) / Float(fadeOutLen + 1)
                leftRaw[actualFrames + i]  = lastL * (1 - t)
                rightRaw[actualFrames + i] = lastR * (1 - t)
            }
            for i in (actualFrames + fadeOutLen)..<n {
                leftRaw[i]  = 0
                rightRaw[i] = 0
            }
            wasUnderrun = true
        } else {
            wasUnderrun = false
        }
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

    /// Phone calls, FaceTime, Siri, alarms: AVAudioSession sends an
    /// interruption notification. AVAudioEngine pauses on .began but does
    /// not auto-resume on .ended unless we call start() again. Without
    /// this handler the engine stays silent after the interruption clears.
    private func registerInterruptionObserver() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleInterruption(note)
        }
    }

    private func handleInterruption(_ note: Notification) {
        guard
            let info = note.userInfo,
            let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeRaw)
        else { return }

        switch type {
        case .began:
            // Engine auto-pauses; consumer thread will see underruns and
            // ride them out on silence. Nothing to do here.
            break
        case .ended:
            guard
                let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt
            else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            if options.contains(.shouldResume), isRunning {
                try? engine.start()
                wasUnderrun = true   // ramp the recovery in instead of popping
            }
        @unknown default:
            break
        }
    }
}

// MARK: - Ring buffer (single-producer / single-consumer)

/// Single-producer (Libretro main thread) / single-consumer (audio render
/// thread) ring buffer. Uses `os_unfair_lock` rather than `NSLock` because:
///
///   - it's an order of magnitude faster on the audio thread, and
///   - it does not subject the audio thread to the same priority-inversion
///     stalls that `NSLock` does. When the main thread gets paused by iOS
///     (e.g. during a screenshot capture) while holding `NSLock`, the audio
///     render thread blocks on `lock()`, misses its deadline, and the
///     speaker hears a crackle. `os_unfair_lock` minimizes that window.
///
/// True wait-free SPSC with atomics would be ideal, but `os_unfair_lock`
/// closes the audible glitch in practice without pulling in swift-atomics.
private final class RingBuffer {
    private var buffer: [Int16]
    private let capacity: Int
    private var readIndex = 0
    private var writeIndex = 0
    private var lock = os_unfair_lock_s()

    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = [Int16](repeating: 0, count: capacity)
    }

    func write(samples: UnsafePointer<Int16>, count: Int) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
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
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
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
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        readIndex = 0
        writeIndex = 0
    }
}
