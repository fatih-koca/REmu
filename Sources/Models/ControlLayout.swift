import Foundation

// MARK: - Control Layout Model
//
// Drives the PUBG / Brawl-Stars-style touch-control editor. Every on-screen
// control is an independent, freely-positioned item: the user drags it around
// a demo screen and tunes its size / opacity / visibility one by one. Positions
// are stored normalized (0...1 of the screen) so a single saved layout adapts
// across device sizes. The same layout powers both the live in-game overlay and
// the editor — see GameControlsOverlay / ControlLayoutEditorView.

enum ControlKind: String, CaseIterable, Identifiable, Codable {
    case dpad, leftStick, rightStick
    case faceTriangle, faceCross, faceSquare, faceCircle
    case l1, l2, r1, r2
    case start, select, fastForward

    var id: String { rawValue }

    /// Human label shown in the editor's selection panel.
    var displayName: String {
        switch self {
        case .dpad:         return "D-Pad"
        case .leftStick:    return "Left Stick"
        case .rightStick:   return "Right Stick"
        case .faceTriangle: return "Triangle (△)"
        case .faceCross:    return "Cross (✕)"
        case .faceSquare:   return "Square (□)"
        case .faceCircle:   return "Circle (○)"
        case .l1:           return "L1"
        case .l2:           return "L2"
        case .r1:           return "R1"
        case .r2:           return "R2"
        case .start:        return "Start"
        case .select:       return "Select"
        case .fastForward:  return "Fast-Forward"
        }
    }
}

// Per-control placement. x/y are the normalized CENTER of the control.
struct ControlConfig: Codable, Equatable {
    var x: Double          // 0 = left edge, 1 = right edge
    var y: Double          // 0 = top edge,  1 = bottom edge
    var scale: Double      // size multiplier (0.5 ... 1.8)
    var opacity: Double    // 0.2 ... 1.0
    var hidden: Bool
}

struct ControlLayout: Codable, Equatable {
    var configs: [String: ControlConfig]

    subscript(_ kind: ControlKind) -> ControlConfig {
        get { configs[kind.rawValue] ?? ControlLayout.defaultConfig(for: kind) }
        set { configs[kind.rawValue] = newValue }
    }

    // Sensible landscape default mirroring the classic dual-column layout:
    // left thumb gets L2/L1 + stick + D-pad, right thumb gets R2/R1 + stick +
    // face cluster, and Select/Start/FF sit along the bottom center.
    static func defaultConfig(for kind: ControlKind) -> ControlConfig {
        // User-tuned default layout: D-pad + stick on the far-left edge, L2/L1
        // pulled inward; R2/R1 inward on the right, face diamond + stick on the
        // far-right edge; Select/Start/FF across the bottom center.
        let pos: (Double, Double)
        var scale = 1.0
        switch kind {
        case .l2:           pos = (0.283, 0.65)
        case .l1:           pos = (0.283, 0.81)
        case .leftStick:    pos = (0.170, 0.76)
        case .dpad:         pos = (0.170, 0.49); scale = 1.1
        case .r2:           pos = (0.717, 0.65)
        case .r1:           pos = (0.717, 0.81)
        case .rightStick:   pos = (0.830, 0.76)
        case .faceTriangle: pos = (0.830, 0.40)
        case .faceSquare:   pos = (0.780, 0.497)
        case .faceCircle:   pos = (0.880, 0.497)
        case .faceCross:    pos = (0.830, 0.595)
        case .select:       pos = (0.380, 0.88)
        case .start:        pos = (0.500, 0.88)
        case .fastForward:  pos = (0.615, 0.88)
        }
        return ControlConfig(x: pos.0, y: pos.1, scale: scale, opacity: 1.0, hidden: false)
    }

    static var defaultLayout: ControlLayout {
        var configs: [String: ControlConfig] = [:]
        for kind in ControlKind.allCases {
            configs[kind.rawValue] = defaultConfig(for: kind)
        }
        return ControlLayout(configs: configs)
    }
}

// MARK: - Screen Layout Model
//
// The game canvas as a freely-placed rectangle (normalized), plus the aspect
// mode and pixel smoothing. The renderer letterboxes the game inside this rect.

struct ScreenLayout: Codable, Equatable {
    var aspectMode: Int    // 0 = Fit, 1 = Fill, 2 = Integer
    var smooth: Bool
    var x: Double          // normalized rect origin / size (0...1)
    var y: Double
    var width: Double
    var height: Double

    static var defaultLayout: ScreenLayout {
        // User-tuned: centered game band (full height, Fit), sharp pixels.
        ScreenLayout(aspectMode: 0, smooth: false, x: 0.185, y: 0.0, width: 0.63, height: 1.0)
    }
}

// MARK: - Persistence

enum ControlLayoutStore {
    static let key = "remu.controls.layout.v3"

    static func load() -> ControlLayout {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            var layout = try? JSONDecoder().decode(ControlLayout.self, from: data)
        else { return .defaultLayout }
        // Forward-compat: backfill any controls added in a newer build.
        for kind in ControlKind.allCases where layout.configs[kind.rawValue] == nil {
            layout.configs[kind.rawValue] = ControlLayout.defaultConfig(for: kind)
        }
        return layout
    }

    static func save(_ layout: ControlLayout) {
        if let data = try? JSONEncoder().encode(layout) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

enum ScreenLayoutStore {
    static let key = "remu.screen.layout.v3"

    static func load() -> ScreenLayout {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let layout = try? JSONDecoder().decode(ScreenLayout.self, from: data)
        else { return .defaultLayout }
        return layout
    }

    static func save(_ layout: ScreenLayout) {
        if let data = try? JSONEncoder().encode(layout) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
