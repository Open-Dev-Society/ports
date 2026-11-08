import AppKit
import PortsCore
import ServiceManagement

let quitExitCode: Int32 = 42
let panelWidth: CGFloat = 348

/// The popover, in its own short-lived process. Apple's guidance is that popovers adopt Liquid Glass
/// by themselves and that custom backgrounds should go, so the glass here is all the system's.
final class PanelApp: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let anchorFrame: NSRect
    private var servers: [Server]
    /// Just stopped and still undoable. Kept in memory only, so closing the panel makes the stop final.
    private var stopped: [StoppedServer] = []
    private var stoppedIdle = false
    private var starting = false
    private var undoTimer: Timer?
    private var undoSeconds = 0
    private weak var undoButton: NSButton?
    private var anchor: NSWindow!
    private let popover = NSPopover()
    private let root = NSStackView()
    private var selected: String?
    private var confirming = false
    private var working: String?
    private var message: String?
    /// The page of the first-run welcome being shown, or nil once it's done.
    private var welcomeStep: Int?

    init(arguments: [String]) {
        let n = arguments.dropFirst(1).prefix(4).map { Double($0) ?? 0 }
        anchorFrame = n.count == 4 ? NSRect(x: n[0], y: n[1], width: n[2], height: n[3]) : .zero
        servers = arguments.count > 5 ? (try? JSONDecoder().decode([Server].self, from: Data(arguments[5].utf8))) ?? [] : []
        welcomeStep = arguments.dropFirst(6).first == welcomeArgument ? 0 : nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A popover can only point at a view in its own process, so this stands in for the menu bar icon.
        anchor = NSWindow(contentRect: anchorFrame, styleMask: .borderless, backing: .buffered, defer: false)
        anchor.isOpaque = false
        anchor.backgroundColor = .clear
        anchor.ignoresMouseEvents = true
        anchor.level = .statusBar
        anchor.orderFront(nil)

        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false
        root.widthAnchor.constraint(equalToConstant: panelWidth + 32).isActive = true

        let controller = NSViewController()
        controller.view = root
        popover.contentViewController = controller
        // Not .transient: since macOS 14 this process may not be allowed to become active, and a
        // transient popover in an inactive app can close the moment it opens.
        popover.behavior = .applicationDefined
        popover.delegate = self
        // Seen once is enough: closing it early shouldn't make it reappear at every login.
        if welcomeStep != nil { setWelcomed() }
        rebuild()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: anchor.contentView!.bounds, of: anchor.contentView!, preferredEdge: .minY)
        rescan()

        // Clicks on the menu bar icon are left to the agent, or closing here would make it reopen.
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, !self.anchorFrame.contains(NSEvent.mouseLocation) else { return }
            self.popover.close()
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }  // Escape
            self?.popover.close()
            return nil
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        popover.close()
    }

    func popoverDidClose(_ notification: Notification) {
        exit(0)
    }

    private func rescan() {
        DispatchQueue.global(qos: .userInitiated).async {
            let found = (try? scan())?.filter(\.isDevServer)
            DispatchQueue.main.async {
                guard let found else { return }
                // A stopped server someone has started again by other means is no longer stopped.
                let busy = Set(found.flatMap(\.ports))
                self.stopped.removeAll { !busy.isDisjoint(with: $0.ports) }
                if found != self.servers {
                    self.servers = found
                }
                self.rebuild()
            }
        }
    }

    // MARK: Numbers

    private var used: UInt64 { servers.reduce(0) { $0 + $1.memory } }
    private var budget: UInt64 { memoryBudget() }
    private var capacity: UInt64 { max(budget, used) }
    private var free: UInt64 { capacity - used }
    private var idle: [Server] { servers.filter(\.idle) }
    private var hasSelection: Bool { servers.contains { "\($0.id)" == selected } }

    private var items: [MapItem] {
        servers.map {
            MapItem(id: "\($0.id)", project: $0.project, port: $0.ports.first ?? 0, memory: $0.memory, idle: $0.idle, stopped: false)
        } + stopped.map {
            MapItem(id: $0.id, project: $0.project, port: $0.ports.first ?? 0, memory: $0.memory, idle: false, stopped: true)
        }
    }

    /// Running memory per project, biggest first, so colours match the treemap's columns.
    private var projects: [(name: String, memory: UInt64)] {
        func total(_ items: [MapItem]) -> UInt64 { items.reduce(0) { $0 + $1.memory } }
        let groups = Dictionary(grouping: items, by: \.project)
        let names = groups.keys.sorted { a, b in
            let (sizeA, sizeB) = (total(groups[a]!), total(groups[b]!))
            return sizeA != sizeB ? sizeA > sizeB : a < b
        }
        return names.map { (name: $0, memory: total(groups[$0]!.filter { !$0.stopped })) }
    }

    // MARK: Layout

    private func rebuild() {
        root.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let welcomeStep {
            welcome(welcomeStep).forEach { add($0) }
            root.layoutSubtreeIfNeeded()
            popover.contentSize = root.fittingSize
            return
        }
        add(header())
        add(MeterView(segments: projects.enumerated().map { (Double($0.element.memory) / Double(capacity), Palette.bar($0.offset)) },
                      budgetShare: Double(budget) / Double(capacity)), height: 30)
        add(treemap(), height: 200)
        add(detailLine(), height: 26)
        add(legend())
        if let footer = footer() { add(footer) }
        root.layoutSubtreeIfNeeded()
        popover.contentSize = root.fittingSize
    }

    private func add(_ view: NSView, height: CGFloat? = nil) {
        root.addArrangedSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: panelWidth).isActive = true
        if let height { view.heightAnchor.constraint(equalToConstant: height).isActive = true }
    }

    private func header() -> NSView {
        let title = text("Dev servers", font: .systemFont(ofSize: 12, weight: .medium), color: .secondaryLabelColor)
        let amount = text(formatMemory(used), font: .monospacedSystemFont(ofSize: 26, weight: .medium))
        let limit = text("/ \(budget >> 30) GB", font: .monospacedSystemFont(ofSize: 12, weight: .regular), color: .secondaryLabelColor)
        let number = row([amount, limit], spacing: 6)
        number.alignment = .lastBaseline
        let left = NSStackView(views: [title, number])
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 2

        let settings = NSButton(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings") ?? NSImage(),
                                target: self, action: #selector(showSettings(_:)))
        settings.isBordered = false
        settings.contentTintColor = .secondaryLabelColor
        settings.toolTip = "Settings"
        // Stack views centre across a row by default, which lines the gear up with the pill.
        let controls = row([StatusPill(status: BudgetStatus(used: used, budget: budget)), settings], spacing: 8)
        let line = row([left, spacer(), controls], spacing: 8)
        line.alignment = .top
        return line
    }

    private func treemap() -> NSView {
        let map = NSView()
        let size = CGSize(width: panelWidth, height: 200)
        for tile in layoutTreemap(items: items, capacity: capacity, size: size) {
            let flipped = NSRect(x: tile.frame.minX, y: size.height - tile.frame.maxY, width: tile.frame.width, height: tile.frame.height)
            let view = tileView(tile, frame: flipped)
            if hasSelection && !view.chosen { view.alphaValue = 0.35 }
            map.addSubview(view)
        }
        return map
    }

    private func tileView(_ tile: MapTile, frame: NSRect) -> TileButton {
        switch tile.kind {
        case .free:
            return TileButton(frame: frame, style: .free, title: "", value: "\(formatMemory(free)) free", color: .labelColor, moon: false, selected: false, target: nil, action: nil, id: "free")
        case .more(let rest):
            let memory = rest.filter { !$0.stopped }.reduce(0) { $0 + $1.memory }
            let button = TileButton(frame: frame, style: .solid, title: "+\(rest.count) more", value: formatMemory(memory), color: Palette.tile(tile.color),
                                    moon: rest.contains(where: \.idle), selected: rest.contains { $0.id == selected }, target: self, action: #selector(moreClicked(_:)), id: "more")
            button.items = rest
            button.setAccessibilityLabel("\(rest.count) more servers, \(formatMemory(memory))")
            return button
        case .server(let item, let showsProject):
            let title = showsProject ? item.project : ":\(item.port)"
            let value = item.stopped ? (starting ? "starting…" : "stopped") : working == item.id ? "stopping…" : formatMemory(item.memory)
            let button = TileButton(frame: frame, style: item.stopped ? .dashed : .solid, title: title, value: value, color: Palette.tile(tile.color),
                                    moon: item.idle, selected: selected == item.id, target: self, action: #selector(tileClicked(_:)), id: item.id)
            button.items = [item]
            let state = item.stopped ? "stopped" : item.idle ? "\(value), idle" : value
            button.setAccessibilityLabel("\(item.project) port \(item.port), \(state)")
            button.menu = contextMenu(for: item)
            return button
        }
    }

    private func contextMenu(for item: MapItem) -> NSMenu? {
        let menu = NSMenu()
        if let folder = servers.first(where: { "\($0.id)" == item.id })?.folder {
            let reveal = NSMenuItem(title: "Show in Finder", action: #selector(showInFinder(_:)), keyEquivalent: "")
            reveal.target = self
            reveal.representedObject = folder
            menu.addItem(reveal)
        }
        return menu
    }

    private func detailLine() -> NSView {
        guard let id = selected, let server = servers.first(where: { "\($0.id)" == id }) else {
            let hint = servers.isEmpty ? "No dev servers running" : "Click a tile to open or stop it"
            return row([text(hint, font: .systemFont(ofSize: 12), color: .secondaryLabelColor)], spacing: 6)
        }
        let port = server.ports.first.map { ":\($0)" } ?? ""
        let more = server.ports.count > 1 ? " +\(server.ports.count - 1)" : ""
        let who = server.startedBy.map { " · \($0)" } ?? ""
        let details = text("\(server.name) · \(port)\(more) · \(formatUptime(server.uptime))\(who)", font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        details.toolTip = server.folder
        var views: [NSView] = [details, spacer()]
        if confirming {
            views.append(button("Keep", action: #selector(keepPressed), label: "Keep \(server.project) running"))
            let confirm = button("Stop", action: #selector(stopPressed), label: "Confirm stopping \(server.project)")
            confirm.hasDestructiveAction = true
            confirm.bezelColor = .systemRed
            confirm.contentTintColor = .white
            views.append(confirm)
        } else {
            views.append(button("Open", action: #selector(openPressed), label: "Open \(server.project) in your browser"))
            views.append(button("Stop", action: #selector(stopPressed), label: "Stop \(server.project)"))
        }
        return row(views, spacing: 6)
    }

    private func legend() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.addArrangedSubview(separator())
        let running = Array(projects.enumerated())
        for (index, project) in running.prefix(4) where project.memory > 0 {
            stack.addArrangedSubview(legendRow(project.name, memory: project.memory, color: Palette.bar(index), primary: true))
        }
        let others = running.dropFirst(4).reduce(0) { $0 + $1.element.memory }
        if others > 0 {
            stack.addArrangedSubview(legendRow("\(running.count - 4) more", memory: others, color: .tertiaryLabelColor, primary: true))
        }
        if free > 0 {
            stack.addArrangedSubview(legendRow("Free", memory: free, color: NSColor.labelColor.withAlphaComponent(0.28), primary: false))
        }
        stack.arrangedSubviews.forEach { $0.widthAnchor.constraint(equalToConstant: panelWidth).isActive = true }
        return stack
    }

    private func legendRow(_ name: String, memory: UInt64, color: NSColor, primary: Bool) -> NSView {
        let swatch = Swatch(color: color)
        let label = text(name, font: .systemFont(ofSize: 12), color: primary ? .labelColor : .secondaryLabelColor)
        let amount = text(formatMemory(memory), font: .monospacedSystemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)
        let share = text("\(Int((Double(memory) / Double(capacity) * 100).rounded()))%", font: .monospacedSystemFont(ofSize: 11, weight: .regular), color: .tertiaryLabelColor)
        share.alignment = .right
        share.widthAnchor.constraint(equalToConstant: 32).isActive = true
        let line = row([swatch, label, spacer(), amount, share], spacing: 8)
        line.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return line
    }

    private func footer() -> NSView? {
        if !stopped.isEmpty {
            let noun = stopped.count == 1 ? "server" : "servers"
            let done = text("\(starting ? "Starting" : "Stopped") \(stopped.count) \(stoppedIdle ? "idle " : "")\(noun)", font: .systemFont(ofSize: 12))
            let line = row([icon("checkmark", color: .systemGreen), done, spacer()], spacing: 6)
            if !starting {
                let undo = button("Undo (\(undoSeconds))", action: #selector(undoPressed), label: "Start those servers again")
                undoButton = undo
                line.addArrangedSubview(undo)
            }
            return line
        }
        if let message {
            return row([icon("exclamationmark.triangle", color: .systemOrange), text(message, font: .systemFont(ofSize: 12), color: .secondaryLabelColor)], spacing: 6)
        }
        let reachable = servers.filter(\.openToNetwork).count
        guard reachable > 0 || !idle.isEmpty else { return nil }
        var views: [NSView] = []
        if reachable > 0 {
            views.append(icon("wifi", color: .systemOrange))
            let label = text("\(reachable) reachable on Wi-Fi", font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
            label.toolTip = "Others on the same network may be able to open these servers."
            views.append(label)
        }
        views.append(spacer())
        if !idle.isEmpty {
            let stop = button("Stop \(idle.count) Idle", action: #selector(stopIdlePressed), label: "Stop \(idle.count) idle servers")
            stop.bezelColor = .controlAccentColor
            stop.toolTip = "Running for hours with nothing connected to them right now."
            views.append(stop)
        }
        return row(views, spacing: 6)
    }

    // MARK: Welcome

    /// Three short pages inside the panel itself, so it points straight at the icon people will use.
    private func welcome(_ step: Int) -> [NSView] {
        var views: [NSView] = []
        switch step {
        case 0:
            let logo = NSImageView(image: NSApp.applicationIconImage)
            logo.widthAnchor.constraint(equalToConstant: 64).isActive = true
            logo.heightAnchor.constraint(equalToConstant: 64).isActive = true
            views.append(row([logo, spacer()], spacing: 0))
            let count = servers.count
            let headline = count == 0 ? "No dev servers are running right now."
                : "\(count) dev \(count == 1 ? "server is" : "servers are") using \(formatMemory(used)) right now."
            views += heading("Welcome to Ports", headline)
            views.append(paragraph("Ports lives in your menu bar, just above this. It finds the local servers that you, your terminal and your coding agents start, and shows what each one costs."))
        case 1:
            views += heading("Reading the panel", "One tile for each server")
            // An example drawn with the panel's own tiles.
            let example = NSView()
            example.heightAnchor.constraint(equalToConstant: 48).isActive = true
            var x: CGFloat = 0
            for (index, (title, value, width, moon)) in [("storefront", "1.2 GB", 176.0, false), ("api", "610 MB", 108.0, true), (":5173", "240 MB", 56.0, false)].enumerated() {
                let tile = TileButton(frame: NSRect(x: x, y: 0, width: width, height: 48), style: .solid, title: title, value: value, color: Palette.tile(index),
                                      moon: moon, selected: false, target: nil, action: nil, id: title)
                tile.setAccessibilityElement(false)
                example.addSubview(tile)
                x += width + 4
            }
            views.append(example)
            views.append(explanation(icon("cursorarrow.click", color: .labelColor), "Bigger tiles use more memory. Click one to open or stop it."))
            views.append(explanation(icon("moon", color: .labelColor), "Idle: up for three hours with nothing connected. Stop Idle stops them all."))
            views.append(explanation(icon("wifi", color: .systemOrange), "Reachable on Wi-Fi: others on your network may be able to open it."))
            views.append(explanation(icon("arrow.uturn.backward", color: .labelColor), "Stopped the wrong one? Undo lasts five seconds."))
        default:
            views += heading("Stays out of your way", "About 12 MB, and nothing leaves your Mac")
            views.append(paragraph("No account and no network requests. Click the icon in your menu bar whenever you want to check."))
            let login = NSButton(checkboxWithTitle: "Open Ports when you log in", target: self, action: #selector(toggleLogin))
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            views.append(login)
            if let message { views.append(paragraph(message, font: .systemFont(ofSize: 12), color: .systemOrange)) }
        }

        let last = step == 2
        let next = button(last ? "Show My Servers" : "Continue", action: #selector(welcomeNext), label: last ? "Finish and show your servers" : "Next page")
        next.bezelColor = .controlAccentColor
        next.keyEquivalent = "\r"
        var controls: [NSView] = [PageDots(count: 3, current: step), spacer()]
        if step > 0 { controls.append(button("Back", action: #selector(welcomeBack), label: "Previous page")) }
        controls.append(next)
        views.append(row(controls, spacing: 6))
        return views
    }

    private func heading(_ caption: String, _ title: String) -> [NSView] {
        let small = text(caption, font: .systemFont(ofSize: 12, weight: .medium), color: .secondaryLabelColor)
        let big = paragraph(title, font: .systemFont(ofSize: 17, weight: .semibold), color: .labelColor)
        let stack = NSStackView(views: [small, big])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        return [stack]
    }

    private func explanation(_ visual: NSView, _ words: String) -> NSView {
        visual.translatesAutoresizingMaskIntoConstraints = false
        let slot = NSView()
        slot.addSubview(visual)
        NSLayoutConstraint.activate([
            slot.widthAnchor.constraint(equalToConstant: 24),
            slot.heightAnchor.constraint(equalToConstant: 18),
            visual.centerXAnchor.constraint(equalTo: slot.centerXAnchor),
            visual.centerYAnchor.constraint(equalTo: slot.centerYAnchor),
        ])
        let line = row([slot, paragraph(words, width: panelWidth - 34)], spacing: 10)
        line.alignment = .top
        return line
    }

    @objc private func welcomeNext() {
        welcomeStep = welcomeStep.flatMap { $0 < 2 ? $0 + 1 : nil }
        rebuild()
    }

    @objc private func welcomeBack() {
        welcomeStep = welcomeStep.map { max($0 - 1, 0) }
        rebuild()
    }

    // MARK: Actions

    @objc private func tileClicked(_ sender: TileButton) {
        guard let item = sender.items.first else { return }
        select(selected == item.id ? nil : item.id)
    }

    @objc private func moreClicked(_ sender: TileButton) {
        let menu = NSMenu()
        for item in sender.items {
            let title = item.stopped ? "\(item.project) :\(item.port)  stopped" : "\(item.project) :\(item.port)  \(formatMemory(item.memory))"
            let entry = NSMenuItem(title: title, action: item.stopped ? nil : #selector(moreItemChosen(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = item.id
            menu.addItem(entry)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func moreItemChosen(_ sender: NSMenuItem) {
        select(sender.representedObject as? String)
    }

    private func select(_ id: String?) {
        selected = id
        confirming = false
        rebuild()
    }

    @objc private func openPressed() {
        if let port = servers.first(where: { "\($0.id)" == selected })?.ports.first, let url = URL(string: "http://localhost:\(port)") {
            NSWorkspace.shared.open(url)
            popover.close()
        }
    }

    @objc private func keepPressed() {
        confirming = false
        rebuild()
    }

    @objc private func stopPressed() {
        guard let server = servers.first(where: { "\($0.id)" == selected }) else { return }
        guard confirming else {
            confirming = true
            rebuild()
            return
        }
        confirming = false
        selected = nil
        working = "\(server.id)"
        rebuild()
        stoppedIdle = false
        stopServers([server])
    }

    @objc private func stopIdlePressed() {
        stoppedIdle = stopped.isEmpty
        stopServers(idle)
    }

    /// Takes each server's restart recipe first, because once it has stopped there's nothing left to read.
    private func stopServers(_ targets: [Server]) {
        DispatchQueue.global(qos: .userInitiated).async {
            var done: [StoppedServer] = []
            var failure: String?
            var restartable = true
            // The panel opens with the agent's last scan, so a tile may name a server that has since restarted.
            let current = (try? scan()) ?? []
            for listed in targets {
                let server = current.first { $0.project == listed.project && !Set($0.ports).isDisjoint(with: listed.ports) } ?? listed
                let recipe = restartRecipe(for: server)
                switch try? stop(server) {
                case .stopped?, .alreadyGone?:
                    if let recipe { done.append(recipe) } else { restartable = false }
                case .refused(let reason)?: failure = "\(server.project) left running. \(reason)"
                case .restarted?: failure = "Stopped \(server.project), but something started it again."
                case .stillRunning?, nil: failure = "Couldn't stop \(server.project)."
                }
            }
            if !restartable, failure == nil { failure = "Stopped, but one server can't be started again from here." }
            DispatchQueue.main.async {
                self.working = nil
                self.stopped = done + self.stopped.filter { old in !done.contains { $0.id == old.id } }
                self.servers.removeAll { targets.map(\.id).contains($0.id) }
                self.message = failure
                if !self.stopped.isEmpty { self.startUndoCountdown() }
                self.rebuild()
                self.rescan()
            }
        }
    }

    /// Undo lasts five seconds. After that the dashed tiles go and the grid closes up.
    private func startUndoCountdown() {
        undoTimer?.invalidate()
        undoSeconds = 5
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.undoSeconds -= 1
            self.undoButton?.title = "Undo (\(self.undoSeconds))"
            if self.undoSeconds == 0 || self.stopped.isEmpty {
                self.undoTimer?.invalidate()
                self.stopped = []
                self.rebuild()
            }
        }
        undoTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func undoPressed() {
        undoTimer?.invalidate()
        let list = stopped
        starting = true
        message = nil
        rebuild()
        DispatchQueue.global(qos: .userInitiated).async {
            let failed = list.first { !(start($0) && waitUntilListening($0)) }
            DispatchQueue.main.async {
                self.starting = false
                self.stopped = []
                if let failed { self.message = "\(failed.project) didn't start. It may need its own terminal." }
                self.rebuild()
                self.rescan()
            }
        }
    }

    @objc private func showInFinder(_ sender: NSMenuItem) {
        if let folder = sender.representedObject as? String {
            NSWorkspace.shared.open(URL(fileURLWithPath: folder))
        }
    }

    @objc private func showSettings(_ sender: NSButton) {
        let menu = NSMenu()
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let budgets = NSMenu()
        for gigabytes in budgetChoices {
            let item = NSMenuItem(title: "\(gigabytes) GB", action: #selector(setBudget(_:)), keyEquivalent: "")
            item.target = self
            item.tag = gigabytes
            item.state = budget == UInt64(gigabytes) << 30 ? .on : .off
            budgets.addItem(item)
        }
        let budgetItem = NSMenuItem(title: "Memory Budget", action: nil, keyEquivalent: "")
        budgetItem.submenu = budgets
        menu.addItem(budgetItem)
        menu.addItem(.separator())
        let check = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        check.target = self
        menu.addItem(check)
        let automatic = NSMenuItem(title: "Check Automatically", action: #selector(toggleAutomaticUpdates), keyEquivalent: "")
        automatic.target = self
        automatic.state = automaticUpdates() ? .on : .off
        menu.addItem(automatic)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Ports", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func setBudget(_ sender: NSMenuItem) {
        setMemoryBudget(gigabytes: sender.tag)
        rebuild()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            message = "Move Ports to Applications first."
            rebuild()
        }
    }

    /// Sparkle runs in its own program, which outlives the panel and shows its own window.
    @objc private func checkForUpdates() {
        let process = Process()
        process.executableURL = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("PortsUpdater")
        process.arguments = ["--now"]
        try? process.run()
        popover.close()
    }

    @objc private func toggleAutomaticUpdates() {
        setAutomaticUpdates(!automaticUpdates())
    }

    @objc private func quit() {
        exit(quitExitCode)
    }

    // MARK: Parts

    private func text(_ value: String, font: NSFont, color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: value)
        field.font = font
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    private func paragraph(_ value: String, width: CGFloat = panelWidth, font: NSFont = .systemFont(ofSize: 13), color: NSColor = .secondaryLabelColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: value)
        field.font = font
        field.textColor = color
        field.preferredMaxLayoutWidth = width
        field.isSelectable = false
        return field
    }

    private func icon(_ symbol: String, color: NSColor) -> NSImageView {
        let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        image.symbolConfiguration = .init(pointSize: 12, weight: .regular)
        image.contentTintColor = color
        return image
    }

    private func button(_ title: String, action: Selector, label: String) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.controlSize = .small
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.setAccessibilityLabel(label)
        return button
    }

    private func row(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = spacing
        return stack
    }

    private func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.init(1), for: .horizontal)
        view.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        return view
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
}

private func waitUntilListening(_ server: StoppedServer) -> Bool {
    for _ in 0..<60 {
        if isListening(on: server.ports) { return true }
        usleep(500_000)
    }
    return false
}
