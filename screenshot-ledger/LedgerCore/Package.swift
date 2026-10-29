// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LedgerCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "LedgerCore", targets: ["LedgerCore"]),
    ],
    targets: [
        .target(name: "LedgerCore"),
        .testTarget(name: "LedgerCoreTests", dependencies: ["LedgerCore"]),
    ]
)
