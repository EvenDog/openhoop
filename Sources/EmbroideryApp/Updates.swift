// New versions of OpenHoop, through Sparkle (an open-source updater many Mac apps use). Once a day, and whenever
// OpenHoop › Check for Updates… is chosen, it reads the update feed at openhoop.app/appcast.xml (SUFeedURL in
// Info.plist). When the feed lists a newer version, Sparkle shows what's new and can download it, install it and
// relaunch. Each download must carry a signature made with OpenHoop's private key, which Sparkle checks against the
// public key in Info.plist (SUPublicEDKey), so it only ever installs updates OpenHoop's maker published.
import AppKit
import Sparkle

@MainActor enum Updates {
    /// Sparkle's updater with its standard windows, made when the app finishes launching. nil when OpenHoop runs
    /// outside its app bundle (tests, `swift run`), which has no feed to check.
    private(set) static var controller: SPUStandardUpdaterController?

    /// Starts the updater: it checks on its own from here on (once a day, unless switched off in Settings).
    static func start() {
        guard controller == nil, Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    /// OpenHoop › Check for Updates…, or nil outside the app bundle. Sparkle's controller is its target, so the item
    /// greys itself out while a check is already running.
    static func menuItem() -> NSMenuItem? {
        guard let controller else { return nil }
        let item = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        item.target = controller
        return item
    }

    /// Whether OpenHoop checks by itself once a day (on unless switched off; Sparkle remembers the choice).
    static var checksAutomatically: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }
    /// When it last checked, if it ever has.
    static var lastCheck: Date? { controller?.updater.lastUpdateCheckDate }
    /// Checks now, showing the result (an update, or that this is the newest version).
    static func checkNow() { controller?.checkForUpdates(nil) }
}
