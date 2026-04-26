import Foundation
import SwiftUI

// MARK: - Pure game logic (framework-agnostic)
// Orijinal, telifsiz bir "yılan" türevi. Tema: kırkayak.

enum CoilpedeDirection {
    case up, down, left, right

    var vector: (x: Int, y: Int) {
        switch self {
        case .up:    return (0, -1)
        case .down:  return (0, 1)
        case .left:  return (-1, 0)
        case .right: return (1, 0)
        }
    }

    var opposite: CoilpedeDirection {
        switch self {
        case .up: return .down; case .down: return .up
        case .left: return .right; case .right: return .left
        }
    }
}

struct GridPoint: Equatable {
    var x: Int
    var y: Int
}

enum CoilpedeState {
    case ready
    case playing
    case gameOver
}

final class CoilpedeGame: ObservableObject {
    // Arena
    let cols: Int
    let rows: Int

    // State
    @Published private(set) var segments: [GridPoint] = []
    @Published private(set) var leaf: GridPoint = GridPoint(x: 0, y: 0)
    @Published private(set) var direction: CoilpedeDirection = .right
    @Published private(set) var score: Int = 0
    @Published private(set) var highScore: Int = UserDefaults.standard.integer(forKey: "coilpede.highScore")
    @Published private(set) var state: CoilpedeState = .ready
    @Published private(set) var tickCount: Int = 0   // for leg animation

    // Queued direction (so player can't reverse into themselves)
    private var pendingDirection: CoilpedeDirection?

    init(cols: Int = 24, rows: Int = 14) {
        self.cols = cols
        self.rows = rows
        reset()
    }

    // MARK: Lifecycle

    func reset() {
        let startX = cols / 3
        let startY = rows / 2
        segments = [
            GridPoint(x: startX,     y: startY),
            GridPoint(x: startX - 1, y: startY),
            GridPoint(x: startX - 2, y: startY),
        ]
        direction = .right
        pendingDirection = nil
        score = 0
        tickCount = 0
        placeLeaf()
        state = .ready
    }

    func start() {
        guard state != .playing else { return }
        if state == .gameOver { reset() }
        state = .playing
    }

    // MARK: Input

    func queueDirection(_ dir: CoilpedeDirection) {
        // No 180° reverse if body length > 1
        if dir == direction.opposite, segments.count > 1 { return }
        pendingDirection = dir
        if state == .ready { start() }
    }

    // MARK: Simulation

    func tick() {
        guard state == .playing else { return }

        if let pending = pendingDirection {
            direction = pending
            pendingDirection = nil
        }

        tickCount &+= 1

        // Compute new head
        let head = segments[0]
        let next = GridPoint(
            x: head.x + direction.vector.x,
            y: head.y + direction.vector.y
        )

        // Wall collision
        if next.x < 0 || next.x >= cols || next.y < 0 || next.y >= rows {
            endGame(); return
        }

        // Self collision (ignore tail — it will move away)
        if segments.dropLast().contains(next) {
            endGame(); return
        }

        // Move: insert new head
        segments.insert(next, at: 0)

        // Eat?
        if next == leaf {
            score += 10
            placeLeaf()
        } else {
            segments.removeLast()
        }
    }

    // MARK: Helpers

    private func placeLeaf() {
        var candidate: GridPoint
        var tries = 0
        repeat {
            candidate = GridPoint(
                x: Int.random(in: 0..<cols),
                y: Int.random(in: 0..<rows)
            )
            tries += 1
        } while segments.contains(candidate) && tries < 200
        leaf = candidate
    }

    private func endGame() {
        state = .gameOver
        if score > highScore {
            highScore = score
            UserDefaults.standard.set(highScore, forKey: "coilpede.highScore")
        }
    }

    // Difficulty curve: faster as score rises
    var currentTickInterval: TimeInterval {
        let base: TimeInterval = 0.16
        let min: TimeInterval  = 0.06
        let step = Double(score / 30) * 0.01
        return max(min, base - step)
    }
}
