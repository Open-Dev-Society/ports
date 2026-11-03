import Darwin
import Foundation

public let portsVersion = "0.1.1"

/// One running server: every process in a process group that listens on a port.
public struct Server: Identifiable, Codable, Equatable {
    public let id: Int32  // the process group
    public let name: String
    public let project: String
    public let folder: String
    public let ports: [Int]
    public let memory: UInt64
    public let uptime: Int
    public let openToNetwork: Bool
    public let startedBy: String?
    public let idle: Bool
    public let isDevServer: Bool
}

// ponytail: "idle" means no client connected right now and up for hours. An open browser tab
// counts as in use. Per-server traffic tracking would be sharper if this nags wrongly.
let idleAfterSeconds = 3 * 3600

// MARK: - Scanning

public func scan() throws -> [Server] {
    let sockets = parseSockets(try run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN,ESTABLISHED", "-Fpn"]))
    let processes = try processList()
    let listeners = sockets.filter { !$0.value.ports.isEmpty && processes[$0.key] != nil }
    guard !listeners.isEmpty else { return [] }

    let folders = parseFolders(try run("/usr/sbin/lsof", ["-a", "-d", "cwd", "-p", listeners.keys.map(String.init).joined(separator: ","), "-Fpn"]))
    let home = NSHomeDirectory()
    let me = getuid()
    let groups = Dictionary(grouping: processes.values.filter { !$0.isZombie }, by: \.pgid)

    let servers: [Server] = Dictionary(grouping: listeners.keys.sorted(), by: { processes[$0]!.pgid }).map { pgid, pids in
        let members = groups[pgid] ?? []
        let isDev = pids.contains {
            processes[$0]!.uid == me && isDevServer(folder: folders[$0] ?? "", executable: executablePath($0), home: home)
        }
        let ports = Set(pids.flatMap { listeners[$0]!.ports }).sorted()
        let uptime = pids.map { processes[$0]!.elapsed }.max() ?? 0
        let connected = pids.contains { !listeners[$0]!.connected.isEmpty }
        let folder = pids.compactMap { folders[$0] }.first ?? ""
        return Server(
            id: pgid,
            name: serverName(listener: processes[pids[0]]!.command, members: members.map(\.command)),
            project: projectName(folder: folder, home: home),
            folder: folder,
            ports: ports,
            memory: members.reduce(0) { $0 + (footprint($1.pid) ?? 0) },
            uptime: uptime,
            openToNetwork: pids.contains { listeners[$0]!.open },
            startedBy: isDev ? startedBy(env(of: members.map(\.pid))) : nil,
            idle: !connected && uptime >= idleAfterSeconds,
            isDevServer: isDev
        )
    }
    return servers.sorted { $0.memory > $1.memory }
}

/// Real memory, including what has been swapped out. RSS read 25 MB for a server really using 3.8 GB.
func footprint(_ pid: Int32) -> UInt64? {
    var info = rusage_info_v2()
    let rc = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
    }
    return rc == 0 ? info.ri_phys_footprint : nil
}

func executablePath(_ pid: Int32) -> String {
    var buffer = [CChar](repeating: 0, count: 4096)
    return proc_pidpath(pid, &buffer, 4096) > 0 ? String(cString: buffer) : ""
}

func run(_ tool: String, _ arguments: [String]) throws -> String {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

// MARK: - Parsing

struct Sockets {
    var ports = Set<Int>()
    var connected = Set<Int>()
    var open = false
}

/// `lsof -Fpn`: `p<pid>` lines followed by `n<address>` lines. A name with `->` is a connection.
func parseSockets(_ output: String) -> [Int32: Sockets] {
    var result: [Int32: Sockets] = [:]
    var pid: Int32 = 0
    let lines = output.split(separator: "\n")
    for line in lines where line.first == "p" { pid = Int32(line.dropFirst()) ?? 0; result[pid] = Sockets() }
    for line in lines {
        if line.first == "p" { pid = Int32(line.dropFirst()) ?? 0 }
        guard line.first == "n", let colon = line.lastIndex(of: ":") else { continue }
        if let arrow = line.range(of: "->") {
            let local = line[..<arrow.lowerBound]
            if let c = local.lastIndex(of: ":"), let port = Int(local[local.index(after: c)...]) { result[pid]?.connected.insert(port) }
        } else if let port = Int(line[line.index(after: colon)...]) {
            result[pid]?.ports.insert(port)
            if ["*", "0.0.0.0", "[::]"].contains(String(line[line.index(after: line.startIndex)..<colon])) { result[pid]?.open = true }
        }
    }
    // Only connections made to this process's own listening ports are clients.
    for key in result.keys { result[key]!.connected.formIntersection(result[key]!.ports) }
    return result
}

func parseFolders(_ output: String) -> [Int32: String] {
    var result: [Int32: String] = [:]
    var pid: Int32 = 0
    for line in output.split(separator: "\n") {
        if line.first == "p" { pid = Int32(line.dropFirst()) ?? 0 }
        if line.first == "n" { result[pid] = String(line.dropFirst()) }
    }
    return result
}

struct ProcessInfoRow {
    let pid, ppid, pgid: Int32
    let uid: UInt32
    let elapsed: Int
    let isZombie: Bool
    let command: String
}

func processList() throws -> [Int32: ProcessInfoRow] {
    parseProcesses(try run("/bin/ps", ["-A", "-ww", "-o", "pid=,ppid=,pgid=,uid=,etime=,stat=,command="]))
}

func parseProcesses(_ output: String) -> [Int32: ProcessInfoRow] {
    var result: [Int32: ProcessInfoRow] = [:]
    for line in output.split(separator: "\n") {
        let f = line.split(maxSplits: 6, omittingEmptySubsequences: true, whereSeparator: { $0 == " " })
        guard f.count >= 6, let pid = Int32(f[0]), let ppid = Int32(f[1]), let pgid = Int32(f[2]), let uid = UInt32(f[3]) else { continue }
        result[pid] = ProcessInfoRow(
            pid: pid, ppid: ppid, pgid: pgid, uid: uid, elapsed: parseElapsed(String(f[4])),
            isZombie: f[5].hasPrefix("Z"), command: f.count > 6 ? String(f[6]) : "")
    }
    return result
}

/// `ps` etime: `[[dd-]hh:]mm:ss`.
func parseElapsed(_ text: String) -> Int {
    let dayParts = text.split(separator: "-")
    let days = dayParts.count == 2 ? Int(dayParts[0]) ?? 0 : 0
    let clock = (dayParts.last ?? "").split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
    return days * 86400 + clock
}

// MARK: - Naming

/// Hide apps and system services: a dev server runs from a folder of yours, not from an installed app.
func isDevServer(folder: String, executable: String, home: String) -> Bool {
    guard folder == home || folder.hasPrefix(home + "/"), !folder.hasPrefix(home + "/Library/") else { return false }
    // Apple's python3 and friends really run from inside Xcode.app, but they're still the user's tools.
    if executable.contains(".app/Contents/Developer/") { return true }
    let installed = ["/Applications/", "/System/", "/usr/libexec/", "/usr/sbin/", home + "/Applications/", home + "/Library/"]
    return !installed.contains { executable.hasPrefix($0) }
}

let knownTools = ["next", "vite", "wrangler", "astro", "nuxt", "remix", "webpack", "parcel", "gatsby", "storybook",
                  "rails", "uvicorn", "gunicorn", "flask", "http.server", "runserver", "hugo", "jekyll"]

/// Only the tool and script name, never the rest of the command line, which can hold secrets.
func serverName(listener: String, members: [String]) -> String {
    for command in [listener] + members {
        let words = command.split(separator: " ").map { String($0.split(separator: "/").last ?? "") }
        for (i, word) in words.enumerated() where knownTools.contains(word) || word.hasPrefix("next-server") {
            let tool = word.hasPrefix("next-server") ? "next" : word
            return i + 1 < words.count && words[i + 1] == "dev" || tool == "next" ? "\(tool) dev" : tool
        }
    }
    let words = listener.split(separator: " ").map(String.init)
    let program = (words.first ?? "server").split(separator: "/").last.map(String.init) ?? "server"
    guard let script = words.dropFirst().first(where: { !$0.hasPrefix("-") }) else { return program }
    return "\(program) \(script.split(separator: "/").last ?? "")"
}

/// The repo's name. In a git worktree that's the main repo, not the worktree's own folder.
func projectName(folder: String, home: String) -> String {
    var url = URL(fileURLWithPath: folder)
    while url.path.hasPrefix(home + "/") {
        let git = url.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: git.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue { return url.lastPathComponent }
            if let text = try? String(contentsOf: git, encoding: .utf8), let range = text.range(of: "/.git/worktrees/") {
                let path = text[..<range.lowerBound]
                return String(path.split(separator: "/").last ?? "")
            }
            return url.lastPathComponent
        }
        url.deleteLastPathComponent()
    }
    return folder == home ? "Home folder" : URL(fileURLWithPath: folder).lastPathComponent
}

/// Reads only these named variables, so nothing else in a process's environment is ever kept.
func env(of pids: [Int32]) -> [String: String] {
    guard !pids.isEmpty, let output = try? run("/bin/ps", ["eww", "-o", "command=", "-p", pids.map(String.init).joined(separator: ",")]) else { return [:] }
    var found: [String: String] = [:]
    for word in output.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
        for name in ["CLAUDECODE", "TERM_PROGRAM", "TMUX_PANE", "REX_BLOCK"] where word.hasPrefix(name + "=") {
            found[name] = String(word.dropFirst(name.count + 1))
        }
    }
    return found
}

func startedBy(_ env: [String: String]) -> String? {
    var terminal = env["TERM_PROGRAM"].map { ["Apple_Terminal": "Terminal", "iTerm.app": "iTerm", "vscode": "VS Code"][$0] ?? $0 }
    if terminal == nil, env["REX_BLOCK"] != nil { terminal = "rex" }
    if env["TMUX_PANE"] != nil { terminal = "tmux" }
    if env["CLAUDECODE"] != nil { return terminal.map { "Claude Code in \($0)" } ?? "Claude Code" }
    return terminal
}

// MARK: - Stopping

public enum StopResult: Equatable {
    case stopped
    case alreadyGone
    case refused(String)
    case stillRunning
    case restarted(port: Int)
}

let agentCommands: Set<String> = ["claude", "codex", "aider", "cursor-agent"]

/// Why this group must not be signalled, if it mustn't. Signalling a group takes every member with it,
/// so a server sharing a group with an agent or this tool's own terminal would take those down too.
func refusal(pgid: Int32, processes: [Int32: ProcessInfoRow], me: Int32) -> String? {
    if pgid <= 1 { return "That's part of macOS." }
    var pid = me
    while let row = processes[pid], pid > 1 {
        if row.pgid == pgid { return "It shares a process group with this tool." }
        pid = row.ppid
    }
    for row in processes.values where row.pgid == pgid {
        let program = row.command.split(separator: " ").first?.split(separator: "/").last.map(String.init) ?? ""
        if agentCommands.contains(program) { return "It runs alongside \(program), which would be stopped too." }
    }
    return nil
}

/// Stops the whole server, not just the pid on the port, so `pnpm` or `next dev` can't bring it back.
/// Scans again first, so a stale list can never signal a process group that has since been reused.
public func stop(_ server: Server) throws -> StopResult {
    // Ports can change while a server runs (`next dev` opens more), so any shared port counts as the same server.
    guard let current = try scan().first(where: { $0.id == server.id && !Set($0.ports).isDisjoint(with: server.ports) }) else { return .alreadyGone }
    return try stopCurrent(current)
}

func stopCurrent(_ server: Server) throws -> StopResult {
    guard server.isDevServer else { return .refused("It isn't a dev server.") }
    let processes = try processList()
    if let reason = refusal(pgid: server.id, processes: processes, me: getpid()) { return .refused(reason) }

    if kill(-server.id, SIGTERM) != 0 { return errno == ESRCH ? .alreadyGone : .refused(String(cString: strerror(errno))) }
    if try !waitUntilGone(server.id, seconds: 5) {
        kill(-server.id, SIGKILL)
        if try !waitUntilGone(server.id, seconds: 2) { return .stillRunning }
    }
    // Something outside the group, like a process manager, may bring it straight back.
    usleep(500_000)
    let sockets = parseSockets(try run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpn"]))
    let listening = Set(sockets.values.flatMap(\.ports))
    if let port = server.ports.first(where: listening.contains) { return .restarted(port: port) }
    return .stopped
}

func waitUntilGone(_ pgid: Int32, seconds: Double) throws -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    repeat {
        if !(try processList()).values.contains(where: { $0.pgid == pgid && !$0.isZombie }) { return true }
        usleep(100_000)
    } while Date() < deadline
    return false
}

// MARK: - Formatting

public func formatMemory(_ bytes: UInt64) -> String {
    let mb = Double(bytes) / 1_048_576
    return mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
}

public func formatUptime(_ seconds: Int) -> String {
    if seconds >= 86400 { return "\(seconds / 86400)d \(seconds % 86400 / 3600)h" }
    if seconds >= 3600 { return "\(seconds / 3600)h" }
    return "\(max(seconds / 60, 1))m"
}
