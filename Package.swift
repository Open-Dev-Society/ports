// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ports",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "PortsCore"),
        .executableTarget(name: "ports", dependencies: ["PortsCore"]),
        .executableTarget(name: "PortsApp"),
        .executableTarget(name: "PortsPanel", dependencies: ["PortsCore"]),
        .testTarget(name: "PortsCoreTests", dependencies: ["PortsCore"]),
    ]
)
