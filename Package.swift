// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "QuotaCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "QuotaCore", targets: ["QuotaCore"])],
    targets: [
        .target(name: "QuotaCore"),
        .target(name: "BridgeTransport",dependencies:["QuotaCore"],path:"Shared",exclude:["QuotaViews.swift","SecureStore.swift","SnapshotStore.swift"],sources:["BridgeClient.swift","HTTPClient.swift"]),
        .testTarget(name: "QuotaCoreTests", dependencies: ["QuotaCore"]),
        .testTarget(name: "BridgeTransportTests",dependencies:["BridgeTransport"])
    ]
)
