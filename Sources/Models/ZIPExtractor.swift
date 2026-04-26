import Foundation
import Compression

// MARK: - Minimal ZIP Reader
//
// A small, dependency-free ZIP reader that supports the only two
// compression methods that show up in 99 % of ROM packages:
//   • method 0  — Stored (no compression)
//   • method 8  — Deflate  (decompressed via Apple's `compression` API)
//
// We don't need to handle ZIP64, encryption, multi-disk archives, etc.
// — the goal is to extract a ROM file the user just downloaded.

enum ZIPExtractor {

    struct Entry {
        let filename: String
        let isDirectory: Bool
        let compressedSize: Int
        let uncompressedSize: Int
        let method: UInt16
        let localHeaderOffset: Int
    }

    enum ZIPError: Error {
        case notAZIP
        case unsupportedMethod(UInt16)
        case truncated
        case decompressionFailed
    }

    // Signatures (little-endian on disk)
    private static let endOfCentralDir: UInt32  = 0x06054b50
    private static let centralDirHeader: UInt32 = 0x02014b50
    private static let localFileHeader: UInt32  = 0x04034b50

    // MARK: - Public API

    /// Returns the central-directory entries for the given ZIP file.
    static func entries(in url: URL) throws -> [Entry] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try entries(in: data)
    }

    static func entries(in data: Data) throws -> [Entry] {
        guard let eocd = locateEndOfCentralDirectory(in: data) else {
            throw ZIPError.notAZIP
        }

        let totalEntries = Int(read16(data, at: eocd + 10))
        let centralDirSize = Int(read32(data, at: eocd + 12))
        let centralDirOffset = Int(read32(data, at: eocd + 16))

        guard centralDirOffset + centralDirSize <= data.count else {
            throw ZIPError.truncated
        }

        var result: [Entry] = []
        result.reserveCapacity(totalEntries)
        var cursor = centralDirOffset

        for _ in 0..<totalEntries {
            guard cursor + 46 <= data.count,
                  read32(data, at: cursor) == centralDirHeader else {
                throw ZIPError.truncated
            }

            let method = read16(data, at: cursor + 10)
            let compressedSize   = Int(read32(data, at: cursor + 20))
            let uncompressedSize = Int(read32(data, at: cursor + 24))
            let nameLen    = Int(read16(data, at: cursor + 28))
            let extraLen   = Int(read16(data, at: cursor + 30))
            let commentLen = Int(read16(data, at: cursor + 32))
            let localOffset = Int(read32(data, at: cursor + 42))

            let nameStart = cursor + 46
            let nameEnd   = nameStart + nameLen
            guard nameEnd <= data.count else { throw ZIPError.truncated }

            let filename = String(data: data[nameStart..<nameEnd], encoding: .utf8)
                ?? String(data: data[nameStart..<nameEnd], encoding: .ascii)
                ?? ""

            let entry = Entry(
                filename: filename,
                isDirectory: filename.hasSuffix("/"),
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                method: method,
                localHeaderOffset: localOffset
            )
            result.append(entry)

            cursor = nameEnd + extraLen + commentLen
        }

        return result
    }

    /// Decompresses the given entry's data from the ZIP archive `data`.
    static func extract(_ entry: Entry, from data: Data) throws -> Data {
        // Local file header layout: 30 bytes fixed + name + extra + payload.
        let lf = entry.localHeaderOffset
        guard lf + 30 <= data.count,
              read32(data, at: lf) == localFileHeader else {
            throw ZIPError.truncated
        }

        let nameLen  = Int(read16(data, at: lf + 26))
        let extraLen = Int(read16(data, at: lf + 28))
        let payloadStart = lf + 30 + nameLen + extraLen
        let payloadEnd   = payloadStart + entry.compressedSize

        guard payloadEnd <= data.count else { throw ZIPError.truncated }
        let payload = data[payloadStart..<payloadEnd]

        switch entry.method {
        case 0:                                    // Stored
            return Data(payload)
        case 8:                                    // Deflate
            return try inflate(
                payload: payload,
                expected: entry.uncompressedSize
            )
        default:
            throw ZIPError.unsupportedMethod(entry.method)
        }
    }

    /// Convenience: extracts the FIRST entry whose extension matches the
    /// given list (case-insensitive). Returns the URL of the file written
    /// to `destinationDirectory`.
    @discardableResult
    static func extractFirstMatch(
        from zipURL: URL,
        extensions: Set<String>,
        into destinationDirectory: URL
    ) throws -> URL? {
        let data = try Data(contentsOf: zipURL, options: .mappedIfSafe)
        let entries = try entries(in: data)

        let allowed = Set(extensions.map { $0.lowercased() })
        let candidate = entries.first { e in
            !e.isDirectory &&
            allowed.contains(
                (e.filename as NSString).pathExtension.lowercased()
            )
        }

        guard let entry = candidate else { return nil }

        try FileManager.default.createDirectory(
            at: destinationDirectory, withIntermediateDirectories: true
        )

        let payload = try extract(entry, from: data)
        let outURL = destinationDirectory.appendingPathComponent(
            (entry.filename as NSString).lastPathComponent
        )
        try payload.write(to: outURL)
        return outURL
    }

    // MARK: - Helpers

    private static func locateEndOfCentralDirectory(in data: Data) -> Int? {
        // EOCD record is 22 bytes minimum and lives near the very end.
        // The trailing comment (up to 64 KB) means we have to scan back.
        let minSize = 22
        guard data.count >= minSize else { return nil }
        let scanStart = max(0, data.count - 65557)
        var i = data.count - minSize
        while i >= scanStart {
            if read32(data, at: i) == endOfCentralDir { return i }
            i -= 1
        }
        return nil
    }

    private static func read16(_ data: Data, at offset: Int) -> UInt16 {
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func read32(_ data: Data, at offset: Int) -> UInt32 {
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    /// Raw deflate decompression via Apple's Compression framework.
    private static func inflate(payload: Data, expected: Int) throws -> Data {
        var output = Data(count: max(expected, 64))
        let outCapacity = output.count
        let inSize      = payload.count

        let result: Int = output.withUnsafeMutableBytes { outRaw -> Int in
            payload.withUnsafeBytes { inRaw -> Int in
                guard let outPtr = outRaw.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let inPtr  = inRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return -1
                }
                return compression_decode_buffer(
                    outPtr, outCapacity,
                    inPtr,  inSize,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard result > 0 else { throw ZIPError.decompressionFailed }
        return output.prefix(result)
    }
}
