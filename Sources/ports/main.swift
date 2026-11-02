import Darwin
import Foundation
import PortsCore

let usage = """
    Which dev servers are running on your Mac, and what they cost you.

      ports                  list dev servers
      ports --all            include apps and system services
      ports stop PORT...     stop the servers on these ports (asks first)
      ports stop PORT... -y  stop without asking
      ports --version        show the version
    """

func fail(_ message: String) -> Never {
    fputs(message + "\n", stderr)
    exit(1)
}

func describe(_ server: Server) -> String {
    server.ports.map { ":\($0)" }.joined(separator: " ")
}

func list(all: Bool) throws {
    let servers = try scan()
    let shown = all ? servers : servers.filter(\.isDevServer)
    let total = shown.reduce(0) { $0 + $1.memory }
    let noun = all ? "listening" : shown.count == 1 ? "dev server" : "dev servers"
    print(shown.isEmpty ? "No dev servers running." : "\(shown.count) \(noun) · \(formatMemory(total))\n")
    for server in shown {
        var flags = [String]()
        if server.openToNetwork { flags.append("open to network") }
        if server.idle { flags.append("idle") }
        let tail = flags.isEmpty ? "" : "  " + flags.joined(separator: ", ")
        print(formatMemory(server.memory).padding(toLength: 8, withPad: " ", startingAt: 0)
            + " \(server.project)  \(server.name)  \(describe(server))  up \(formatUptime(server.uptime))\(tail)")
        let home = NSHomeDirectory()
        let folder = server.folder.hasPrefix(home) ? "~" + server.folder.dropFirst(home.count) : server.folder
        print("         \(folder)" + (server.startedBy.map { " · \($0)" } ?? ""))
    }
    let hidden = servers.count - shown.count
    if hidden > 0 { print("\n\(hidden) other listening, hidden. See them with: ports --all") }
    if let first = shown.first(where: \.isDevServer) { print("Stop one with: ports stop \(first.ports[0])") }
}

func stopPorts(_ arguments: [String]) throws {
    let yes = arguments.contains("-y") || arguments.contains("--yes")
    let ports = arguments.filter { !$0.hasPrefix("-") }
    guard !ports.isEmpty else { fail(usage) }
    let servers = try scan()
    var failed = false
    for text in ports {
        guard let port = Int(text) else { fail("\"\(text)\" isn't a port number.") }
        guard let server = servers.first(where: { $0.ports.contains(port) }) else {
            print("Nothing is listening on \(port).")
            continue
        }
        guard server.isDevServer else {
            print("Left \(port) alone: \(server.name) isn't a dev server.")
            failed = true
            continue
        }
        if !yes {
            guard isatty(STDIN_FILENO) == 1 else { fail("Not a terminal, so can't ask. Add -y to stop without asking.") }
            print("Stop \(server.project) (\(server.name), \(describe(server)), \(formatMemory(server.memory)))? [y/N] ", terminator: "")
            guard readLine()?.lowercased().hasPrefix("y") == true else { continue }
        }
        switch try stop(server) {
        case .stopped: print("Stopped \(server.project), freed about \(formatMemory(server.memory)).")
        case .alreadyGone: print("\(server.project) had already stopped.")
        case .refused(let reason): print("Left \(server.project) running: \(reason)"); failed = true
        case .stillRunning: print("\(server.project) is still running after being force-stopped."); failed = true
        case .restarted(let port): print("Stopped \(server.project), but something restarted it on \(port)."); failed = true
        }
    }
    if failed { exit(1) }
}

/// For the menu bar agent: a one-line summary, then the servers as JSON for the panel.
func menuBarOutput() throws {
    let servers = try scan().filter(\.isDevServer)
    let total = formatMemory(servers.reduce(0) { $0 + $1.memory })
    // The menu bar meter's two parts: the biggest project, then everything else, as shares of the budget.
    let byProject = Dictionary(grouping: servers, by: \.project).mapValues { $0.reduce(0) { $0 + $1.memory } }
    let capacity = Double(max(memoryBudget(), byProject.values.reduce(0, +)))
    let biggest = byProject.values.max() ?? 0
    let rest = byProject.values.reduce(0, +) - biggest
    print("\(servers.count)\t\(total)\t\(Double(biggest) / capacity)\t\(Double(rest) / capacity)")
    print(String(decoding: try JSONEncoder().encode(servers), as: UTF8.self))
}

let arguments = Array(CommandLine.arguments.dropFirst())
do {
    switch arguments.first {
    case nil: try list(all: false)
    case "--menu-bar": try menuBarOutput()
    case "--all", "-a": try list(all: true)
    case "stop": try stopPorts(Array(arguments.dropFirst()))
    case "--help", "-h", "help": print(usage)
    case "--version", "-v": print("ports \(portsVersion)")
    default: fail(usage)
    }
} catch {
    fail("Couldn't check running servers: \(error.localizedDescription)")
}
