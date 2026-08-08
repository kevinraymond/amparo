// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AmparoKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AmparoCrypto", targets: ["AmparoCrypto"]),
        .library(name: "AmparoAPI", targets: ["AmparoAPI"]),
        .library(name: "AmparoShared", targets: ["AmparoShared"]),
    ],
    targets: [
        .target(name: "AmparoCrypto"),
        .target(name: "AmparoAPI", dependencies: ["AmparoCrypto"]),
        .target(name: "AmparoShared", dependencies: ["AmparoCrypto", "AmparoAPI"]),
        .testTarget(
            name: "AmparoCryptoTests",
            dependencies: ["AmparoCrypto"],
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "AmparoAPITests",
            dependencies: ["AmparoAPI", "AmparoCrypto"],
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "AmparoAPIIntegrationTests",
            dependencies: ["AmparoAPI", "AmparoCrypto"]
        ),
        .testTarget(
            name: "AmparoSharedTests",
            dependencies: ["AmparoShared", "AmparoCrypto", "AmparoAPI"]
        ),
    ]
)
