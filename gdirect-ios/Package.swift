// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GDirectSupport",
    products: [.library(name: "GDirectSupport", targets: ["GDirectSupport"])],
    targets: [
        .target(name: "GDirectSupport", path: "ios/GDirect/Support"),
        .testTarget(name: "GDirectSupportTests", dependencies: ["GDirectSupport"], path: "Tests/GDirectSupportTests")
    ]
)
