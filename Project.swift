import ProjectDescription

let bundleIdPrefix = "dev.hermes.client"
let deploymentTargets: DeploymentTargets = .iOS("27.0")

let project = Project(
    name: "Hermes",
    options: .options(
        automaticSchemesOptions: .disabled,
        disableBundleAccessors: true,
        disableSynthesizedResourceAccessors: true
    ),
    packages: [
        .local(path: "HermesKit")
    ],
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "SWIFT_STRICT_CONCURRENCY": "complete",
            "SWIFT_UPCOMING_FEATURE_NONISOLATED_NONSENDING_BY_DEFAULT": "YES",
            "SWIFT_UPCOMING_FEATURE_INFER_ISOLATED_CONFORMANCES": "YES",
            "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        ]
    ),
    targets: [
        .target(
            name: "Hermes",
            destinations: [.iPhone, .iPad],
            product: .app,
            bundleId: bundleIdPrefix,
            deploymentTargets: deploymentTargets,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Hermes",
                "UILaunchScreen": [:],
            ]),
            sources: ["App/Sources/**"],
            resources: ["App/Resources/**"],
            dependencies: [
                .package(product: "HermesAPI"),
                .package(product: "HermesStore"),
                .package(product: "HermesSecurity"),
            ]
        ),
        .target(
            name: "HermesTests",
            destinations: [.iPhone, .iPad],
            product: .unitTests,
            bundleId: "\(bundleIdPrefix).tests",
            deploymentTargets: deploymentTargets,
            infoPlist: .default,
            sources: ["App/Tests/**"],
            dependencies: [
                .target(name: "Hermes")
            ]
        ),
    ],
    schemes: [
        .scheme(
            name: "Hermes",
            shared: true,
            buildAction: .buildAction(targets: ["Hermes"]),
            testAction: .targets(["HermesTests"]),
            runAction: .runAction(executable: "Hermes")
        )
    ]
)
