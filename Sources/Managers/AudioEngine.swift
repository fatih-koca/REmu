import Foundation
import AVFoundation

/// Libretro core'undan gelen 16-bit stereo interleaved audio sample'ları
/// AVAudioEngine üzerinden iOS speaker'a yönlendirir.
final class AudioEngine {
    static let shared = AudioEngine()

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let sampleRate: Double = 44100
    private let channels: AVAudioChannelCount = 2

    private let ringBuffer = RingBuffer(capacity: 44100 * 2 * 4)   // ~4 saniye buffer
    private var isRunning = false

    private init() {
        self.format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        )!
    }

    // MARK: Lifecycle

    func start() {
        guard !isRunning else { return }

        configureAudioSession()

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            playerNode.play()
            isRunning = true
            registerCoreCallback()
        } catch {
            print("[AudioEngine] start failed: \(error)")
        }
    }

    func stop() {
        guard isRunning else { return }
        playerNode.stop()
        engine.stop()
        ringBuffer.reset()
        isRunning = false
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
    private func enqueue(samples: UnsafePointer<Int16>, frames: Int) {
        let totalSamples = frames * 2   // stereo
        ringBuffer.write(samples: samples, count: totalSamples)
        schedulePlayback(frames: frames)
    }

    private func schedulePlayback(frames: Int) {
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frames)
        ) else { return }
        buffer.frameLength = AVAudioFrameCount(frames)

        guard
            let leftChannel  = buffer.floatChannelData?[0],
            let rightChannel = buffer.floatChannelData?[1]
        else { return }

        // int16 interleaved → float32 planar, normalize to [-1, 1]
        var temp = [Int16](repeating: 0, count: frames * 2)
        let read = ringBuffer.read(into: &temp, count: frames * 2)
        guard read == frames * 2 else { return }

        for i in 0..<frames {
            leftChannel[i]  = Float(temp[i * 2])     / 32767.0
            rightChannel[i] = Float(temp[i * 2 + 1]) / 32767.0
        }

        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }

    // MARK: Session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredSampleRate(sampleRate)
            try session.setPreferredIOBufferDuration(0.005)   // ~5ms low latency
            try session.setActive(true)
        } catch {
            print("[AudioEngine] session error: \(error)")
        }
    }
}

// MARK: - Lock-free Ring Buffer (audio thread safe)

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
                readIndex = (readIndex + 1) % capacity   // overflow → drop oldest
            }
        }
    }

    func read(into dest: inout [Int16], count: Int) -> Int {
        lock.lock(); defer { lock.unlock() }
        var copied = 0
        while copied < count && readIndex != writeIndex {
            dest[copied] = buffer[readIndex]
            readIndex = (readIndex + 1) % capacity
            copied += 1
        }
        return copied
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        readIndex = 0
        writeIndex = 0
    }
}
