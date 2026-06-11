import SwiftUI
import UIKit

// MARK: - Force-update gate (PUBG-style)
//
// On launch and on every return to foreground the app reads a tiny JSON from
// the public GitHub repo:
//
//     https://raw.githubusercontent.com/fatih-koca/REmu/main/appconfig.json
//     { "minVersion": "1.4.0" }
//
// If the installed version is OLDER than minVersion, RootView covers the app
// with UpdateRequiredView (no way past it except the App Store button). To
// make any future release mandatory, bump minVersion in that file — no app
// update needed for the switch itself.
//
// Fails OPEN by design: no network, timeout or bad JSON simply never blocks.
// Retro games are played offline; an unreachable config must not lock anyone
// out of their library.

final class UpdateGate: ObservableObject {
    static let shared = UpdateGate()

    @Published private(set) var updateRequired = false

    static let appStoreURL = URL(string: "https://apps.apple.com/app/id6767642114")!
    private let configURL = URL(string: "https://raw.githubusercontent.com/fatih-koca/REmu/main/appconfig.json")!

    private init() {
        check()
        NotificationCenter.default.addObserver(
            self, selector: #selector(check),
            name: UIApplication.willEnterForegroundNotification, object: nil
        )
    }

    @objc private func check() {
        var req = URLRequest(url: configURL)
        req.cachePolicy = .reloadIgnoringLocalCacheData   // always the live value
        req.timeoutInterval = 8
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let data,
                  let cfg = try? JSONDecoder().decode(RemoteConfig.self, from: data)
            else { return }   // fail open
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            let outdated = current.compare(cfg.minVersion, options: .numeric) == .orderedAscending
            DispatchQueue.main.async { self?.updateRequired = outdated }
        }.resume()
    }

    private struct RemoteConfig: Decodable { let minVersion: String }
}

// MARK: - Blocking screen

struct UpdateRequiredView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.06, blue: 0.22),
                    Color(red: 0.03, green: 0.02, blue: 0.08),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 54))
                    .foregroundColor(.cyan)
                    .shadow(color: .cyan.opacity(0.5), radius: 16)

                Text("Update required")
                    .font(.title2).bold()
                    .foregroundColor(.white)

                Text("A newer version of REmu is required to continue. Please update from the App Store.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)

                Button {
                    UIApplication.shared.open(UpdateGate.appStoreURL)
                } label: {
                    Text("Update")
                        .font(.headline)
                        .foregroundColor(.black)
                        .padding(.horizontal, 36).padding(.vertical, 13)
                        .background(Capsule().fill(Color.cyan))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .padding(30)
        }
    }
}
