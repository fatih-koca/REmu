import Foundation
import UIKit

// MARK: - ROM Artwork Extractor
//
// Best-effort cover-art extraction directly from ROM files. Runs once,
// at import time, and caches the resulting PNG under Documents/Covers/.
// Anything that can't be parsed silently returns nil — the UI falls back
// to the console's system icon.

enum ROMArtworkExtractor {

    /// Tries to pull a cover image out of `romURL` and write it as PNG to
    /// `Documents/Covers/<id>.png`. Returns the saved URL on success.
    /// Synchronous — only checks formats that embed art directly (PSP, GameCube).
    static func extractFromFile(for romURL: URL, console: ConsoleSystem, id: UUID) -> URL? {
        guard let image = readArtwork(from: romURL, console: console) else { return nil }
        return write(image, id: id)
    }

    /// Fetches a cover from the libretro-thumbnails project on GitHub.
    /// Most consoles don't store cover art inside the ROM itself, so for
    /// those (SNES, PS1, N64…) this is the only way to get the artwork
    /// the user saw on the download site.
    static func fetchOnline(
        title: String,
        console: ConsoleSystem,
        id: UUID,
        completion: @escaping (URL?) -> Void
    ) {
        guard let system = console.libretroThumbnailFolder else {
            completion(nil); return
        }
        let candidates = candidateTitles(from: title)
        tryFetch(candidates: candidates, system: system, id: id, completion: completion)
    }

    /// Builds a small ordered list of guesses for the No-Intro filename
    /// libretro-thumbnails uses. The user's ROM may be named loosely
    /// ("Mario World [!]", "super_mario_world.smc", "Super Mario World (U)"),
    /// so we strip GoodTools tags, expand short region codes, and fall
    /// back to common region suffixes.
    private static func candidateTitles(from rawTitle: String) -> [String] {
        let cleaned = clean(rawTitle)
        let regionExpanded = expandRegionCodes(in: cleaned)

        // Title with all (...) and [...] groups removed — useful for
        // appending canonical region suffixes when the source had none
        // or had something like "[!]" only.
        let stripped = stripParenAndBrackets(in: cleaned)
            .trimmingCharacters(in: .whitespaces)

        var seen = Set<String>()
        var out: [String] = []
        func add(_ s: String) {
            let t = s.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, seen.insert(t).inserted else { return }
            out.append(t)
        }

        add(regionExpanded)
        add(cleaned)

        if !stripped.contains("(") {
            for region in ["(USA)", "(Europe)", "(Japan)", "(World)",
                           "(USA, Europe)", "(USA, Japan)"] {
                add("\(stripped) \(region)")
            }
            add(stripped)
        }
        return out
    }

    /// Strip GoodTools-style "[...]" tags and normalise whitespace /
    /// underscores/dots a lot of pirate dumps use instead of spaces.
    private static func clean(_ s: String) -> String {
        var t = s
        // Remove every [..] group.
        while let range = t.range(of: "\\[[^\\]]*\\]", options: .regularExpression) {
            t.removeSubrange(range)
        }
        t = t.replacingOccurrences(of: "_", with: " ")
        // Don't replace dots blindly — file titles like "Mario Bros. 3"
        // legitimately contain them. Only collapse the runs that come
        // from naming schemes like "Super.Mario.World".
        if t.contains(".") && !t.contains(" ") {
            t = t.replacingOccurrences(of: ".", with: " ")
        }
        // Collapse multi-space runs.
        while t.contains("  ") {
            t = t.replacingOccurrences(of: "  ", with: " ")
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// "(U)" → "(USA)", "(E)" → "(Europe)", etc. so a ROM tagged the
    /// old GoodTools way still hits the No-Intro keyed thumbnails.
    private static func expandRegionCodes(in s: String) -> String {
        let replacements: [(String, String)] = [
            ("(U)", "(USA)"),
            ("(E)", "(Europe)"),
            ("(J)", "(Japan)"),
            ("(W)", "(World)"),
            ("(UE)", "(USA, Europe)"),
            ("(JU)", "(Japan, USA)"),
        ]
        var t = s
        for (short, long) in replacements {
            t = t.replacingOccurrences(of: short, with: long)
        }
        return t
    }

    private static func stripParenAndBrackets(in s: String) -> String {
        var t = s
        while let r = t.range(of: "\\([^)]*\\)", options: .regularExpression) {
            t.removeSubrange(r)
        }
        while let r = t.range(of: "\\[[^\\]]*\\]", options: .regularExpression) {
            t.removeSubrange(r)
        }
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        return t
    }

    private static func tryFetch(
        candidates: [String],
        system: String,
        id: UUID,
        completion: @escaping (URL?) -> Void
    ) {
        var remaining = candidates
        guard !remaining.isEmpty else { completion(nil); return }
        let candidate = remaining.removeFirst()

        guard let encoded = candidate.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed),
              let url = URL(
                string: "https://raw.githubusercontent.com/libretro-thumbnails/" +
                        "\(system)/master/Named_Boxarts/\(encoded).png"
              )
        else {
            tryFetch(candidates: remaining, system: system, id: id, completion: completion)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200,
               let data, let image = UIImage(data: data),
               let saved = write(image, id: id) {
                completion(saved)
            } else {
                tryFetch(candidates: remaining, system: system, id: id, completion: completion)
            }
        }.resume()
    }

    static func coversDirectory() -> URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Covers")
    }

    // MARK: Dispatch

    private static func readArtwork(from url: URL, console: ConsoleSystem) -> UIImage? {
        let ext = url.pathExtension.lowercased()
        switch console {
        case .psp where ext == "pbp":
            return PBPReader.icon(at: url)
        case .psp where ext == "iso" || ext == "cso":
            return ISO9660Reader.firstFile(at: url, named: "ICON0.PNG")
                .flatMap(UIImage.init(data:))
        case .gamecube:
            return GameCubeBannerReader.banner(at: url)
        default:
            return nil
        }
    }

    private static func write(_ image: UIImage, id: UUID) -> URL? {
        guard let png = image.pngData() else { return nil }
        let coversDir = coversDirectory()
        try? FileManager.default.createDirectory(
            at: coversDir, withIntermediateDirectories: true
        )
        let target = coversDir.appendingPathComponent("\(id.uuidString).png")
        do {
            try png.write(to: target, options: .atomic)
            return target
        } catch {
            NSLog("REmu artwork: failed to write cover: \(error)")
            return nil
        }
    }
}

// MARK: - libretro-thumbnails system folders

private extension ConsoleSystem {
    var libretroThumbnailFolder: String? {
        switch self {
        case .snes:     return "Nintendo_-_Super_Nintendo_Entertainment_System"
        case .gba:      return "Nintendo_-_Game_Boy_Advance"
        case .ps1:      return "Sony_-_PlayStation"
        case .ps2:      return "Sony_-_PlayStation_2"
        case .gamecube: return "Nintendo_-_GameCube"
        case .psp:      return "Sony_-_PlayStation_Portable"
        }
    }
}

// MARK: - PSP .pbp

/// PBP is a tiny container with a fixed header:
///   offset 0  : 4-byte magic "\x00PBP"
///   offset 4  : 4-byte version
///   offset 8  : 8 little-endian uint32 offsets (PARAM.SFO, ICON0.PNG,
///               ICON1.PMF, PIC0.PNG, PIC1.PNG, SND0.AT3, DATA.PSP, DATA.PSAR)
/// Each section runs from `offsets[i]` to `offsets[i+1]` (or EOF for the
/// last one). We only care about ICON0.PNG, which is index 1.
private enum PBPReader {
    static func icon(at url: URL) -> UIImage? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let header = try? handle.read(upToCount: 40), header.count == 40 else { return nil }
        let magic = header.prefix(4)
        guard magic == Data([0x00, 0x50, 0x42, 0x50]) else { return nil }

        let offsets: [UInt32] = (0..<8).map { i in
            let start = 8 + i * 4
            return header.subdata(in: start..<(start + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }
        }

        let icon0Start = UInt64(offsets[1])
        let icon0End = UInt64(offsets[2])
        guard icon0End > icon0Start else { return nil }

        try? handle.seek(toOffset: icon0Start)
        guard let data = try? handle.read(upToCount: Int(icon0End - icon0Start)),
              !data.isEmpty else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - ISO9660 (PSP discs)

/// Just enough of ISO9660 to find a single named file at the root of a
/// PSP_GAME directory. PSP discs are plain ISO9660 with the icon at
/// `/PSP_GAME/ICON0.PNG`.
private enum ISO9660Reader {

    /// Searches the disc for the first occurrence of a file with the
    /// given (case-insensitive) basename and returns its bytes.
    static func firstFile(at url: URL, named target: String) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        // Primary Volume Descriptor lives at sector 16 (2048-byte sectors).
        try? handle.seek(toOffset: 16 * 2048)
        guard let pvd = try? handle.read(upToCount: 2048), pvd.count == 2048 else { return nil }

        // Type byte must be 1 (PVD), identifier "CD001" at offset 1.
        guard pvd[0] == 1, pvd.subdata(in: 1..<6) == Data("CD001".utf8) else { return nil }

        // Root directory record is 34 bytes at offset 156 of the PVD.
        let rootRecord = pvd.subdata(in: 156..<(156 + 34))
        let rootExtent = readUInt32LE(rootRecord, at: 2)
        let rootSize = readUInt32LE(rootRecord, at: 10)

        return search(
            handle: handle,
            extent: rootExtent,
            size: rootSize,
            target: target.uppercased()
        )
    }

    private static func search(
        handle: FileHandle,
        extent: UInt32,
        size: UInt32,
        target: String,
        depth: Int = 0
    ) -> Data? {
        // ISO9660 directory trees are shallow; cap recursion just in case.
        guard depth < 6 else { return nil }

        try? handle.seek(toOffset: UInt64(extent) * 2048)
        guard let dirData = try? handle.read(upToCount: Int(size)), !dirData.isEmpty else {
            return nil
        }

        var offset = 0
        while offset < dirData.count {
            let length = Int(dirData[offset])
            if length == 0 {
                // Records don't span sector boundaries — jump to next sector.
                let next = ((offset / 2048) + 1) * 2048
                if next >= dirData.count { break }
                offset = next
                continue
            }

            let record = dirData.subdata(in: offset..<(offset + length))
            let childExtent = readUInt32LE(record, at: 2)
            let childSize = readUInt32LE(record, at: 10)
            let flags = record[25]
            let nameLen = Int(record[32])
            guard 33 + nameLen <= record.count else { break }
            let nameBytes = record.subdata(in: 33..<(33 + nameLen))
            let name = String(data: nameBytes, encoding: .ascii) ?? ""

            // Skip "." (0x00) and ".." (0x01) entries.
            let isSpecial = nameLen == 1 && (nameBytes.first == 0x00 || nameBytes.first == 0x01)
            let isDirectory = (flags & 0x02) != 0

            if !isSpecial {
                // Strip ";1" version suffix that ISO9660 appends to file names.
                let trimmed = name.split(separator: ";").first.map(String.init) ?? name
                if !isDirectory, trimmed.uppercased() == target {
                    try? handle.seek(toOffset: UInt64(childExtent) * 2048)
                    return try? handle.read(upToCount: Int(childSize))
                }
                if isDirectory,
                   let hit = search(
                       handle: handle,
                       extent: childExtent,
                       size: childSize,
                       target: target,
                       depth: depth + 1
                   ) {
                    return hit
                }
            }

            offset += length
        }
        return nil
    }
}

// MARK: - GameCube banner (opening.bnr)

/// GameCube discs put a 96x32 banner image inside `opening.bnr` at the
/// root of the FST. Format:
///   offset 0    : magic "BNR1" or "BNR2"
///   offset 0x20 : 96x32 RGB5A3 image (6144 bytes), tiled 4x4 blocks
///
/// We pull the disc's FST out of the GC header (offsets 0x424 / 0x428),
/// scan for "opening.bnr", read the image, decode RGB5A3 to RGBA8.
private enum GameCubeBannerReader {

    private static let bannerWidth = 96
    private static let bannerHeight = 32

    static func banner(at url: URL) -> UIImage? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        // GC header starts with magic 0xC2339F3D at offset 0x1C. (Wii uses
        // a different magic at offset 0x18; we don't try to handle Wii.)
        try? handle.seek(toOffset: 0x1C)
        guard let magicBytes = try? handle.read(upToCount: 4), magicBytes.count == 4 else {
            return nil
        }
        let magic = magicBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        guard magic == 0xC2339F3D else { return nil }

        // FST offset and size live at 0x424 / 0x428 (big-endian).
        try? handle.seek(toOffset: 0x424)
        guard let fstHeader = try? handle.read(upToCount: 8), fstHeader.count == 8 else {
            return nil
        }
        let fstOffset = readUInt32BE(fstHeader, at: 0)
        let fstSize = readUInt32BE(fstHeader, at: 4)
        guard fstSize > 0, fstSize < 16 * 1024 * 1024 else { return nil }

        try? handle.seek(toOffset: UInt64(fstOffset))
        guard let fst = try? handle.read(upToCount: Int(fstSize)), !fst.isEmpty else {
            return nil
        }

        // Root entry (12 bytes): the third uint32 holds total entry count.
        let totalEntries = readUInt32BE(fst, at: 8)
        let stringTableOffset = Int(totalEntries) * 12

        for i in 1..<Int(totalEntries) {
            let recordOffset = i * 12
            guard recordOffset + 12 <= fst.count else { break }
            let typeAndNameOffset = readUInt32BE(fst, at: recordOffset)
            let isDirectory = (typeAndNameOffset >> 24) != 0
            if isDirectory { continue }

            let nameOffset = Int(typeAndNameOffset & 0x00FFFFFF)
            let fileOffset = readUInt32BE(fst, at: recordOffset + 4)
            let fileSize = readUInt32BE(fst, at: recordOffset + 8)

            let nameStart = stringTableOffset + nameOffset
            guard nameStart < fst.count else { continue }
            let name = readNullTerminatedASCII(fst, from: nameStart)
            guard name.lowercased() == "opening.bnr" else { continue }
            guard fileSize >= 0x20 + 6144 else { return nil }

            try? handle.seek(toOffset: UInt64(fileOffset))
            guard let bnr = try? handle.read(upToCount: Int(fileSize)),
                  bnr.count >= 0x20 + 6144 else { return nil }
            let pixelData = bnr.subdata(in: 0x20..<(0x20 + 6144))
            return decodeRGB5A3(pixelData,
                                width: bannerWidth,
                                height: bannerHeight)
        }
        return nil
    }

    /// RGB5A3 is the GameCube's odd 16-bit pixel format, stored in 4x4
    /// tiles. Top bit decides whether the remaining 15 bits encode RGB555
    /// (opaque) or A3RGB444 (with 3-bit alpha).
    private static func decodeRGB5A3(_ data: Data, width: Int, height: Int) -> UIImage? {
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let tileW = 4, tileH = 4
        var idx = 0

        for ty in stride(from: 0, to: height, by: tileH) {
            for tx in stride(from: 0, to: width, by: tileW) {
                for py in 0..<tileH {
                    for px in 0..<tileW {
                        guard idx + 1 < data.count else { return nil }
                        let pixel = (UInt16(data[idx]) << 8) | UInt16(data[idx + 1])
                        idx += 2

                        let r: UInt8, g: UInt8, b: UInt8, a: UInt8
                        if pixel & 0x8000 != 0 {
                            // Opaque RGB555
                            r = expand5(UInt8((pixel >> 10) & 0x1F))
                            g = expand5(UInt8((pixel >> 5) & 0x1F))
                            b = expand5(UInt8(pixel & 0x1F))
                            a = 255
                        } else {
                            // A3 RGB444
                            a = expand3(UInt8((pixel >> 12) & 0x07))
                            r = expand4(UInt8((pixel >> 8) & 0x0F))
                            g = expand4(UInt8((pixel >> 4) & 0x0F))
                            b = expand4(UInt8(pixel & 0x0F))
                        }

                        let x = tx + px
                        let y = ty + py
                        if x < width, y < height {
                            let o = (y * width + x) * 4
                            rgba[o]     = r
                            rgba[o + 1] = g
                            rgba[o + 2] = b
                            rgba[o + 3] = a
                        }
                    }
                }
            }
        }

        return makeUIImage(rgba: rgba, width: width, height: height)
    }

    private static func expand3(_ v: UInt8) -> UInt8 { UInt8((Int(v) * 255 + 3) / 7) }
    private static func expand4(_ v: UInt8) -> UInt8 { UInt8((Int(v) << 4) | Int(v)) }
    private static func expand5(_ v: UInt8) -> UInt8 { UInt8((Int(v) << 3) | (Int(v) >> 2)) }

    private static func makeUIImage(rgba: [UInt8], width: Int, height: Int) -> UIImage? {
        let provider = CGDataProvider(data: Data(rgba) as CFData)
        guard let provider else { return nil }
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        )
        guard let cg = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: cs,
            bitmapInfo: info,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Byte helpers

private func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
    guard offset + 4 <= data.count else { return 0 }
    return data.subdata(in: offset..<(offset + 4)).withUnsafeBytes {
        $0.load(as: UInt32.self)
    }
}

private func readUInt32BE(_ data: Data, at offset: Int) -> UInt32 {
    guard offset + 4 <= data.count else { return 0 }
    return data.subdata(in: offset..<(offset + 4)).withUnsafeBytes {
        $0.load(as: UInt32.self).bigEndian
    }
}

private func readNullTerminatedASCII(_ data: Data, from start: Int) -> String {
    var end = start
    while end < data.count, data[end] != 0 { end += 1 }
    return String(data: data.subdata(in: start..<end), encoding: .ascii) ?? ""
}
