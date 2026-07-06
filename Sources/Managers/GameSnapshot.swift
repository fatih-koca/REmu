import UIKit

// MARK: - Last-frame capture for save-state thumbnails
//
// The renderer hands every presented frame here (BGRA8, as delivered by the
// libretro core). We keep just the most recent frame in a reusable buffer —
// no per-frame allocation — and build a downscaled UIImage only on demand,
// when a save state is created. Both store() and thumbnail() run on the main
// thread (the display-link tick and UI actions), so no locking is needed.

final class GameSnapshot {
    static let shared = GameSnapshot()
    private init() {}

    private var buffer = [UInt8]()
    private var width = 0
    private var height = 0
    private var rowBytes = 0

    /// Copy the latest frame. Called from the video callback every frame.
    func store(_ frame: PixelBuffer) {
        let w = Int(frame.width)
        let h = Int(frame.height)
        guard w > 0, h > 0, let src = frame.data else { return }
        let pitch = frame.pitch > 0 ? Int(frame.pitch) : w * 4
        let needed = pitch * h
        if buffer.count != needed { buffer = [UInt8](repeating: 0, count: needed) }
        buffer.withUnsafeMutableBytes { dst in
            if let base = dst.baseAddress { memcpy(base, src, needed) }
        }
        width = w; height = h; rowBytes = pitch
    }

    /// A downscaled image of the last frame (≤ maxDim on its long edge), or nil.
    func thumbnail(maxDim: CGFloat = 320) -> UIImage? {
        guard width > 0, height > 0, !buffer.isEmpty else { return nil }
        let w = width, h = height, pitch = rowBytes

        var full: UIImage?
        buffer.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            let info = CGBitmapInfo(rawValue:
                CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            guard let ctx = CGContext(
                data: base, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: pitch,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: info.rawValue
            ), let cg = ctx.makeImage() else { return }
            full = UIImage(cgImage: cg)
        }
        guard let image = full else { return nil }

        let scale = min(maxDim / CGFloat(w), maxDim / CGFloat(h), 1)
        let size = CGSize(width: CGFloat(w) * scale, height: CGFloat(h) * scale)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1; fmt.opaque = true
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
