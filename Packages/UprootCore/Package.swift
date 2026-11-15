// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UprootCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UprootCore", targets: ["UprootCore"]),
        .executable(name: "uproot-scan", targets: ["uproot-scan"]),
    ],
    targets: [
        .target(name: "UprootCore"),
        .executableTarget(name: "uproot-scan", dependencies: ["UprootCore"]),
        .testTarget(name: "UprootCoreTests", dependencies: ["UprootCore"]),
    ]
)
