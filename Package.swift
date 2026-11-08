// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ports",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(name: "PortsCore"),
        .executableTarget(name: "ports", dependencies: ["PortsCore"]),
        .executableTarget(name: "PortsApp"),
        .executableTarget(name: "PortsPanel", dependencies: ["PortsCore"]),
        // Its own program, so Sparkle is only in memory while it checks for an update.
        .executableTarget(
            name: "PortsUpdater",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "PortsCoreTests", dependencies: ["PortsCore"]),
    ]
)
