import SwiftUI

@main
struct RetroNexusApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    // Triggered when iOS hands off a file to REmu via
                    // Safari's "Open in REmu" or the Files app share sheet.
                    if let rom = ROMLibrary.shared.importROM(from: url) {
                        // Tell ContentView to auto-launch the freshly
                        // imported ROM.
                        NotificationCenter.default.post(
                            name: .remuShouldLaunchROM,
                            object: rom
                        )
                    }
                }
        }
    }
}

// MARK: - Root View
//
// ContentView stays mounted at all times so its NotificationCenter
// observers (e.g. .remuShouldLaunchROM from onOpenURL) never miss an
// event, even on first launch. The EULA renders as a fade-able overlay
// on top until the user accepts; persistence lives in @AppStorage so
// the gate appears exactly once per install (or once per terms revision
// when the version suffix is bumped).
private struct RootView: View {
    @AppStorage("remu.eula.accepted.v1") private var hasAcceptedEULA = false

    var body: some View {
        ZStack {
            ContentView()

            if !hasAcceptedEULA {
                EULAView(displayMode: .firstLaunch) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        hasAcceptedEULA = true
                    }
                }
                .transition(.opacity)
            }
        }
    }
}

extension Notification.Name {
    /// Posted after a ROM is imported via onOpenURL so the UI can launch it.
    static let remuShouldLaunchROM = Notification.Name("remu.shouldLaunchROM")
    /// Posted by CoreBridge when a libretro core is successfully loaded.
    static let remuCoreLoaded      = Notification.Name("remu.coreLoaded")
    /// Posted by CoreBridge when a libretro core fails to load (most likely
    /// because the matching .dylib isn't bundled with the app yet).
    static let remuCoreLoadFailed  = Notification.Name("remu.coreLoadFailed")
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return .landscape
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // GADMobileAds.sharedInstance().start(completionHandler: nil)  // AdMob init
        SaveStateManager.shared.createDirectoriesIfNeeded()
        GameControllerManager.shared.start()
        return true
    }
}
