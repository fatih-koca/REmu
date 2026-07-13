import UIKit
import GoogleMobileAds
import AppTrackingTransparency

// MARK: - AdMob manager
//
// Two placements, both OUTSIDE gameplay (never over the emulator screen):
//   1. Interstitial when returning from a ROM session to the library.
//   2. Interstitial on a built-in demo's game-over screen.
// Both share one cooldown so the user never sees ads back-to-back, and
// nothing shows during the first minute after launch.
//
// A rewarded ad powers the demos' "watch an ad, keep playing" revive.
//
// Ad unit IDs below are Google's PUBLIC TEST IDS — replace with REmu's real
// AdMob units before shipping (see the TODOs; the app id lives in
// project.yml → GADApplicationIdentifier).

final class AdManager: NSObject, GADFullScreenContentDelegate {
    static let shared = AdManager()

    // TODO: replace with the real REmu ad unit IDs from the AdMob console.
    private enum Unit {
        static let interstitial = "ca-app-pub-3940256099942544/4411468910"   // TEST
        static let rewarded     = "ca-app-pub-3940256099942544/1712485313"   // TEST
    }

    private var interstitial: GADInterstitialAd?
    private var rewarded: GADRewardedAd?
    private var onRewardEarned: (() -> Void)?

    private let launchedAt = Date()
    private var lastShownAt: Date?
    private let cooldown: TimeInterval = 240        // ≥4 min between interstitials
    private let quietAfterLaunch: TimeInterval = 60 // no ads in the first minute

    /// True when the rewarded "continue" is loaded and can be offered.
    var rewardedReady: Bool { rewarded != nil }

    // MARK: Startup

    /// Called from AppDelegate. Waits a beat so the splash isn't competing
    /// with the ATT sheet, asks for tracking consent once, then starts the
    /// SDK and preloads both formats. Ads work either way — consent only
    /// decides personalized vs non-personalized.
    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if #available(iOS 14.5, *),
               ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
                ATTrackingManager.requestTrackingAuthorization { _ in
                    DispatchQueue.main.async { self.startSDK() }
                }
            } else {
                self.startSDK()
            }
        }
    }

    private func startSDK() {
        GADMobileAds.sharedInstance().start { [weak self] _ in
            self?.loadInterstitial()
            self?.loadRewarded()
        }
    }

    // MARK: Interstitial

    private func loadInterstitial() {
        GADInterstitialAd.load(withAdUnitID: Unit.interstitial,
                               request: GADRequest()) { [weak self] ad, _ in
            ad?.fullScreenContentDelegate = self
            self?.interstitial = ad
        }
    }

    /// Fire-and-forget: shows an interstitial after `delay` if one is loaded
    /// and the cooldown allows it. Safe to call from any trigger point.
    func showInterstitialIfEligible(after delay: TimeInterval = 0.6) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            guard let ad = interstitial,
                  Date().timeIntervalSince(launchedAt) > quietAfterLaunch,
                  lastShownAt.map({ Date().timeIntervalSince($0) > cooldown }) ?? true,
                  let root = Self.topViewController()
            else { return }
            interstitial = nil          // consumed; delegate reloads on dismiss
            lastShownAt = Date()
            ad.present(fromRootViewController: root)
        }
    }

    // MARK: Rewarded ("watch an ad, keep playing")

    private func loadRewarded() {
        GADRewardedAd.load(withAdUnitID: Unit.rewarded,
                           request: GADRequest()) { [weak self] ad, _ in
            ad?.fullScreenContentDelegate = self
            self?.rewarded = ad
        }
    }

    /// Presents the rewarded ad; `onReward` runs on the main thread once the
    /// user has earned the reward (i.e. actually watched it).
    func showRewarded(onReward: @escaping () -> Void) {
        guard let ad = rewarded, let root = Self.topViewController() else { return }
        rewarded = nil                  // consumed; delegate reloads on dismiss
        onRewardEarned = onReward
        ad.present(fromRootViewController: root) { [weak self] in
            DispatchQueue.main.async {
                self?.onRewardEarned?()
                self?.onRewardEarned = nil
            }
        }
    }

    // MARK: GADFullScreenContentDelegate

    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        reloadSlot(for: ad)
    }

    func ad(_ ad: GADFullScreenPresentingAd,
            didFailToPresentFullScreenContentWithError error: Error) {
        onRewardEarned = nil
        reloadSlot(for: ad)
    }

    private func reloadSlot(for ad: GADFullScreenPresentingAd) {
        if ad is GADRewardedAd { loadRewarded() } else { loadInterstitial() }
    }

    // MARK: Helpers

    private static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.rootViewController
        var top = root
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
