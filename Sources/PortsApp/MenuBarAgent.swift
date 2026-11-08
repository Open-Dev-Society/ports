import AppKit

let quitExitCode: Int32 = 42

/// Holds nothing but the menu bar item. Scanning runs in the `ports` helper, because scanning here
/// raised this process from 11 MB to 13 MB. The helper's JSON is passed on to the panel unread.
final class MenuBarAgent: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var panel: Process?
    private var cachedServers = "[]"
    private var scanning = false
    /// The first time Ports runs, the panel opens by itself so people see where the app lives.
    private var welcome = !(UserDefaults(suiteName: "io.github.open-dev-society.ports.settings")?.bool(forKey: "welcomed") ?? false)

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.font = .systemFont(ofSize: 13, weight: .medium)
            button.target = self
            button.action = #selector(togglePanel)
            button.image = portIcon()
        }
        enableLoginItemOnce()
        refresh()
        let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 10
        let updates = Timer(fire: Date(timeIntervalSinceNow: 60), interval: 24 * 3600, repeats: true) { [weak self] _ in self?.checkForUpdates() }
        updates.tolerance = 600
        RunLoop.main.add(updates, forMode: .common)
    }

    /// This target doesn't link PortsCore, so the argument is spelled out here.
    private func enableLoginItemOnce() {
        helper("PortsPanel", ["--enable-login-once"])
    }

    /// Sparkle lives in its own program, so it costs memory only while a check runs.
    private func checkForUpdates() {
        guard UserDefaults(suiteName: "io.github.open-dev-society.ports.settings")?.object(forKey: "automaticUpdates") as? Bool ?? true else { return }
        helper("PortsUpdater", [])
    }

    private func helper(_ name: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(name)
        process.arguments = arguments
        try? process.run()
    }

    private let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

    /// If an update replaced this app while it ran and nothing restarted it, start the new copy and quit.
    private func restartIfUpdated() {
        let plist = Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist), let onDisk = info["CFBundleVersion"] as? String, onDisk != version else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }

    private func refresh() {
        restartIfUpdated()
        guard !scanning, let helper = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("ports") else { return }
        scanning = true
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            let output = Pipe()
            process.executableURL = helper
            process.arguments = ["--menu-bar"]
            process.standardOutput = output
            try? process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", maxSplits: 1).map(String.init)
            DispatchQueue.main.async {
                self.scanning = false
                if process.terminationStatus == 0, lines.count == 2 { self.show(summary: lines[0], servers: lines[1]) }
            }
        }
    }

    /// `summary` is the helper's first line: count, total memory, and two budget shares the menu bar no longer draws.
    private func show(summary: String, servers: String) {
        guard let button = item.button else { return }
        cachedServers = servers
        let parts = summary.split(separator: "\t").map(String.init)
        guard parts.count == 4 else { return }
        let count = Int(parts[0]) ?? 0
        button.title = count == 0 ? "" : parts[1]
        button.toolTip = count == 0 ? "No dev servers running" : "\(count) dev \(count == 1 ? "server" : "servers") using \(parts[1])"
        button.setAccessibilityLabel(button.toolTip)
        if welcome, panel == nil { togglePanel() }
    }

    /// Lucide's "ethernet-port" (ISC licence, lucide.dev), drawn on its 24-point grid. A template image,
    /// so the system colours it for the menu bar like any other icon.
    private func portIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: true) { rect in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 15, y: 20))
            path.line(to: NSPoint(x: 18, y: 17))
            path.appendArc(from: NSPoint(x: 22, y: 17), to: NSPoint(x: 22, y: 4), radius: 2)
            path.appendArc(from: NSPoint(x: 22, y: 4), to: NSPoint(x: 2, y: 4), radius: 2)
            path.appendArc(from: NSPoint(x: 2, y: 4), to: NSPoint(x: 2, y: 17), radius: 2)
            path.appendArc(from: NSPoint(x: 2, y: 17), to: NSPoint(x: 6, y: 17), radius: 2)
            path.line(to: NSPoint(x: 6, y: 17))
            path.line(to: NSPoint(x: 9, y: 20))
            path.close()
            for x in [6, 10, 14, 18] {
                path.move(to: NSPoint(x: x, y: 8))
                path.line(to: NSPoint(x: x, y: 9))
            }
            path.transform(using: AffineTransform(scale: rect.width / 24))
            path.lineWidth = 2 * rect.width / 24
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Ports"
        return image
    }

    @objc private func togglePanel() {
        if let panel {
            panel.terminate()
            return
        }
        guard let button = item.button, let window = button.window, let helper = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("PortsPanel") else { return }
        let frame = window.frame
        let process = Process()
        process.executableURL = helper
        process.arguments = ["\(frame.minX)", "\(frame.minY)", "\(frame.width)", "\(frame.height)", cachedServers] + (welcome ? ["--welcome"] : [])
        welcome = false
        process.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                if finished.terminationStatus == quitExitCode { NSApp.terminate(nil) }
                self?.panel = nil
                self?.item.button?.highlight(false)
                self?.refresh()
            }
        }
        guard (try? process.run()) != nil else { return }
        panel = process
        button.highlight(true)
    }
}
