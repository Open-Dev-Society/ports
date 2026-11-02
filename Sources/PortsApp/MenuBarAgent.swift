import AppKit

let quitExitCode: Int32 = 42

/// Holds nothing but the menu bar item. Scanning runs in the `ports` helper, because scanning here
/// raised this process from 11 MB to 13 MB. The helper's JSON is passed on to the panel unread.
final class MenuBarAgent: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var panel: Process?
    private var cachedServers = "[]"
    private var scanning = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
            button.target = self
            button.action = #selector(togglePanel)
            button.image = meter(first: 0, second: 0)
        }
        enableLoginItemOnce()
        refresh()
        let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 10
    }

    /// This target doesn't link PortsCore, so the argument is spelled out here.
    private func enableLoginItemOnce() {
        let process = Process()
        process.executableURL = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("PortsPanel")
        process.arguments = ["--enable-login-once"]
        try? process.run()
    }

    private func refresh() {
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

    /// `summary` is the helper's first line: count, total memory, and the meter's two shares.
    private func show(summary: String, servers: String) {
        guard let button = item.button else { return }
        cachedServers = servers
        let parts = summary.split(separator: "\t").map(String.init)
        guard parts.count == 4 else { return }
        let count = Int(parts[0]) ?? 0
        button.image = meter(first: Double(parts[2]) ?? 0, second: Double(parts[3]) ?? 0)
        button.title = count == 0 ? "" : parts[1]
        button.toolTip = count == 0 ? "No dev servers running" : "\(count) dev \(count == 1 ? "server" : "servers") using \(parts[1])"
        button.setAccessibilityLabel(button.toolTip)
    }

    /// A template image, so the system colours it for the menu bar like any other icon.
    private func meter(first: Double, second: Double) -> NSImage {
        let image = NSImage(size: NSSize(width: 26, height: 6), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).addClip()
            NSColor.black.withAlphaComponent(0.25).setFill()
            rect.fill()
            let firstWidth = (rect.width * first).rounded()
            NSColor.black.setFill()
            NSRect(x: 0, y: 0, width: firstWidth, height: rect.height).fill()
            NSColor.black.withAlphaComponent(0.6).setFill()
            NSRect(x: firstWidth + 1, y: 0, width: (rect.width * second).rounded(), height: rect.height).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Ports memory meter"
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
        process.arguments = ["\(frame.minX)", "\(frame.minY)", "\(frame.width)", "\(frame.height)", cachedServers]
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
