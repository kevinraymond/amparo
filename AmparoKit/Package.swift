// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AmparoKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AmparoCrypto", targets: ["AmparoCrypto"]),
        .library(name: "AmparoAPI", targets: ["AmparoAPI"]),
    ],
    targets: [
        .target(name: "AmparoCrypto"),
        .target(name: "AmparoAPI", dependencies: ["AmparoCrypto"]),
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
    ]
)
