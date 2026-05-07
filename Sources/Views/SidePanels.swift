import SwiftUI

// MARK: - Game Info Top Strip
//
// Horizontal strip at the very top of any in-game screen. Shows the
// game title (and optional subtitle / category) on the left, and any
// number of stat pairs (FPS, SCORE, BEST, …) aligned to the right.

struct GameInfoTopStrip: View {
    let stats: [(String, String)]
    let onPause: (() -> Void)?

    init(
        stats: [(String, String)] = [],
        onPause: (() -> Void)? = nil
    ) {
        self.stats = stats
        self.onPause = onPause
    }

    var body: some View {
        HStack(spacing: 18) {
            // Pause button — moved to the left side
            if let onPause {
                PauseButton(onPause: onPause)
            }

            Spacer()

            // FPS (and any other stat) stays on the right
            ForEach(stats.indices, id: \.self) { i in
                VStack(alignment: .trailing, spacing: 1) {
                    Text(stats[i].0)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.gray)
                        .tracking(0.5)
                    Text(stats[i].1)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 50)
        .frame(maxWidth: .infinity)
        .background(
            // Light wash so pause/FPS chips remain readable while the game
            // pixels stay visible underneath. Faded to nothing at the bottom
            // edge so the transition into the canvas is invisible.
            LinearGradient(
                colors: [
                    Color.black.opacity(0.32),
                    Color.black.opacity(0.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
    }
}

