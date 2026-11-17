// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AccountSwitch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "AccountSwitch", resources: [.process("Resources")]),
        .testTarget(name: "AccountSwitchTests", dependencies: ["AccountSwitch"])
    ]
)
