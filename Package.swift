// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FocusPilot",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "FocusPilot", targets: ["FocusPilot"]),
    ],
    dependencies: [
        // Pinned exactly: storage format and migrations depend on it.
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        // Everything testable lives here; the app target stays a thin SwiftUI shell.
        .target(
            name: "FocusPilotCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .executableTarget(
            name: "FocusPilot",
            dependencies: ["FocusPilotCore"]
        ),
        .testTarget(
            name: "FocusPilotCoreTests",
            dependencies: ["FocusPilotCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
    ]
)
