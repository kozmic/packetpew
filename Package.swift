// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PacketPew",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        // The app itself (run with `swift run PacketPew`, or open the package in Xcode).
        .executable(name: "PacketPew", targets: ["PacketPew"]),
        // Shared, cross-platform library with all logic and UI — reusable in an iOS target.
        .library(name: "PacketPewKit", targets: ["PacketPewKit"])
    ],
    targets: [
        // C bridge to libpcap. Built on macOS only (iOS has no /dev/bpf).
        .target(
            name: "CPcap",
            linkerSettings: [
                .linkedLibrary("pcap", .when(platforms: [.macOS]))
            ]
        ),
        .target(
            name: "PacketPewKit",
            dependencies: [
                .target(name: "CPcap", condition: .when(platforms: [.macOS]))
            ],
            resources: [
                .copy("Resources/world.json")
            ]
        ),
        .executableTarget(
            name: "PacketPew",
            dependencies: ["PacketPewKit"]
        )
    ],
    swiftLanguageModes: [.v5]
)
