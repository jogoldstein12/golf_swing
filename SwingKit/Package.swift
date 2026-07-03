// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SwingKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SwingKit", targets: ["SwingKit"]),
        .executable(name: "swingctl", targets: ["swingctl"]),
    ],
    targets: [
        .target(name: "SwingKit"),
        .executableTarget(name: "swingctl", dependencies: ["SwingKit"]),
        .testTarget(name: "SwingKitTests", dependencies: ["SwingKit"]),
    ]
)
