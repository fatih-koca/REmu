import Foundation
import SwiftUI

// MARK: - Lumo — original neon platformer (pure logic)
//
// %100 özgün bir yan kaydırmalı platform oyunu. Kahraman: karanlık neon
// dünyayı aydınlatan küçük bir ışık kıvılcımı. Kristalleri topla, kasvet
// yaratıklarının üstüne bas, seviye sonundaki feneri yak. Mantık
// framework'ten bağımsızdır; LumoView çizim + dokunuşu üstlenir.
//
// Tile legend: X solid · ^ spikes · c crystal · e enemy · b bounce pad ·
//              B beacon · P player spawn · . empty

enum LumoState { case ready, playing, levelCleared, won, gameOver }

struct LMEnemy {
    var x: CGFloat          // tile-space center
    var y: CGFloat
    var dir: CGFloat = -1
    var alive = true
}

struct LMCrystal {
    let col: Int
    let row: Int
    var taken = false
}

struct LMParticle {
    var pos: CGPoint        // point-space
    var vel: CGVector
    var life: Double
    var hue: Double
}

final class LumoGame: ObservableObject {

    // Single redraw driver — everything else is plain storage the Canvas
    // reads, so a 120 Hz tick costs one objectWillChange, not twenty.
    @Published private(set) var frame = 0

    // Haptic event counters (view observes deltas).
    @Published private(set) var stompEvents = 0
    @Published private(set) var crystalEvents = 0
    @Published private(set) var hurtEvents = 0
    @Published private(set) var bounceEvents = 0

    private(set) var state: LumoState = .ready
    private(set) var score = 0
    private(set) var highScore = UserDefaults.standard.integer(forKey: "lumo.highScore")
    private(set) var lives = 3
    private(set) var level = 1
    let levelCount = 5

    // World (tile space; 1 unit = one tile)
    private(set) var rows: [String] = []
    private(set) var cols = 0
    private(set) var crystals: [LMCrystal] = []
    private(set) var enemies: [LMEnemy] = []
    private(set) var particles: [LMParticle] = []
    private(set) var beacon = CGPoint.zero          // tile center of the beacon
    private var spawn = CGPoint(x: 2, y: 5)
    // Last solidly-grounded, hazard-free spot — deaths respawn here.
    private var lastSafe = CGPoint(x: 2, y: 5)
    private var safeTimer: TimeInterval = 0

    // Player (tile space; pos = center)
    private(set) var px: CGFloat = 2
    private(set) var py: CGFloat = 5
    private(set) var vx: CGFloat = 0
    private(set) var vy: CGFloat = 0
    private(set) var facing: CGFloat = 1
    private(set) var grounded = false
    private(set) var invulnerable: TimeInterval = 0
    private(set) var time: TimeInterval = 0          // for pulsing/animation

    // Camera (point space) — view reads, game updates.
    private(set) var camX: CGFloat = 0
    private(set) var field = CGSize(width: 850, height: 390)
    var tile: CGFloat { field.height / 11 }

    // Input state
    private var moveInput: CGFloat = 0               // -1…1
    private var jumpHeld = false
    private var jumpBuffer: TimeInterval = 0
    private var coyote: TimeInterval = 0
    private var jumpCut = false
    private var clearTimer: TimeInterval = 0
    private var trailTimer: TimeInterval = 0

    // Player size (in tiles)
    private let pw: CGFloat = 0.62
    private let ph: CGFloat = 0.78

    // MARK: Levels

    private static let maps: [[String]] = [
        // L1
        [
            "........................................................................",
            "........................................................................",
            "........................ccc.............................................",
            ".......................XXXXX............................................",
            "........................................................................",
            ".............cc.....................c.c...............cc................",
            "............XXXX...................XXXXX.............XXXX...............",
            "........................................................................",
            "..P.....c.......e.............b...........e......c..........c.....B.....",
            "XXXXXXXXXXXXXXXXXXXXXX..XXXXXXXXXX...XXXXXXXXXXXXXXXXXXXXX..XXXXXXXXXXXX",
            "XXXXXXXXXXXXXXXXXXXXXX^^XXXXXXXXXX...XXXXXXXXXXXXXXXXXXXXX^^XXXXXXXXXXXX",
        ],
        // L2
        [
            "................................................................................................",
            "......................cc....................................ccc.................................",
            ".....................XXXX...............cc.................XXXXX................................",
            "................e...............................................................................",
            "...............XXXX....................XXXX..........XXXX.........XXXX..........................",
            "................................................................................................",
            ".........XXXX....................XXXX.........XXXX......................XXXX........cc..........",
            "...................................................................................XXXX.........",
            "..P.................e........c..............e.............c...................e............B....",
            "XXXXXXXXXXXXXXXXXXXXXXXXXX..XXXX......XXXXXXXXXXXXXX.....XXXXXXX......XXXXXXXXXX..XXXXXXXXXXXXXX",
            "XXXXXXXXXXXXXXXXXXXXXXXXXX^^XXXX......XXXXXXXXXXXXXX.....XXXXXXX......XXXXXXXXXX^^XXXXXXXXXXXXXX",
        ],
        // L3
        [
            "........................................................................................................",
            "........................................................................................................",
            "........................................................................................................",
            "..................cc...........................cc...............................cc......................",
            ".................XXXX.........................XXXXX............................XXXX.....................",
            ".................................cc.............................cc............................cc........",
            "................................XXXX...........................XXXX..........................XXXX.......",
            "........................................................................................................",
            "..P.......c...b.......e....b..........c......b.......e........b.......c......b........e...........b..B..",
            "XXXXXXXXXXXXXXXX...XXXXXXXXXXXX...XXXXXXXX...XXXXXXXXXXXX...XXXXXXXXXXXXX...XXXXXXXXXXXXX...XXXXXXXXXXXX",
            "XXXXXXXXXXXXXXXX^^^XXXXXXXXXXXX^^^XXXXXXXX^^^XXXXXXXXXXXX^^^XXXXXXXXXXXXX^^^XXXXXXXXXXXXX^^^XXXXXXXXXXXX",
        ],
        // L4
        [
            "........................................................................................................................",
            "........................................................................................................................",
            "...................cc..................................cc..................................cc...........................",
            "..................XXXX................................XXXX................................XXXX..........................",
            "........................................................................................................................",
            "..............cc..................................cc............................................cc......................",
            ".............XXXX................................XXXX..........................................XXXX.....................",
            "........................................................................................................................",
            "..P......e........e.......c........e......b............e.......e......c............e......e..........c.....e......B.....",
            "XXXXXXXXXXXXXXXXXXXXX..XXXXXXXXXXXXXXXX..XXXXXXXXXXXXXXXXXXX..XXXXXXXXXXXXXXXXXX..XXXXXXXXXXX..XXXXXXXXX..XXXXXXXXXXXXXX",
            "XXXXXXXXXXXXXXXXXXXXX^^XXXXXXXXXXXXXXXX^^XXXXXXXXXXXXXXXXXXX^^XXXXXXXXXXXXXXXXXX^^XXXXXXXXXXX^^XXXXXXXXX^^XXXXXXXXXXXXXX",
        ],
        // L5
        [
            "........................................................................................................................................",
            "........................................................cc..............................................................................",
            ".......................................................XXXX.......................................................cc....................",
            ".................................................................................................................XXXX............B......",
            "....................cc............................XXXX......................................................XXXX................XXXX....",
            "...................XXXX.................................................................................cc................cc............",
            ".............XXXX............................XXXX.....................cc...............................XXXX..............XXXX...........",
            ".....................................................................XXXX...............................................................",
            "..P.....e................c.....b........e.................e.....b...........e........c......e......b..........e.......c.................",
            "XXXXXXXXXXXXXXXXXX...XXXXXXXXXXXXXXX...XXXXXXXXXXX...XXXXXXXXXXXXXX...XXXXXXXXXXXX..XXXXXXXXXXX...XXXXXXXXXXXXXX...XXXXXXXXXXXXXXXXXXXXX",
            "XXXXXXXXXXXXXXXXXX^^^XXXXXXXXXXXXXXX...XXXXXXXXXXX^^^XXXXXXXXXXXXXX...XXXXXXXXXXXX^^XXXXXXXXXXX...XXXXXXXXXXXXXX^^^XXXXXXXXXXXXXXXXXXXXX",
        ],
    ]

    // MARK: Lifecycle

    init() {
        resetAll()   // without this the first session starts in an empty world
    }

    func configure(size: CGSize) {
        guard size.width > 100, size.height > 100, size != field else { return }
        field = size
    }

    func resetAll() {
        score = 0
        lives = 3
        level = 1
        loadLevel()
        state = .ready
    }

    func startOrLaunch() {
        switch state {
        case .gameOver, .won:
            resetAll()
        case .ready:
            state = .playing
        default:
            break
        }
    }

    private func loadLevel() {
        let map = Self.maps[(level - 1) % Self.maps.count]
        rows = map
        cols = map.map(\.count).max() ?? 0
        crystals = []
        enemies = []
        particles = []

        for (r, line) in map.enumerated() {
            for (c, ch) in line.enumerated() {
                switch ch {
                case "P": spawn = CGPoint(x: CGFloat(c) + 0.5, y: CGFloat(r) + 0.5)
                case "c": crystals.append(LMCrystal(col: c, row: r))
                case "e": enemies.append(LMEnemy(x: CGFloat(c) + 0.5, y: CGFloat(r) + 0.7))
                case "B": beacon = CGPoint(x: CGFloat(c) + 0.5, y: CGFloat(r) + 0.5)
                default: break
                }
            }
        }
        lastSafe = spawn
        respawnPlayer()
        camX = max(0, px * tile - field.width * 0.38)
    }

    private func respawnPlayer() {
        px = lastSafe.x; py = lastSafe.y
        vx = 0; vy = 0
        grounded = false
        jumpBuffer = 0; coyote = 0
        invulnerable = 1.2
    }

    // MARK: Input (touch buttons / gamepad)

    func setMove(_ v: CGFloat) {
        moveInput = max(-1, min(1, v))
        if v != 0 { facing = v > 0 ? 1 : -1 }
    }

    func pressJump() {
        jumpHeld = true
        jumpBuffer = 0.11
        if state == .ready { state = .playing }
    }

    func releaseJump() {
        jumpHeld = false
        // Variable jump: cutting the hold while rising shortens the arc once.
        if vy < 0, !jumpCut {
            vy *= 0.45
            jumpCut = true
        }
    }

    // MARK: Tile helpers

    private func tileAt(_ c: Int, _ r: Int) -> Character {
        guard r >= 0, r < rows.count else { return "." }
        let line = rows[r]
        guard c >= 0, c < line.count else { return c < 0 ? "X" : (c >= cols ? "X" : ".") }
        return line[line.index(line.startIndex, offsetBy: c)]
    }

    private func isSolid(_ c: Int, _ r: Int) -> Bool {
        let t = tileAt(c, r)
        return t == "X" || t == "b"
    }

    func tileChar(_ c: Int, _ r: Int) -> Character { tileAt(c, r) }

    // MARK: Simulation

    func tick(dt rawDT: TimeInterval) {
        let dt = min(rawDT, 1.0 / 30.0)
        time += dt
        updateParticles(dt)

        switch state {
        case .playing:
            step(dt)
        case .levelCleared:
            clearTimer -= dt
            if clearTimer <= 0 {
                if level >= levelCount {
                    finish(won: true)
                } else {
                    level += 1
                    loadLevel()
                    state = .ready
                }
            }
        default:
            break
        }

        frame &+= 1
    }

    private func step(_ dt: TimeInterval) {
        let t = CGFloat(dt)
        if invulnerable > 0 { invulnerable -= dt }
        if jumpBuffer > 0 { jumpBuffer -= dt }
        if coyote > 0 { coyote -= dt }

        // --- Horizontal: snappy approach toward target speed
        let runSpeed: CGFloat = 7.6
        let target = moveInput * runSpeed
        let approach: CGFloat = grounded ? 42 : 25
        vx += (target - vx) * min(1, approach * t)
        if abs(vx) < 0.02 { vx = 0 }

        // --- Jump
        let gravity: CGFloat = 42
        let jumpVel: CGFloat = 16.9
        if jumpBuffer > 0, grounded || coyote > 0 {
            vy = -jumpVel
            grounded = false
            jumpCut = false
            jumpBuffer = 0
            coyote = 0
        }
        vy += gravity * t
        vy = min(vy, 24)        // terminal fall

        // --- Move X then resolve
        px += vx * t
        resolveX()

        // --- Move Y then resolve
        let wasFalling = vy > 0
        py += vy * t
        resolveY(wasFalling: wasFalling)

        // --- Run trail
        trailTimer -= dt
        if trailTimer <= 0, abs(vx) > 1 || !grounded {
            trailTimer = 0.05
            spawnTrail()
        }

        // --- Hazards / pickups / goal
        interact()

        // --- Enemies
        updateEnemies(t)

        // --- Fell out of the world
        if py > CGFloat(rows.count) + 2 {
            hurt(forceRespawn: true)
        }

        // --- Checkpoint: remember the last spot with BOTH feet on solid
        // ground (never a pit edge); deaths respawn here, not at the start.
        safeTimer -= dt
        if grounded, safeTimer <= 0 {
            let below = Int(floor(py + ph / 2 + 0.1))
            let lc = Int(floor(px - pw / 2 + 0.05))
            let rc = Int(floor(px + pw / 2 - 0.05))
            if isSolid(lc, below), isSolid(rc, below) {
                lastSafe = CGPoint(x: px, y: py)
                safeTimer = 0.3
            }
        }

        // --- Camera follows with lookahead
        let targetCam = max(0, min(px * tile - field.width * 0.38,
                                   CGFloat(cols) * tile - field.width))
        camX += (targetCam - camX) * min(1, 10 * t)
    }

    private func resolveX() {
        let top = Int(floor(py - ph / 2)), bot = Int(floor(py + ph / 2 - 0.001))
        if vx > 0 {
            let edge = px + pw / 2
            let c = Int(floor(edge))
            for r in top...bot where isSolid(c, r) {
                px = CGFloat(c) - pw / 2 - 0.001
                vx = 0
                break
            }
        } else if vx < 0 {
            let edge = px - pw / 2
            let c = Int(floor(edge))
            for r in top...bot where isSolid(c, r) {
                px = CGFloat(c + 1) + pw / 2 + 0.001
                vx = 0
                break
            }
        }
    }

    private func resolveY(wasFalling: Bool) {
        let left = Int(floor(px - pw / 2)), right = Int(floor(px + pw / 2 - 0.001))
        if vy > 0 {
            let edge = py + ph / 2
            let r = Int(floor(edge))
            for c in left...right where isSolid(c, r) {
                py = CGFloat(r) - ph / 2 - 0.001
                vy = 0
                if !grounded { grounded = true }
                coyote = 0.09
                // Bounce pad?
                if tileAt(c, r) == "b" {
                    vy = -21
                    grounded = false
                    bounceEvents += 1
                    burst(at: pointFor(CGFloat(c) + 0.5, CGFloat(r)), hue: 0.38, n: 8)
                }
                jumpCut = false
                return
            }
            if grounded { grounded = false; coyote = 0.09 }
        } else if vy < 0 {
            let edge = py - ph / 2
            let r = Int(floor(edge))
            for c in left...right where isSolid(c, r) {
                py = CGFloat(r + 1) + ph / 2 + 0.001
                vy = 0
                break
            }
        }
    }

    private func interact() {
        // Spikes
        let footR = Int(floor(py + ph / 2 + 0.05))
        let leftC = Int(floor(px - pw / 2 + 0.08)), rightC = Int(floor(px + pw / 2 - 0.08))
        for c in leftC...rightC where tileAt(c, footR) == "^" {
            hurt(); return
        }

        // Crystals
        for i in crystals.indices where !crystals[i].taken {
            let cx = CGFloat(crystals[i].col) + 0.5, cy = CGFloat(crystals[i].row) + 0.5
            if abs(cx - px) < 0.55, abs(cy - py) < 0.6 {
                crystals[i].taken = true
                score += 10
                crystalEvents += 1
                burst(at: pointFor(cx, cy), hue: 0.52, n: 7)
            }
        }

        // Beacon
        if abs(beacon.x - px) < 0.6, abs(beacon.y - py) < 0.9 {
            score += 200
            state = .levelCleared
            clearTimer = 1.5
            burst(at: pointFor(beacon.x, beacon.y - 0.6), hue: 0.12, n: 18)
        }
    }

    private func updateEnemies(_ t: CGFloat) {
        for i in enemies.indices where enemies[i].alive {
            var e = enemies[i]
            let speed: CGFloat = 2.2
            let nx = e.x + e.dir * speed * t
            // Ground check one row BELOW the blob's feet (sampling its own
            // row made every step look like a ledge, freezing the patrol).
            let footR = Int(floor(e.y + 0.4))
            let aheadC = Int(floor(nx + e.dir * 0.4))
            // Turn at walls or ledge edges.
            if isSolid(aheadC, Int(floor(e.y))) || !isSolid(aheadC, footR) {
                e.dir *= -1
            } else {
                e.x = nx
            }
            enemies[i] = e

            // Contact with player
            if abs(e.x - px) < (pw / 2 + 0.38), abs(e.y - py) < (ph / 2 + 0.3) {
                if vy > 1.5, py < e.y - 0.15 {
                    // Stomp!
                    enemies[i].alive = false
                    score += 50
                    stompEvents += 1
                    vy = -9
                    grounded = false
                    burst(at: pointFor(e.x, e.y), hue: 0.76, n: 10)
                } else if invulnerable <= 0 {
                    hurt()
                }
            }
        }
    }

    private func hurt(forceRespawn: Bool = false) {
        guard invulnerable <= 0 || forceRespawn else { return }
        lives -= 1
        hurtEvents += 1
        burst(at: pointFor(px, py), hue: 0.89, n: 12)
        if lives <= 0 {
            finish(won: false)
        } else {
            respawnPlayer()
        }
    }

    private func finish(won: Bool) {
        state = won ? .won : .gameOver
        if score > highScore {
            highScore = score
            UserDefaults.standard.set(highScore, forKey: "lumo.highScore")
        }
    }

    // MARK: Particles (point space)

    func pointFor(_ tx: CGFloat, _ ty: CGFloat) -> CGPoint {
        CGPoint(x: tx * tile, y: ty * tile)
    }

    private func spawnTrail() {
        guard particles.count < 70 else { return }
        particles.append(LMParticle(
            pos: pointFor(px, py + ph * 0.2),
            vel: CGVector(dx: CGFloat.random(in: -12...12), dy: CGFloat.random(in: -6...18)),
            life: 0.45, hue: 0.52
        ))
    }

    private func burst(at p: CGPoint, hue: Double, n: Int) {
        guard particles.count < 80 else { return }
        for _ in 0..<n {
            let ang = Double.random(in: 0..<(2 * .pi))
            let sp = Double.random(in: 30...150)
            particles.append(LMParticle(
                pos: p,
                vel: CGVector(dx: CGFloat(cos(ang) * sp), dy: CGFloat(sin(ang) * sp - 40)),
                life: 1.0, hue: hue
            ))
        }
    }

    private func updateParticles(_ dt: TimeInterval) {
        guard !particles.isEmpty else { return }
        var kept: [LMParticle] = []
        for var pt in particles {
            pt.life -= dt * 2.2
            guard pt.life > 0 else { continue }
            pt.vel.dy += CGFloat(190 * dt)
            pt.pos.x += pt.vel.dx * CGFloat(dt)
            pt.pos.y += pt.vel.dy * CGFloat(dt)
            kept.append(pt)
        }
        particles = kept
    }
}
