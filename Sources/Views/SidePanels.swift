import SwiftUI

// MARK: - Game Info Top Strip
//
// Horizontal strip at the very top of any in-game screen. Shows the
// game title (and optional subtitle / category) on the left, and any
// number of stat pairs (FPS, SCORE, BEST, …) aligned to the right.

struct GameInfoTopStrip: View {
    let title: String
    let subtitle: String?
    let stats: [(String, String)]
    let onPause: (() -> Void)?

    init(
        title: String,
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

            Spacer()

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

            if let onPause {
                PauseButton(onPause: onPause)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .frame(maxWidth: .infinity)
        .background(
            // Solid at top, fades into the game underneath
            LinearGradient(
                colors: [
                    Color.black.opacity(0.78),
                    Color.black.opacity(0.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
    }
}

// MARK: - Ad Bottom Strip
//
// Horizontal AdMob banner placeholder strip pinned to the bottom of any
// in-game screen. Replace with a GADBannerView bridge once the AdMob
// SDK is integrated.

struct AdBottomStrip: View {
    var body: some View {
        ZStack {
            // Fades from transparent into solid black at the very bottom
            LinearGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.78),
                ],
                startPoint: .top, endPoint: .bottom
            )
            Text("[ AdMob Banner ]")
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundColor(.gray.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 36)
    }
}
