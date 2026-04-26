import Foundation
import UniformTypeIdentifiers

// MARK: - Console System

enum ConsoleSystem: String, Codable, CaseIterable {
    case ps1       = "PlayStation"
    case ps2       = "PlayStation 2"
    case n64       = "Nintendo 64"
    case gamecube  = "GameCube"
    case psp       = "PSP"

    var fileExtensions: [String] {
        switch self {
        case .ps1:      return ["bin", "cue", "iso", "img"]
        case .ps2:      return ["iso", "bin"]
        case .n64:      return ["z64", "n64", "v64"]
        case .gamecube: return ["iso", "gcm", "gcz"]
        case .psp:      return ["iso", "cso", "pbp"]
        }
    }

    var coreIdentifier: String {
        switch self {
        case .ps1:      return "mednafen_psx"
        case .ps2:      return "pcsx2"
        case .n64:      return "mupen64plus_next"
        case .gamecube: return "dolphin"
        case .psp:      return "ppsspp"
        }
    }

    var systemIcon: String {
        switch self {
        case .ps1:      return "gamecontroller.fill"
        case .ps2:      return "gamecontroller"
        case .n64:      return "cube.fill"
        case .gamecube: return "cube"
        case .psp:      return "rectangle.fill"
        }
    }
}

// MARK: - ROM Entry

struct ROMEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var console: ConsoleSystem
    var filePath: URL
    var lastPlayed: Date?
    var hasSaveState: Bool

    init(title: String, console: ConsoleSystem, filePath: URL) {
        self.id = UUID()
        self.title = title
        self.console = console
        self.filePath = filePath
        self.hasSaveState = false
    }
}

// MARK: - ROM Library (Persistence)

final class ROMLibrary: ObservableObject {
    static let shared = ROMLibrary()
    @Published var roms: [ROMEntry] = []

    private let persistenceURL: URL = {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("library.json")
    }()

    private init() { load() }

    func add(_ rom: ROMEntry) {
        guard !roms.contains(where: { $0.filePath == rom.filePath }) else { return }
        roms.append(rom)
        save()
    }

    func remove(_ rom: ROMEntry) {
        roms.removeAll { $0.id == rom.id }
        save()
    }

    static func detectConsole(for url: URL) -> ConsoleSystem? {
        let ext = url.pathExtension.lowercased()
        return ConsoleSystem.allCases.first { $0.fileExtensions.contains(ext) }
    }

    // MARK: - Import (used by both DocumentPicker and onOpenURL)
    //
    // Copies the source file into Documents/ROMs/ and registers it.
    // Works for both security-scoped URLs (Files.app) and regular URLs
    // (Safari "Open in" flow that drops the file into our tmp inbox).

    @discardableResult
    func importROM(from sourceURL: URL) -> ROMEntry? {
        let needsScope = sourceURL.startAccessingSecurityScopedResource()
        defer { if needsScope { sourceURL.stopAccessingSecurityScopedResource() } }

        let romsDir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ROMs")
        try? FileManager.default.createDirectory(
            at: romsDir, withIntermediateDirectories: true
        )

        // ── ZIP / 7z handling ─────────────────────────────────────────
        // If the user picked a .zip, we extract the FIRST file inside
        // whose extension matches a known console. .7z is not supported
        // (no built-in iOS decoder) — we surface a log so the user knows.
        let ext = sourceURL.pathExtension.lowercased()
        let workingURL: URL

        if ext == "zip" {
            let allKnownExt = Set(ConsoleSystem.allCases
                                    .flatMap { $0.fileExtensions })
            do {
                guard let extracted = try ZIPExtractor.extractFirstMatch(
                    from: sourceURL,
                    extensions: allKnownExt,
                    into: romsDir
                ) else {
                    NSLog("REmu import: ZIP contains no recognised ROM extension")
                    return nil
                }
                workingURL = extracted
            } catch {
                NSLog("REmu import: ZIP extraction failed: \(error)")
                return nil
            }
        } else if ext == "7z" || ext == "rar" {
            NSLog("REmu import: \(ext.uppercased()) is not supported — please " +
                  "extract the ROM and import it as a regular file")
            return nil
        } else {
            // Plain ROM file — just copy into our ROMs directory.
            let targetURL = romsDir.appendingPathComponent(sourceURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: targetURL.path) == false {
                do {
                    try FileManager.default.copyItem(at: sourceURL, to: targetURL)
                } catch {
                    NSLog("REmu import: copy failed for \(sourceURL.lastPathComponent): \(error)")
                    return nil
                }
            }
            workingURL = targetURL
        }

        guard let console = Self.detectConsole(for: workingURL) else {
            NSLog("REmu import: unsupported extension '\(workingURL.pathExtension)'")
            return nil
        }

        // If the ROM is already in the library, return the existing entry.
        if let existing = roms.first(where: { $0.filePath.path == workingURL.path }) {
            return existing
        }

        let rom = ROMEntry(
            title: workingURL.deletingPathExtension().lastPathComponent,
            console: console,
            filePath: workingURL
        )

        // Library is observed by SwiftUI views, so this update must happen
        // on the main actor.
        if Thread.isMainThread {
            add(rom)
        } else {
            DispatchQueue.main.async { [weak self] in self?.add(rom) }
        }
        return rom
    }

    private func save() {
        if let data = try? JSONEncoder().encode(roms) {
            try? data.write(to: persistenceURL)
        }
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: persistenceURL),
            let decoded = try? JSONDecoder().decode([ROMEntry].self, from: data)
        else { return }
        roms = decoded
    }
}
