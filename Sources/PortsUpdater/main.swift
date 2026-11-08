import AppKit
import Sparkle

// Started by the menu bar agent once a day, or with --now from the panel's Check for Updates.
// It checks GitHub's latest release, shows Sparkle's window if there's an update, and exits.
final class Updater: NSObject, NSApplicationDelegate, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private let now = CommandLine.arguments.contains("--now")
    private var controller: SPUStandardUpdaterController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        if now {
            NSApp.activate(ignoringOtherApps: true)
            controller.updater.checkForUpdates()
        } else {
            controller.updater.checkForUpdatesInBackground()
        }
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func standardUserDriverWillFinishUpdateSession() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        // A background check that found nothing shows no window, so nothing else would end this process.
        if NSApp.windows.allSatisfy({ !$0.isVisible }) { exit(0) }
    }

    /// The menu bar item keeps running from the old copy, and relaunching the app would only bring that copy
    /// forward. So it quits first, and Sparkle's relaunch starts the new one.
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        let path = { (url: URL?) in url?.resolvingSymlinksInPath().standardizedFileURL.path }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        where path(app.bundleURL) == path(Bundle.main.bundleURL) && app.executableURL?.lastPathComponent == "PortsApp" {
            app.terminate()
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = Updater()
app.delegate = delegate
app.run()
