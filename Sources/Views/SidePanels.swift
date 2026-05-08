import SwiftUI

// MARK: - Game Info Top Strip
//
// Horizontal strip at the very top of any in-game screen. Shows the
// game title (and optional subtitle / category) on the left, and any
// number of stat pairs (FPS, SCORE, BEST, …) aligned to the right.

struct GameInfoTopStrip: View {
    /// Optional — when supplied, drawn on the leading side. The
    /// emulator screen passes the ROM title here; the built-in
    /// Glowchase demo prefers a clean strip and leaves it nil.
    let title: String?
    let subtitle: String?
    let stats: [(String, String)]
    let onPause: (() -> Void)?

    init(
        title: String? = nil,
        subtitle: String? = nil,
        stats: [(String, String)] = [],
        onPause: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.stats = stats
        self.onPause = onPause
    }

    var body: some View {
        HStack(spacing: 18) {
            // Pause button — leading edge
            if let onPause {
                PauseButton(onPause: onPause)
            }

            // Optional title + subtitle. Built-in demos leave both nil
            // for a clean strip; the emulator screen fills them in.
            if let title {
                VStack(alignment: .leading, spacing: 1) {
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.orange)
                            .tracking(0.8)
                    }
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
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

