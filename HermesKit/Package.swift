// swift-tools-version: 6.2
import PackageDescription

let strictConcurrency: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "HermesKit",
    platforms: [
        .iOS("27.0"),
        .macOS("27.0"),
    ],
    products: [
        .library(name: "HermesAPI", targets: ["HermesAPI"]),
        .library(name: "HermesStore", targets: ["HermesStore"]),
        .library(name: "HermesSecurity", targets: ["HermesSecurity"]),
        .library(name: "HermesChat", targets: ["HermesChat"]),
    ],
    targets: [
        .target(
            name: "HermesAPI",
            swiftSettings: strictConcurrency
        ),
        .target(
            name: "HermesChat",
            dependencies: ["HermesAPI", "HermesStore"],
            swiftSettings: strictConcurrency
        ),
        .target(
            name: "HermesStore",
            dependencies: ["HermesAPI"],
            swiftSettings: strictConcurrency
        ),
        .target(
            name: "HermesSecurity",
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "HermesAPITests",
            dependencies: ["HermesAPI"],
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "HermesChatTests",
            dependencies: ["HermesChat", "HermesStore"]
        ),
        .testTarget(
            name: "HermesStoreTests",
            dependencies: ["HermesStore"]
        ),
        .testTarget(
            name: "HermesSecurityTests",
            dependencies: ["HermesSecurity"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
