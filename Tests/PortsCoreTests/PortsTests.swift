import Foundation
import XCTest

@testable import PortsCore

final class ParsingTests: XCTestCase {
    func testSocketsSeparateListenersFromClients() {
        let output = """
            p10
            f5
            n*:3000
            f6
            n127.0.0.1:3000->127.0.0.1:5555
            f7
            n192.168.1.2:6000->1.2.3.4:443
            p20
            f5
            n127.0.0.1:4000
            f6
            n[::1]:4001
            f7
            n127.0.0.1:50000->127.0.0.1:443
            """
        let sockets = parseSockets(output)
        XCTAssertEqual(sockets[10]?.ports, [3000])
        XCTAssertEqual(sockets[10]?.connected, [3000])
        XCTAssertEqual(sockets[10]?.open, true)
        XCTAssertEqual(sockets[20]?.ports, [4000, 4001])
        XCTAssertEqual(sockets[20]?.connected, [], "outgoing connections aren't clients")
        XCTAssertEqual(sockets[20]?.open, false)
    }

    func testElapsed() {
        XCTAssertEqual(parseElapsed("08:25"), 505)
        XCTAssertEqual(parseElapsed("11:28:02"), 41282)
        XCTAssertEqual(parseElapsed("01-09:56:24"), 122184)
    }

    func testProcessRow() {
        let row = parseProcesses("30101 30079 30073 501 11:28:02 S next-server (v14.2.15) \n")[30101]
        XCTAssertEqual(row?.pgid, 30073)
        XCTAssertEqual(row?.command, "next-server (v14.2.15) ")
        XCTAssertEqual(parseProcesses("9 1 9 501 00:01 Z+ \n")[9]?.isZombie, true)
    }

    func testDevServerFilter() {
        let home = "/Users/a"
        XCTAssertTrue(isDevServer(folder: "/Users/a/work/app", executable: "/opt/homebrew/bin/node", home: home))
        XCTAssertTrue(isDevServer(folder: "/Users/a/.config/agent/worktrees/x", executable: "/usr/local/bin/node", home: home))
        XCTAssertTrue(isDevServer(folder: "/Users/a/work", executable: "/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python", home: home), "Apple's python3")
        XCTAssertTrue(isDevServer(folder: "/Users/a/work", executable: "/Library/Developer/CommandLineTools/usr/bin/python3", home: home))
        XCTAssertFalse(isDevServer(folder: "/", executable: "/Applications/Spotify.app/Contents/MacOS/Spotify", home: home))
        XCTAssertFalse(isDevServer(folder: "/", executable: "/opt/homebrew/bin/node", home: home), "no folder of yours")
        XCTAssertFalse(isDevServer(folder: "/Users/a/work", executable: "/Applications/App.app/Contents/MacOS/x", home: home))
        XCTAssertFalse(isDevServer(folder: "/Users/a/Library/Caches", executable: "/opt/homebrew/bin/node", home: home))
        XCTAssertFalse(isDevServer(folder: "/Users/ab/work", executable: "/opt/homebrew/bin/node", home: home), "someone else's home")
    }

    func testServerNames() {
        XCTAssertEqual(serverName(listener: "next-server (v14.2.15) ", members: []), "next dev")
        XCTAssertEqual(serverName(listener: "node ./node_modules/.bin/../next/dist/bin/next dev --turbo -p 3001", members: []), "next dev")
        XCTAssertEqual(serverName(listener: "node /a/node_modules/.bin/vite --port 1", members: []), "vite")
        XCTAssertEqual(serverName(listener: "node server.mjs", members: []), "node server.mjs")
        XCTAssertEqual(serverName(listener: "node --env-file=/secret/.env server.mjs", members: []), "node server.mjs")
        XCTAssertEqual(serverName(listener: "node /tmp/x/y/tool.mjs --token=abc", members: []), "node tool.mjs")
        XCTAssertEqual(serverName(listener: "/usr/bin/python3 -m http.server 8000", members: []), "http.server")
    }

    func testStartedBy() {
        XCTAssertEqual(startedBy(["CLAUDECODE": "1", "TERM_PROGRAM": "rex", "REX_BLOCK": "b"]), "Claude Code in rex")
        XCTAssertEqual(startedBy(["TERM_PROGRAM": "Apple_Terminal"]), "Terminal")
        XCTAssertEqual(startedBy(["REX_BLOCK": "b"]), "rex")
        XCTAssertNil(startedBy([:]))
    }

    func testRefusesGroupsItCouldHarm() {
        func row(_ pid: Int32, _ ppid: Int32, _ pgid: Int32, _ command: String) -> ProcessInfoRow {
            ProcessInfoRow(pid: pid, ppid: ppid, pgid: pgid, uid: 501, elapsed: 0, isZombie: false, command: command)
        }
        let processes: [Int32: ProcessInfoRow] = [
            1: row(1, 0, 1, "launchd"),
            50: row(50, 1, 50, "/bin/zsh"),
            51: row(51, 50, 50, "ports"),
            60: row(60, 1, 60, "/usr/local/bin/claude --resume"),
            61: row(61, 60, 60, "node server.mjs"),
            70: row(70, 1, 70, "node server.mjs"),
        ]
        XCTAssertNotNil(refusal(pgid: 1, processes: processes, me: 51))
        XCTAssertNotNil(refusal(pgid: 50, processes: processes, me: 51), "own terminal")
        XCTAssertNotNil(refusal(pgid: 60, processes: processes, me: 51), "agent in the group")
        XCTAssertNil(refusal(pgid: 70, processes: processes, me: 51))
    }
}

/// Starts real throwaway servers. Never touches anything it didn't start.
final class LiveServerTests: XCTestCase {
    private var started: [Process] = []

    override func tearDown() {
        for process in started where process.isRunning { kill(-process.processIdentifier, SIGKILL) }
    }

    /// A shell in its own process group, like a server in a terminal. Runs from a folder under home.
    private func launch(_ script: String, port: Int) throws -> Server {
        let folder = NSHomeDirectory() + "/.ports-test-\(port)"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: folder) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", "use POSIX; POSIX::setsid(); exec('/bin/sh','-c',$ARGV[0])", script]
        process.currentDirectoryURL = URL(fileURLWithPath: folder)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        started.append(process)
        for _ in 0..<50 {
            if let server = try scan().first(where: { $0.ports.contains(port) }) { return server }
            usleep(100_000)
        }
        throw NSError(domain: "server didn't start on \(port)", code: 1)
    }

    private func isListening(_ port: Int) throws -> Bool {
        try scan().contains { $0.ports.contains(port) }
    }

    func testListsAndStopsServerWithRestartingWrapper() throws {
        // The wrapper restarts the server if only the pid on the port is killed, like pnpm or next dev.
        let port = 38471
        let server = try launch("while true; do /usr/bin/python3 -m http.server \(port) --bind 127.0.0.1; sleep 0.2; done", port: port)
        XCTAssertTrue(server.isDevServer)
        XCTAssertFalse(server.openToNetwork)
        XCTAssertEqual(server.name, "http.server")
        XCTAssertEqual(server.project, ".ports-test-\(port)")
        XCTAssertGreaterThan(server.memory, 1_000_000)
        XCTAssertEqual(try stop(server), .stopped)
        usleep(800_000)
        XCTAssertFalse(try isListening(port), "wrapper brought it back")
    }

    func testForceStopsServerThatIgnoresTerm() throws {
        let port = 38472
        let server = try launch("trap '' TERM; /usr/bin/python3 -c \"import signal,http.server as h; signal.signal(signal.SIGTERM, signal.SIG_IGN); h.HTTPServer(('',\(port)),h.BaseHTTPRequestHandler).serve_forever()\"", port: port)
        XCTAssertTrue(server.openToNetwork)
        XCTAssertEqual(try stop(server), .stopped)
        XCTAssertFalse(try isListening(port))
    }

    func testRestartsWithItsPortAndEnvironment() throws {
        let port = 38474
        // Takes its port from the environment, so it only comes back on the same port with its environment.
        let script = "import os,http.server as h; open('secret.txt','w').write(os.environ.get('API_KEY','none')); h.HTTPServer(('127.0.0.1',int(os.environ['PORT'])),h.BaseHTTPRequestHandler).serve_forever()"
        let server = try launch("PORT=\(port) API_KEY=hunter2 exec /usr/bin/python3 -c \"\(script)\"", port: port)
        let recipe = try XCTUnwrap(restartRecipe(for: server))
        XCTAssertEqual(recipe.environment["PORT"], "\(port)")
        XCTAssertEqual(try stop(server), .stopped)
        XCTAssertFalse(PortsCore.isListening(on: [port]))

        // The app starts servers from a background thread, where signals are blocked.
        let started = expectation(description: "started")
        DispatchQueue.global().async {
            XCTAssertTrue(start(recipe))
            started.fulfill()
        }
        wait(for: [started], timeout: 5)
        var back = false
        for _ in 0..<50 where !back {
            back = PortsCore.isListening(on: [port])
            usleep(100_000)
        }
        XCTAssertTrue(back, "started again on its old port")
        let again = try XCTUnwrap(try scan().first { $0.ports.contains(port) })
        XCTAssertTrue(again.isDevServer)
        let before = Date()
        XCTAssertEqual(try stop(again), .stopped, "and it can be stopped again")
        XCTAssertLessThan(Date().timeIntervalSince(before), 4, "by a normal stop, not the force-stop after 5 seconds")
        XCTAssertEqual(try String(contentsOfFile: recipe.folder + "/secret.txt", encoding: .utf8), "hunter2")
    }

    func testDefaultBudgetIsAQuarterOfMemoryFromTheMenu() {
        XCTAssertEqual(defaultBudget(physicalMemory: 8 << 30), 2)
        XCTAssertEqual(defaultBudget(physicalMemory: 16 << 30), 4)
        XCTAssertEqual(defaultBudget(physicalMemory: 18 << 30), 4)
        XCTAssertEqual(defaultBudget(physicalMemory: 36 << 30), 8)
        XCTAssertEqual(defaultBudget(physicalMemory: 128 << 30), 16)
    }

    func testLoginItemOnlyFromAnApplicationsFolder() {
        XCTAssertTrue(isInstalled("/Applications/Ports.app", home: "/Users/a"))
        XCTAssertTrue(isInstalled("/Users/a/Applications/Ports.app", home: "/Users/a"))
        XCTAssertFalse(isInstalled("/Users/a/Downloads/Ports.app", home: "/Users/a"))
        XCTAssertFalse(isInstalled("/Volumes/Ports/Ports.app", home: "/Users/a"))
        XCTAssertFalse(isInstalled("/private/var/folders/x/AppTranslocation/y/d/Ports.app", home: "/Users/a"))
    }

    func testStaleServerIsNotSignalled() throws {
        let port = 38473
        let server = try launch("exec /usr/bin/python3 -m http.server \(port) --bind 127.0.0.1", port: port)
        XCTAssertEqual(try stop(server), .stopped)
        XCTAssertEqual(try stop(server), .alreadyGone)
    }
}

final class TreemapTests: XCTestCase {
    private func item(_ project: String, _ port: Int, _ mb: UInt64, stopped: Bool = false) -> MapItem {
        MapItem(id: "\(project)\(port)", project: project, port: port, memory: mb << 20, idle: false, stopped: stopped)
    }
    private let size = CGSize(width: 348, height: 200)

    private func assertTidy(_ tiles: [MapTile], file: StaticString = #filePath, line: UInt = #line) {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
        for (i, tile) in tiles.enumerated() {
            XCTAssertTrue(bounds.contains(tile.frame), "\(tile.frame) outside", file: file, line: line)
            for other in tiles[(i + 1)...] {
                XCTAssertFalse(tile.frame.intersects(other.frame), "\(tile.frame) overlaps \(other.frame)", file: file, line: line)
            }
        }
    }

    func testMatchesTheDesign() {
        let tiles = layoutTreemap(
            items: [item("web", 1, 1024), item("api", 3400, 388), item("api", 3401, 372),
                    item("api", 8788, 26), item("api", 8799, 22)],
            capacity: 3 << 30, size: size)
        assertTidy(tiles)
        XCTAssertEqual(tiles.count, 5, "project, two ports, +2 more, free")
        guard case .server(_, showsProject: true) = tiles[0].kind else { return XCTFail("first tile shows the project") }
        guard case .more(let rest) = tiles[3].kind else { return XCTFail("small servers fold") }
        XCTAssertEqual(rest.count, 2)
        XCTAssertEqual(tiles[4].kind, .free)
    }

    func testOverBudgetHasNoFreeTile() {
        let tiles = layoutTreemap(items: [item("a", 1, 4000), item("b", 2, 900)], capacity: 3 << 30, size: size)
        assertTidy(tiles)
        XCTAssertFalse(tiles.contains { $0.kind == .free })
    }

    func testManyProjectsFold() {
        let items = (0..<12).map { item("p\($0)", $0, 50) }
        let tiles = layoutTreemap(items: items, capacity: 3 << 30, size: size)
        assertTidy(tiles)
        let folded = tiles.flatMap { tile -> [MapItem] in
            if case .more(let rest) = tile.kind { return rest }
            if case .server(let one, _) = tile.kind { return [one] }
            return []
        }
        XCTAssertEqual(folded.count, 12, "every server stays reachable")
    }

    func testEmptyIsAllFree() {
        let tiles = layoutTreemap(items: [], capacity: 3 << 30, size: size)
        XCTAssertEqual(tiles.map(\.kind), [.free])
    }

    func testBudgetWords() {
        XCTAssertEqual(BudgetStatus(used: 79, budget: 100), .roomToSpare)
        XCTAssertEqual(BudgetStatus(used: 80, budget: 100), .gettingFull)
        XCTAssertEqual(BudgetStatus(used: 95, budget: 100), .almostFull)
        XCTAssertEqual(BudgetStatus(used: 101, budget: 100), .overBudget)
    }
}

final class RestartTests: XCTestCase {
    func testParsesProcessArguments() {
        var bytes: [UInt8] = [2, 0, 0, 0]
        bytes += Array("/usr/bin/node".utf8) + [0, 0, 0, 0]
        bytes += Array("node".utf8) + [0] + Array("server.mjs".utf8) + [0]
        bytes += Array("PORT=3400".utf8) + [0] + Array("API_KEY=secret".utf8) + [0, 0, 0]
        let parsed = parseProcessArguments(Data(bytes))
        XCTAssertEqual(parsed?.executable, "/usr/bin/node")
        XCTAssertEqual(parsed?.arguments, ["node", "server.mjs"])
        XCTAssertEqual(parsed?.environment["PORT"], "3400")
    }
}
