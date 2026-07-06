import Foundation
import UIKit

// MARK: - Save State

struct SaveState: Codable {
    let romID: UUID
    let timestamp: Date
    let fileName: String
    var screenshotPath: String?     // relative filename, resolved via statesDirectory
    var isAuto: Bool?               // optional for backward-compat decode

    var auto: Bool { isAuto == true }
}

// MARK: - Manager

final class SaveStateManager {
    static let shared = SaveStateManager()
    private init() {}

    private let fm = FileManager.default

    private var statesDirectory: URL {
        documentsURL.appendingPathComponent("SaveStates", isDirectory: true)
    }

    private var systemDirectory: URL {
        documentsURL.appendingPathComponent("System", isDirectory: true)
    }

    private var documentsURL: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func createDirectoriesIfNeeded() {
        [statesDirectory, systemDirectory].forEach {
            try? fm.createDirectory(at: $0, withIntermediateDirectories: true)
        }
    }

    // MARK: Save

    /// Serializes raw core RAM snapshot and writes it to disk, with an optional
    /// thumbnail of the current frame. `stateData` comes from CoreBridge's
    /// retro_serialize(). Auto-saves replace the single previous auto slot so
    /// they don't pile up.
    @discardableResult
    func saveState(romID: UUID, stateData: Data,
                   screenshot: UIImage? = nil, isAuto: Bool = false) throws -> SaveState {
        if isAuto { removeAutoStates(for: romID) }

        let base = "\(romID.uuidString)_\(Int(Date().timeIntervalSince1970))"
        let fileName = base + (isAuto ? ".auto.state" : ".state")
        let fileURL = statesDirectory.appendingPathComponent(fileName)
        try stateData.write(to: fileURL, options: .atomic)

        var shotName: String?
        if let jpeg = screenshot?.jpegData(compressionQuality: 0.7) {
            let name = fileName + ".jpg"
            try? jpeg.write(to: statesDirectory.appendingPathComponent(name), options: .atomic)
            shotName = name
        }

        let state = SaveState(romID: romID, timestamp: Date(),
                              fileName: fileName, screenshotPath: shotName, isAuto: isAuto)
        try persistMetadata(state, romID: romID)
        return state
    }

    /// Resolved on-disk location of a save's thumbnail, if it still exists.
    func screenshotURL(for state: SaveState) -> URL? {
        guard let name = state.screenshotPath else { return nil }
        let url = statesDirectory.appendingPathComponent(name)
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    private func removeAutoStates(for romID: UUID) {
        let autos = ((try? listStates(for: romID)) ?? []).filter { $0.auto }
        autos.forEach { try? deleteState($0) }
    }

    // MARK: Load

    func loadLatestState(for romID: UUID) throws -> Data? {
        let states = try listStates(for: romID)
        guard let latest = states.sorted(by: { $0.timestamp > $1.timestamp }).first else {
            return nil
        }
        let fileURL = statesDirectory.appendingPathComponent(latest.fileName)
        return try Data(contentsOf: fileURL)
    }

    /// Loads a specific save (used by the save-states picker, where the user
    /// chooses which of several saved points to restore).
    func loadState(_ state: SaveState) throws -> Data {
        let fileURL = statesDirectory.appendingPathComponent(state.fileName)
        return try Data(contentsOf: fileURL)
    }

    func listStates(for romID: UUID) throws -> [SaveState] {
        let metaURL = metadataURL(for: romID)
        guard fm.fileExists(atPath: metaURL.path),
              let data = try? Data(contentsOf: metaURL),
              let states = try? JSONDecoder().decode([SaveState].self, from: data)
        else { return [] }
        return states
    }

    // MARK: Delete

    func deleteState(_ state: SaveState) throws {
        let fileURL = statesDirectory.appendingPathComponent(state.fileName)
        try? fm.removeItem(at: fileURL)
        if let shot = state.screenshotPath {
            try? fm.removeItem(at: statesDirectory.appendingPathComponent(shot))
        }
        var states = (try? listStates(for: state.romID)) ?? []
        states.removeAll { $0.fileName == state.fileName }
        let data = try JSONEncoder().encode(states)
        try data.write(to: metadataURL(for: state.romID))
    }

    // MARK: BIOS Check

    func biosExists(named name: String) -> Bool {
        fm.fileExists(atPath: systemDirectory.appendingPathComponent(name).path)
    }

    // MARK: Private

    private func metadataURL(for romID: UUID) -> URL {
        statesDirectory.appendingPathComponent("\(romID.uuidString).meta.json")
    }

    private func persistMetadata(_ state: SaveState, romID: UUID) throws {
        var states = (try? listStates(for: romID)) ?? []
        states.append(state)
        let data = try JSONEncoder().encode(states)
        try data.write(to: metadataURL(for: romID))
    }
}
