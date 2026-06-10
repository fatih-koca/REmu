import SwiftUI
import UIKit
import ImageIO

// MARK: - Color hex helper

extension Color {
    init(hex: UInt) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8)  & 0xff) / 255,
                  blue:  Double( hex        & 0xff) / 255,
                  opacity: 1)
    }
}

// MARK: - Per-console theming (accent + badge gradient)

private extension ConsoleSystem {
    var accent: Color { Color(hex: badgeHexes.0) }
    var badgeGradient: [Color] { [Color(hex: badgeHexes.0), Color(hex: badgeHexes.1)] }

    /// Pixel-art console badge asset (in Assets.xcassets).
    var pixelAsset: String {
        switch self {
        case .nes:        return "Console_nes"
        case .snes:       return "Console_snes"
        case .gb:         return "Console_gb"
        case .gbc:        return "Console_gbc"
        case .gba:        return "Console_gba"
        case .genesis:    return "Console_genesis"
        case .sms:        return "Console_sms"
        case .gamegear:   return "Console_gamegear"
        case .pcengine:   return "Console_pcengine"
        case .atari2600:  return "Console_atari2600"
        case .ngpc:       return "Console_ngpc"
        case .wonderswan: return "Console_wonderswan"
        case .ps1:        return "Console_ps1"
        }
    }

    var badgeHexes: (UInt, UInt) {
        switch self {
        case .nes:        return (0xf04357, 0x8c1f2c)
        case .snes:       return (0xa678ff, 0x5b3fd6)
        case .gb:         return (0x9fbd45, 0x54632a)
        case .gbc:        return (0x2fd3d3, 0x176f8a)
        case .gba:        return (0x7b6dff, 0x3a2ea0)
        case .genesis:    return (0x4a8bff, 0x1f3f9c)
        case .sms:        return (0x3f80ff, 0x16357a)
        case .gamegear:   return (0x33b6df, 0x124e66)
        case .pcengine:   return (0xff8a46, 0x9c3f10)
        case .atari2600:  return (0xc78a44, 0x5e3c14)
        case .ngpc:       return (0x7d8496, 0x2c3340)
        case .wonderswan: return (0x97a0b4, 0x2c3340)
        case .ps1:        return (0x9aa2b0, 0x3c424f)
        }
    }
}

// MARK: - Home model

private struct HomeGame: Identifiable {
    let id: String
    let title: String
    let rom: ROMEntry?          // nil == built-in demo
    var isDemo: Bool { rom == nil }
}

private struct HomeSection: Identifiable {
    let id: String
    let title: String
    let badgeSymbol: String
    let accent: Color
    let gradient: [Color]
    let games: [HomeGame]
    let console: ConsoleSystem?
    var isEmptyConsole: Bool { console != nil && games.isEmpty }
    var count: Int { games.count }
}

// MARK: - Async cover loader
//
// Decodes cover art fully OFF the main thread. UIImage(contentsOfFile:) only
// memory-maps the file — the expensive PNG decompression normally happens
// lazily on the MAIN thread the first time Core Animation composites the
// image (= the first swipe). ImageIO's thumbnail API with
// ShouldCacheImmediately forces the decode (downsampled to the largest size a
// card ever draws) inside the background queue, so the main thread only ever
// touches ready-to-draw bitmaps. Completion-based: a finished load invalidates
// just the one card that asked, never the whole screen.

private final class CoverStore {
    static let shared = CoverStore()

    private var cache: [String: UIImage] = [:]
    private var pending: [String: [(UIImage?) -> Void]] = [:]
    private let queue = DispatchQueue(label: "remu.covers", qos: .userInitiated, attributes: .concurrent)
    // Largest rendered cover: cardBase ≤ 172pt × 1.16 focal scale, in pixels.
    private let maxPixel = Int(ceil(172 * 1.16 * UIScreen.main.scale))

    /// Synchronous cache hit (main thread).
    func cached(_ path: String?) -> UIImage? {
        guard let path else { return nil }
        return cache[path]
    }

    /// Async load; completion fires on the main thread (immediately on a hit).
    func load(_ path: String?, completion: ((UIImage?) -> Void)? = nil) {
        guard let path else { completion?(nil); return }
        if let img = cache[path] { completion?(img); return }
        if pending[path] != nil {                       // already in flight
            if let completion { pending[path]?.append(completion) }
            return
        }
        pending[path] = completion.map { [$0] } ?? []
        let maxPx = maxPixel
        queue.async { [weak self] in
            let img = Self.decode(path, maxPixel: maxPx)
            DispatchQueue.main.async {
                guard let self else { return }
                if let img { self.cache[path] = img }
                (self.pending.removeValue(forKey: path) ?? []).forEach { $0(img) }
            }
        }
    }

    /// Warm the cache in the background so first swipes composite instantly.
    func preload(_ paths: [String]) { paths.forEach { load($0) } }

    private static func decode(_ path: String, maxPixel: Int) -> UIImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let src = CGImageSourceCreateWithURL(url, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        else { return UIImage(contentsOfFile: path) }
        return UIImage(cgImage: cg)
    }
}

/// One card's cover: shows the placeholder until its bitmap is decoded, then
/// swaps in. Holds its OWN @State so a finished load re-renders exactly this
/// card — not the whole home screen.
private struct CoverImage<Placeholder: View>: View {
    let path: String?
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                // Box art comes in many aspect ratios (NES portrait, SNES
                // landscape…). Never crop it: fit the full cover and fill the
                // leftover space with a blurred copy of itself. The blur is
                // rendered once per cover and cached by Core Animation —
                // drags only transform the layer, so this costs nothing per frame.
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                    .blur(radius: 14, opaque: true)
                    .overlay(Color.black.opacity(0.22))
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                placeholder()
                    .onAppear {
                        if let hit = CoverStore.shared.cached(path) { image = hit }
                        else { CoverStore.shared.load(path) { image = $0 } }
                    }
            }
        }
    }
}

// MARK: - Transposed-XMB Home
//
// Performance architecture: the two carousels own their drag @State, so a drag
// frame re-evaluates ONLY the moving carousel — never the gradient background,
// the .ultraThinMaterial column, the top bar, or the other carousel. (When the
// drag state lived on this root view, every onChanged tick re-ran the entire
// body; the cold first invalidation of that huge tree was the first-swipe
// stutter.)

struct XMBHomeView: View {
    @ObservedObject var library: ROMLibrary
    var onPlayROM:     (ROMEntry) -> Void
    var onPlayDemo:    () -> Void
    var onOpenTutorial:() -> Void
    var onOpenSettings:() -> Void
    var onImport:      () -> Void

    @State private var selectedIndex = 0          // focused console (Demo Games on launch)

    // TRUE safe-area insets from the key window, cached. Device-accurate in
    // real landscape (GeometryReader/simulator report different values), and
    // reading it once avoids walking UIApplication.connectedScenes on every
    // body evaluation. Refreshed on size changes.
    @State private var insets: UIEdgeInsets = XMBHomeView.readWindowInsets()

    // Canvas size (set from the GeometryReader). All metrics below are
    // PROPORTIONAL to it so the layout stays balanced on every iPhone/iPad.
    @State private var canvasW: CGFloat = 780
    @State private var canvasH: CGFloat = 380

    private var columnInnerW: CGFloat { min(canvasW * 0.305, 280) }   // panel inner width
    private var rowSelW:      CGFloat { columnInnerW - 2 }            // selected reaches ~panel right edge
    private var rowNormalW:   CGFloat { rowSelW - 30 }
    private var slotHeight:   CGFloat { max(canvasH * 0.150, 44) }    // vertical row spacing

    // Game carousel
    private var cardBase: CGFloat { min(canvasW * 0.152, 172) }       // card width (scale is visual)
    private var gameGap:  CGFloat { canvasW * 0.026 }
    private var gameSlot:  CGFloat { cardBase + gameGap }

    private static func readWindowInsets() -> UIEdgeInsets {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        return (windows.first { $0.isKeyWindow } ?? windows.first)?.safeAreaInsets ?? .zero
    }

    // MARK: Sections (Demo pinned → consoles by game count desc → empty consoles)

    // Cached so we don't regroup/sort the library on every body evaluation.
    @State private var cachedSections: [HomeSection] = []
    private var sections: [HomeSection] { cachedSections.isEmpty ? computeSections() : cachedSections }

    private func computeSections() -> [HomeSection] {
        var out: [HomeSection] = [
            HomeSection(id: "demo",
                        title: NSLocalizedString("Demo Games", comment: "Home: pinned demo section title"),
                        badgeSymbol: "sparkles",
                        accent: Color(hex: 0x3ddd86),
                        gradient: [Color(hex: 0x3ddd86), Color(hex: 0xf5a623)],
                        games: [HomeGame(id: "glowchase", title: "Glowchase", rom: nil)],
                        console: nil)
        ]
        let grouped = Dictionary(grouping: library.roms, by: { $0.console })
        let order = ConsoleSystem.allCases
        func idx(_ c: ConsoleSystem) -> Int { order.firstIndex(of: c) ?? 0 }

        let withGames = order
            .filter { (grouped[$0]?.count ?? 0) > 0 }
            .sorted { a, b in
                let ca = grouped[a]?.count ?? 0, cb = grouped[b]?.count ?? 0
                return ca != cb ? ca > cb : idx(a) < idx(b)
            }
        let empties = order.filter { (grouped[$0]?.count ?? 0) == 0 }

        for c in withGames {
            let games = (grouped[c] ?? [])
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                .map { HomeGame(id: $0.id.uuidString, title: $0.title, rom: $0) }
            out.append(section(for: c, games: games))
        }
        for c in empties { out.append(section(for: c, games: [])) }
        return out
    }

    private func section(for c: ConsoleSystem, games: [HomeGame]) -> HomeSection {
        HomeSection(id: c.rawValue, title: c.displayName, badgeSymbol: c.systemIcon,
                    accent: c.accent, gradient: c.badgeGradient, games: games, console: c)
    }

    private var clampedIndex: Int { min(max(selectedIndex, 0), max(sections.count - 1, 0)) }
    private var selectedSection: HomeSection { sections[clampedIndex] }

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            // Full-bleed; position everything inside the TRUE safe rect (UIWindow).
            let ins = insets
            let W = geo.size.width
            let H = geo.size.height
            let safeW = max(W - ins.left - ins.right, 240)
            let topBarH: CGFloat = 44
            // Console panel spans almost the full screen height (per the user's
            // rectangle): top near the very top, bottom near the very bottom
            // (the panel is on the left, clear of the centered home indicator),
            // and nudged a little closer to the camera on the left.
            let panelTop = ins.top + 12
            let panelBot = H - 12
            let panelH   = max(panelBot - panelTop, 120)
            let focalLocalY = panelH * 0.46
            let focalY      = panelTop + focalLocalY
            let panelX = ins.left + 2          // a little closer to the camera
            let rowsX  = panelX + 8
            let panelW = columnInnerW + 14
            let gamesLead = panelX + panelW + 18   // games follow the panel left

            ZStack(alignment: .topLeading) {
                background

                gamesLane(geo, lead: gamesLead, centerY: focalY)

                frostedColumn(x: panelX, y: panelTop, width: panelW, height: panelH)
                    .allowsHitTesting(false)

                ConsoleSpineView(
                    sections: sections,
                    selectedIndex: clampedIndex,
                    innerW: columnInnerW,
                    rowNormalW: rowNormalW,
                    rowSelW: rowSelW,
                    slotHeight: slotHeight,
                    panelH: panelH,
                    focalLocalY: focalLocalY,
                    onSelect: { selectedIndex = $0 }
                )
                .position(x: rowsX + columnInnerW / 2, y: panelTop + panelH / 2)

                topBar(width: safeW, height: topBarH)
                    .position(x: ins.left + safeW / 2, y: ins.top + 12 + topBarH / 2)
            }
            .frame(width: W, height: H, alignment: .topLeading)
            .onAppear {
                insets = Self.readWindowInsets()
                canvasW = max(geo.size.width - insets.left - insets.right, 240)
                canvasH = max(geo.size.height - insets.top - insets.bottom, 220)
                cachedSections = computeSections()
                // Warm-decode every cover AND the pixel-art badges off-main so
                // the first composite of any card/row never decodes on-main.
                CoverStore.shared.preload(library.roms.compactMap { $0.coverURL?.path })
                DispatchQueue.global(qos: .userInitiated).async {
                    for c in ConsoleSystem.allCases {
                        _ = UIImage(named: c.pixelAsset)?.preparingForDisplay()
                    }
                }
            }
            .onChange(of: library.roms) { _ in cachedSections = computeSections() }
            .onChange(of: geo.size) { s in
                insets = Self.readWindowInsets()
                canvasW = max(s.width - insets.left - insets.right, 240)
                canvasH = max(s.height - insets.top - insets.bottom, 220)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Background (vivid, accent-tinted — matches the mockup)

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x1b1340), Color(hex: 0x120d28), Color(hex: 0x07050f)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(gradient: Gradient(colors: [selectedSection.accent.opacity(0.55), .clear]),
                           center: UnitPoint(x: 0.88, y: 0.04), startRadius: 0, endRadius: 720)
            RadialGradient(gradient: Gradient(colors: [Color(hex: 0x5b3cff).opacity(0.42), .clear]),
                           center: UnitPoint(x: 0.05, y: 1.0), startRadius: 0, endRadius: 620)
            LinearGradient(colors: [.clear, Color.black.opacity(0.35)],
                           startPoint: .center, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.5), value: clampedIndex)
    }

    // MARK: Frosted console column (games slide behind it, semi-transparent)

    private func frostedColumn(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(selectedSection.accent.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.05)],
                                           startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .frame(width: width, height: height)
            .position(x: x + width / 2, y: y + height / 2)
            .shadow(color: .black.opacity(0.35), radius: 24, x: 8, y: 0)
    }

    // MARK: Games lane (slides behind the frosted column)

    private func gamesLane(_ geo: GeometryProxy, lead: CGFloat, centerY: CGFloat) -> some View {
        let sec = selectedSection
        return ZStack(alignment: .topLeading) {
            // Header sits just above the focal card.
            Text(gamesHeader(sec))
                .font(.system(size: 13, weight: .heavy)).tracking(0.6)
                .foregroundColor(sec.accent)
                .shadow(color: .black.opacity(0.5), radius: 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, lead)
                .padding(.top, max(centerY - 106, 8))

            if sec.isEmptyConsole {
                emptyGames(sec)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, lead)
                    .padding(.top, max(centerY - 58, 8))
            } else {
                GamesCarouselView(
                    section: sec,
                    cardBase: cardBase,
                    gameSlot: gameSlot,
                    focalX: lead + 66,
                    centerY: centerY,
                    width: geo.size.width,
                    height: geo.size.height,
                    trailingPad: insets.right + 26,
                    onPlay: { g in
                        if g.isDemo { onPlayDemo() }
                        else if let rom = g.rom { onPlayROM(rom) }
                    }
                )
                .id(sec.id)   // new console → fresh carousel at game 0
            }
        }
        .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        // Cards sliding behind the frosted panel must NOT re-emerge in the
        // thin strip between the panel and the screen edge (camera side) —
        // mask the whole lane off left of the panel's left edge.
        .mask(Rectangle().padding(.leading, insets.left + 2))
    }

    private func gamesHeader(_ sec: HomeSection) -> String {
        if sec.console == nil {
            return NSLocalizedString("DEMO · BUILT-IN", comment: "Games header: demo section")
        }
        if sec.count == 0 {
            return String(format: NSLocalizedString("%@ · NO GAMES YET", comment: "Games header: empty console"), sec.title)
        }
        if sec.count == 1 {
            return String(format: NSLocalizedString("%@ · 1 GAME", comment: "Games header: one game"), sec.title)
        }
        return String(format: NSLocalizedString("%@ · %d GAMES", comment: "Games header: game count"), sec.title, sec.count)
    }

    private func emptyGames(_ sec: HomeSection) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                .foregroundColor(.white.opacity(0.25))
                .frame(width: 106, height: 106)
                .overlay(Image(systemName: "plus")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4)))
            VStack(alignment: .leading, spacing: 6) {
                Text("No games yet")
                    .font(.headline).foregroundColor(.white.opacity(0.85))
                Text("Tap + to import a game for this system.")
                    .font(.subheadline).foregroundColor(.white.opacity(0.55))
                Button(action: onImport) {
                    Text("Import")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Capsule().fill(sec.accent))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }

    // MARK: Top bar (REmu centered, actions trailing)

    private func topBar(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Text("REmu")
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: Color(hex: 0x9b6cff).opacity(0.6), radius: 12)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 10) {
                circleButton("questionmark", action: onOpenTutorial)
                circleButton("gearshape", action: onOpenSettings)
                circleButton("plus", action: onImport)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(width: width, height: height, alignment: .center)
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 36, height: 36)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().stroke(Color.white.opacity(0.16)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Console spine (focal-snap carousel, owns its drag state)

private struct ConsoleSpineView: View {
    let sections: [HomeSection]
    let selectedIndex: Int
    let innerW: CGFloat
    let rowNormalW: CGFloat
    let rowSelW: CGFloat
    let slotHeight: CGFloat
    let panelH: CGFloat
    let focalLocalY: CGFloat
    let onSelect: (Int) -> Void

    @State private var dragOffset: CGFloat = 0

    /// Extra space (in slot units) inserted at the games/empty boundary so the
    /// divider gets REAL room — a 57pt slot leaves only ~6pt between rows,
    /// which can never fit a labeled divider without crowding.
    private let dividerGap: CGFloat = 0.45

    private var firstEmpty: Int? { sections.firstIndex(where: { $0.isEmptyConsole }) }

    /// Rows at/under the divider shift down by the gap; subtracting the
    /// selected row's own shift keeps the FOCUSED row exactly on the focal line.
    private func extraOffset(_ i: Int) -> CGFloat {
        guard let fe = firstEmpty, i >= fe else { return 0 }
        return dividerGap
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // All rows stay in the hierarchy (off-panel ones are clipped), and
            // their selection chrome is permanently present at alpha 0 — so a
            // drag never inserts new layers mid-gesture (the structural commit
            // that caused the first-frame hitch).
            ForEach(Array(sections.enumerated()), id: \.element.id) { i, sec in
                let rel = CGFloat(i - selectedIndex) + dragOffset / slotHeight
                let visRel = rel + extraOffset(i) - extraOffset(selectedIndex)
                let centerY = focalLocalY + visRel * slotHeight
                let c = max(0, 1 - abs(rel))
                consoleRow(sec, closeness: c)
                    .position(x: rowWidth(c) / 2 + 2, y: centerY)
            }

            // Labeled divider, centered in its own inserted gap.
            if let fe = firstEmpty {
                let relD = CGFloat(fe) - 0.5 - CGFloat(selectedIndex) + dragOffset / slotHeight
                    + dividerGap / 2 - extraOffset(selectedIndex)
                HStack(spacing: 8) {
                    Text("NO GAMES · SUPPORTED")
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(0.7)
                        .foregroundColor(.white.opacity(0.38))
                        .lineLimit(1)
                        .fixedSize()
                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                }
                .frame(width: rowNormalW - 8)
                .position(x: rowNormalW / 2 + 2, y: focalLocalY + relD * slotHeight)
            }
        }
        .frame(width: innerW, height: panelH, alignment: .topLeading)
        .clipped()
        // Rows fade out softly near the panel's top/bottom instead of being
        // sliced by the hard clip edge.
        .mask(
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.055),
                .init(color: .black, location: 0.945),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        )
        .contentShape(Rectangle())
        .gesture(drag)
    }

    // ONE gesture handles both drag and tap. A separate .onTapGesture on the
    // rows made SwiftUI arbitrate tap-vs-drag: slow finger movement was
    // withheld until the tap failed, then released all at once ("waits, then
    // jumps"). minimumDistance 0 tracks the finger from the very first point;
    // a release that barely moved (≤ 8pt) counts as a tap on that row.
    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let count = sections.count
                let minOff = CGFloat(selectedIndex - (count - 1)) * slotHeight
                let maxOff = CGFloat(selectedIndex) * slotHeight
                dragOffset = min(max(v.translation.height, minOff), maxOff)
            }
            .onEnded { v in
                var target: Int
                if abs(v.translation.width) < 8 && abs(v.translation.height) < 8 {
                    // Tap: select the row under the finger (accounting for the
                    // divider's inserted gap below the boundary).
                    let relTap = (v.location.y - focalLocalY) / slotHeight + extraOffset(selectedIndex)
                    target = selectedIndex + Int(relTap.rounded())
                    if let fe = firstEmpty, target >= fe {
                        target = selectedIndex + Int((relTap - dividerGap).rounded())
                    }
                    target = min(max(target, 0), sections.count - 1)
                } else {
                    let shift = Int((dragOffset / slotHeight).rounded())
                    target = min(max(selectedIndex - shift, 0), sections.count - 1)
                }
                withAnimation(.interpolatingSpring(stiffness: 220, damping: 26)) {
                    onSelect(target); dragOffset = 0
                }
            }
    }

    private func rowWidth(_ c: CGFloat) -> CGFloat { rowNormalW + (rowSelW - rowNormalW) * c }

    private func consoleRow(_ sec: HomeSection, closeness c: CGFloat) -> some View {
        let badgeSize = slotHeight * 0.62 + slotHeight * 0.13 * c
        let nameSize  = slotHeight * 0.27 + 2 * c
        let rowH      = slotHeight * 0.88 + slotHeight * 0.12 * c
        let cd        = Double(c)
        return HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 11 + 2 * c, style: .continuous)
                    .fill(LinearGradient(colors: sec.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: badgeSize, height: badgeSize)
                    .overlay(
                        // Always present; fully transparent at c == 0 (free to
                        // composite, never a structural insert during drag).
                        RoundedRectangle(cornerRadius: 11 + 2 * c, style: .continuous)
                            .stroke(Color.white.opacity(0.92 * cd), lineWidth: 2.4 * c)
                    )
                if let console = sec.console {
                    Image(console.pixelAsset)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(badgeSize * 0.08)
                } else {
                    Image(systemName: sec.badgeSymbol)
                        .font(.system(size: badgeSize * 0.44, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            Text(sec.title)
                .font(.system(size: nameSize, weight: c > 0.5 ? .bold : .semibold))
                .foregroundColor(.white.opacity(0.72 + 0.28 * cd))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(maxWidth: .infinity, alignment: .leading)
            if sec.console == nil || sec.count > 0 {
                Text("\(sec.count)")
                    .font(.system(size: 12 + c, weight: .bold))
                    .foregroundColor(.white.opacity(0.72 + 0.28 * cd))
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.10 + 0.14 * cd)))
            }
        }
        .padding(.horizontal, 11)
        .frame(width: rowWidth(c), height: rowH, alignment: .leading)
        .background(
            // Always present; alpha-0 at rest (see badge stroke note above).
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [sec.accent.opacity(0.40 * cd),
                                              sec.accent.opacity(0.12 * cd)],
                                     startPoint: .leading, endPoint: .trailing))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.22 * cd)))
        )
        .opacity(sec.isEmptyConsole ? 0.5 : (0.84 + 0.16 * cd))
    }
}

// MARK: - Games carousel (focal-snap, owns its drag state)

private struct GamesCarouselView: View {
    let section: HomeSection
    let cardBase: CGFloat
    let gameSlot: CGFloat
    let focalX: CGFloat
    let centerY: CGFloat
    let width: CGFloat
    let height: CGFloat
    let trailingPad: CGFloat
    let onPlay: (HomeGame) -> Void

    @State private var gameIndex = 0
    @State private var dragX: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(section.games.enumerated()), id: \.element.id) { i, g in
                let rel = CGFloat(i - gameIndex) + dragX / gameSlot
                let cx  = focalX + rel * gameSlot
                let c   = max(0, 1 - abs(rel))
                gameCard(g, closeness: c)
                    .position(x: cx, y: centerY)
            }

            // Detail / action bar for the focused game (idea #4): fills the
            // empty bottom area with a PLAY button + metadata. Lives INSIDE
            // the carousel so focus changes never re-render the whole home.
            let focused = section.games[min(max(gameIndex, 0), max(section.games.count - 1, 0))]
            let barLead = focalX - cardBase * 0.68
            let barW = max(width - barLead - trailingPad, 220)
            detailBar(focused)
                .frame(width: barW, alignment: .leading)
                .position(x: barLead + barW / 2, y: height - 56)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(drag)
    }

    private static let relFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func detailBar(_ game: HomeGame) -> some View {
        HStack(spacing: 14) {
            Button(action: { onPlay(game) }) {
                HStack(spacing: 7) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .heavy))
                    Text("PLAY")
                        .font(.system(size: 13.5, weight: .heavy))
                        .tracking(1.1)
                }
                .foregroundColor(.black)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(Capsule().fill(section.accent))
                .shadow(color: section.accent.opacity(0.45), radius: 9, y: 3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(section.title)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(.white.opacity(0.88))
                    Text("·").foregroundColor(.white.opacity(0.4))
                    Text("\(gameIndex + 1) / \(section.games.count)")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.62))
                }
                Text(subtitle(for: game))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
        .padding(.leading, 12).padding(.trailing, 18).padding(.vertical, 9)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(Color.white.opacity(0.12)))
        )
        .fixedSize()
    }

    private func subtitle(for game: HomeGame) -> String {
        if game.isDemo {
            return NSLocalizedString("Built-in demo · no ROM needed", comment: "Detail bar: demo subtitle")
        }
        if let date = game.rom?.lastPlayed {
            return String(format: NSLocalizedString("Last played %@", comment: "Detail bar: relative last-played date"),
                          Self.relFormatter.localizedString(for: date, relativeTo: Date()))
        }
        return NSLocalizedString("Never played yet", comment: "Detail bar: game never launched")
    }

    // Single gesture for drag + tap (see ConsoleSpineView.drag for why):
    // tracks the finger from the first point; a release that barely moved
    // launches the card under the finger.
    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let count = section.games.count
                let minX = CGFloat(gameIndex - (count - 1)) * gameSlot
                let maxX = CGFloat(gameIndex) * gameSlot
                dragX = min(max(v.translation.width, minX), maxX)
            }
            .onEnded { v in
                let count = section.games.count
                if abs(v.translation.width) < 8 && abs(v.translation.height) < 8 {
                    // Tap: like the console spine, tapping a non-focused card
                    // SELECTS it (snaps it to the focal spot); only tapping the
                    // already-focused card launches the game.
                    let rel = (v.location.x - focalX) / gameSlot
                    let i = gameIndex + Int(rel.rounded())
                    let withinCardBand = abs(v.location.y - centerY) <= cardBase * 0.78
                    if i >= 0 && i < count && withinCardBand {
                        if i == gameIndex {
                            dragX = 0
                            onPlay(section.games[i])
                        } else {
                            withAnimation(.interpolatingSpring(stiffness: 240, damping: 28)) {
                                gameIndex = i; dragX = 0
                            }
                        }
                        return
                    }
                    withAnimation(.interpolatingSpring(stiffness: 240, damping: 28)) { dragX = 0 }
                } else {
                    let shift = Int((dragX / gameSlot).rounded())
                    let target = min(max(gameIndex - shift, 0), max(count - 1, 0))
                    withAnimation(.interpolatingSpring(stiffness: 240, damping: 28)) {
                        gameIndex = target; dragX = 0
                    }
                }
            }
    }

    private func gameCard(_ game: HomeGame, closeness c: CGFloat) -> some View {
        let cd = Double(c)
        return VStack(spacing: 6) {
            CoverImage(path: game.rom?.coverURL?.path) {
                ZStack {
                    LinearGradient(colors: section.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    if let console = section.console {
                        Image(console.pixelAsset)
                            .interpolation(.none).resizable().scaledToFit()
                            .padding(cardBase * 0.22)
                    } else {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundColor(.white.opacity(0.92))
                    }
                }
            }
            .frame(width: cardBase, height: cardBase)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(Color.white.opacity(0.14 + 0.78 * cd), lineWidth: 1 + 1.6 * c)
            )
            .shadow(color: .black.opacity(0.4), radius: 7, x: 0, y: 5)

            // Fixed-height title/hint slots for EVERY card so the cover never
            // shifts vertically as titles wrap or the hint fades in.
            Text(game.title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.white.opacity(0.55 + 0.45 * cd))
                .multilineTextAlignment(.center)
                .lineLimit(c > 0.6 ? 2 : 1)   // focused card shows its full name
                .frame(width: cardBase + 16, height: 32, alignment: .top)
        }
        .scaleEffect(1 + 0.16 * c)
        .contentShape(Rectangle())
    }
}
