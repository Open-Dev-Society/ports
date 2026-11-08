import Darwin
import Foundation

/// What it takes to start a stopped server again. It holds the whole environment, API keys included,
/// so it stays in memory for the few seconds Undo lasts and is never written to disk.
public struct StoppedServer: Identifiable, Equatable {
    public var id: String { "\(project):\(ports.first ?? 0)" }
    public let project: String
    public let name: String
    public let folder: String
    public let ports: [Int]
    public let memory: UInt64
    let executable: String
    let arguments: [String]
    let environment: [String: String]
}

let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish"]

/// Call this before stopping. The oldest process that isn't a shell wrapper is what started the server.
public func restartRecipe(for server: Server) -> StoppedServer? {
    guard let processes = try? processList() else { return nil }
    let members = processes.values.filter { $0.pgid == server.id && !$0.isZombie }.sorted { $0.elapsed > $1.elapsed }
    for member in members {
        let program = member.command.split(separator: " ").first?.split(separator: "/").last.map(String.init) ?? ""
        guard !shells.contains(program), !member.command.hasPrefix("next-server"),
              let data = processArguments(member.pid), let parsed = parseProcessArguments(data),
              let output = try? run("/usr/sbin/lsof", ["-a", "-d", "cwd", "-p", "\(member.pid)", "-Fpn"]),
              let folder = parseFolders(output)[member.pid] else { continue }
        return StoppedServer(
            project: server.project, name: server.name, folder: folder, ports: server.ports, memory: server.memory,
            executable: parsed.executable, arguments: Array(parsed.arguments.dropFirst()),
            environment: parsed.environment)
    }
    return nil
}

func processArguments(_ pid: Int32) -> Data? {
    var mib = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    guard sysctl(&mib, 3, nil, &size, nil, 0) == 0 else { return nil }
    var data = Data(count: size)
    let rc = data.withUnsafeMutableBytes { sysctl(&mib, 3, $0.baseAddress, &size, nil, 0) }
    return rc == 0 ? data.prefix(size) : nil
}

/// KERN_PROCARGS2: a 32-bit argc, the executable path, padding zeros, argv, then the environment.
func parseProcessArguments(_ data: Data) -> (executable: String, arguments: [String], environment: [String: String])? {
    guard data.count > 4 else { return nil }
    let argc = data.prefix(4).enumerated().reduce(0) { $0 + Int($1.element) << ($1.offset * 8) }
    let words = data.dropFirst(4).split(separator: 0, omittingEmptySubsequences: true).map { String(decoding: $0, as: UTF8.self) }
    guard words.count > argc, argc > 0, let executable = words.first else { return nil }
    var environment: [String: String] = [:]
    for word in words.dropFirst(argc + 1) {
        guard let equals = word.firstIndex(of: "=") else { continue }
        environment[String(word[..<equals])] = String(word[word.index(after: equals)...])
    }
    return (executable, Array(words[1...argc]), environment)
}

/// Starts it detached in its own session, so it outlives the panel and can be stopped as a group again.
public func start(_ server: StoppedServer) -> Bool {
    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    defer { posix_spawnattr_destroy(&attributes) }
    // Background threads block most signals and a child inherits that, which would leave the server
    // ignoring SIGTERM. So it gets a clean signal mask and default handlers.
    var noSignals = sigset_t(0)
    var allSignals = ~sigset_t(0)
    posix_spawnattr_setsigmask(&attributes, &noSignals)
    posix_spawnattr_setsigdefault(&attributes, &allSignals)
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF))
    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
    posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
    posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
    posix_spawn_file_actions_addchdir_np(&actions, server.folder)

    let argv = ([server.executable] + server.arguments).map { strdup($0) } + [nil]
    let envp = server.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
    defer { (argv + envp).forEach { free($0) } }
    var pid: pid_t = 0
    return posix_spawn(&pid, server.executable, &actions, &attributes, argv, envp) == 0
}

public func isListening(on ports: [Int]) -> Bool {
    guard let output = try? run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpn"]) else { return false }
    let listening = Set(parseSockets(output).values.flatMap(\.ports))
    return ports.contains(where: listening.contains)
}

let defaultsSuite = "io.github.open-dev-society.ports.settings"

// MARK: - Open at Login

public let enableLoginArgument = "--enable-login-once"

public func isInstalled(_ appPath: String, home: String = NSHomeDirectory()) -> Bool {
    appPath.hasPrefix("/Applications/") || appPath.hasPrefix(home + "/Applications/")
}

public func loginItemWasEnabled() -> Bool {
    UserDefaults(suiteName: defaultsSuite)?.bool(forKey: "loginItemEnabled") ?? false
}

public func setLoginItemWasEnabled() {
    UserDefaults(suiteName: defaultsSuite)?.set(true, forKey: "loginItemEnabled")
}

// MARK: - Updates

/// On unless turned off. The menu bar agent reads the same key without linking PortsCore.
public func automaticUpdates() -> Bool {
    UserDefaults(suiteName: defaultsSuite)?.object(forKey: "automaticUpdates") as? Bool ?? true
}

public func setAutomaticUpdates(_ on: Bool) {
    UserDefaults(suiteName: defaultsSuite)?.set(on, forKey: "automaticUpdates")
}

// MARK: - Welcome

public let welcomeArgument = "--welcome"

/// The menu bar agent reads the same key without linking PortsCore.
public func setWelcomed() {
    UserDefaults(suiteName: defaultsSuite)?.set(true, forKey: "welcomed")
}

// MARK: - Memory budget

public let budgetChoices = [2, 3, 4, 6, 8, 16]

/// A quarter of this Mac's memory, rounded down to a choice in the menu.
public func defaultBudget(physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) -> Int {
    budgetChoices.last { UInt64($0) << 30 <= physicalMemory / 4 } ?? budgetChoices[0]
}

public func memoryBudget() -> UInt64 {
    let gigabytes = UserDefaults(suiteName: defaultsSuite)?.integer(forKey: "budgetGB") ?? 0
    return UInt64(gigabytes > 0 ? gigabytes : defaultBudget()) << 30
}

public func setMemoryBudget(gigabytes: Int) {
    UserDefaults(suiteName: defaultsSuite)?.set(gigabytes, forKey: "budgetGB")
}
