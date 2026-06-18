// swift-tools-version: 6.2
//
// SignalFlowKit — modular Swift Package for the SignalFlow IoT monitoring platform.
//
// This manifest is where Clean Architecture stops being a diagram and becomes a build constraint.
// A target can only see the targets it explicitly declares as dependencies, so the layering rules
// in docs/03-technical-architecture.md and docs/12-scaffolding.md are enforced by the compiler:
// e.g. a Feature target literally cannot `import DataKit`.
//
// Strict concurrency: every target builds in the Swift 6 language mode (see `swiftLanguageModes`),
// under which complete strict-concurrency checking is the default. No `@unchecked Sendable` allowed.

import PackageDescription

// All first-party code builds in Swift 6 mode → data-race safety enforced at compile time.
let swift6: [SwiftSetting] = [
    .swiftLanguageMode(.v6)
]

let package = Package(
    name: "SignalFlowKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26) // host platform, so `swift build` / `swift test` run from the CLI
    ],
    products: [
        // A host runner for the `@main` shell: lets `swift build`/`swift run` compile and launch the
        // entry point from the CLI (CI coverage). The Xcode iOS app target reuses the same source
        // file. Named distinctly from the iOS app's `SignalFlow` scheme to avoid any ambiguity.
        .executable(name: "SignalFlowHost", targets: ["SignalFlowHost"]),
        // The composition root library — `AppContainer` + `RootView`. Linkable by an external app
        // shell and importable by tests.
        .library(name: "SignalFlowApp", targets: ["SignalFlowApp"]),
        // Exposed for previews / design work without booting the whole app.
        .library(name: "DesignSystemKit", targets: ["DesignSystemKit"]),
        .library(name: "DomainKit", targets: ["DomainKit"])
    ],
    targets: [

        // MARK: - Core (feature-agnostic foundations)

        .target(name: "CoreKit", swiftSettings: swift6),
        // DesignSystemKit encodes the product's visual semantics for domain concepts (status, asset
        // kind, severity), so it depends on DomainKit — but on nothing in the data layer.
        .target(name: "DesignSystemKit", dependencies: ["DomainKit"], swiftSettings: swift6),

        // MARK: - Domain (pure business core — depends on NOTHING)

        .target(name: "DomainKit", swiftSettings: swift6),

        // MARK: - Data sources (concrete infrastructure)

        .target(name: "NetworkingKit", dependencies: ["CoreKit"], swiftSettings: swift6),
        // The only target that imports SwiftData. Maps SwiftData @Model records to/from DomainKit
        // entities behind a ModelActor; depends on DomainKit alone.
        .target(name: "PersistenceKit", dependencies: ["DomainKit"], swiftSettings: swift6),
        .target(name: "SimulationKit", dependencies: ["CoreKit", "DomainKit"], swiftSettings: swift6),

        // DataKit is the aggregator that implements DomainKit's ports on top of the data sources.
        .target(
            name: "DataKit",
            dependencies: ["DomainKit", "PersistenceKit", "NetworkingKit", "SimulationKit"],
            swiftSettings: swift6
        ),

        // The only target that imports Apple's FoundationModels framework. Implements the DomainKit
        // InsightsProviding port with on-device guided generation; depends on DomainKit alone.
        .target(name: "IntelligenceKit", dependencies: ["DomainKit"], swiftSettings: swift6),

        // MARK: - Features (vertical slices — Domain + DesignSystem only, never Data)

        .target(name: "FeatureDashboard", dependencies: ["DomainKit", "DesignSystemKit"], swiftSettings: swift6),
        .target(name: "FeatureFleet", dependencies: ["DomainKit", "DesignSystemKit"], swiftSettings: swift6),
        .target(name: "FeatureDeviceDetail", dependencies: ["DomainKit", "DesignSystemKit"], swiftSettings: swift6),
        .target(name: "FeatureAlerts", dependencies: ["DomainKit", "DesignSystemKit"], swiftSettings: swift6),
        .target(name: "FeatureInsights", dependencies: ["DomainKit", "DesignSystemKit"], swiftSettings: swift6),
        .target(name: "FeatureSettings", dependencies: ["DomainKit", "DesignSystemKit"], swiftSettings: swift6),

        // MARK: - App (composition root — the ONLY target allowed to know concretes)

        .target(
            name: "SignalFlowApp",
            dependencies: [
                "CoreKit",
                "DomainKit",
                "DesignSystemKit",
                // concrete data modules — wired here, invisible to features
                "DataKit",
                "IntelligenceKit",
                "PersistenceKit",
                "NetworkingKit",
                "SimulationKit",
                // every feature
                "FeatureDashboard",
                "FeatureFleet",
                "FeatureDeviceDetail",
                "FeatureAlerts",
                "FeatureInsights",
                "FeatureSettings"
            ],
            swiftSettings: swift6
        ),

        // The `@main` entry point. A thin shell over the `SignalFlowApp` composition root, reused by
        // both this host runner and the Xcode iOS app target.
        .executableTarget(
            name: "SignalFlowHost",
            dependencies: ["SignalFlowApp"],
            swiftSettings: swift6
        ),

        // MARK: - Testing

        // Shared test utilities (fakes, builders, fixtures). Intentionally empty for now.
        .target(name: "TestingSupportKit", dependencies: ["DomainKit"], swiftSettings: swift6),

        // A single smoke test target proving the test stack + TestingSupportKit link and run.
        .testTarget(
            name: "SignalFlowKitTests",
            dependencies: [
                "DomainKit", "TestingSupportKit", "CoreKit", "SimulationKit", "DataKit",
                "PersistenceKit", "IntelligenceKit", "DesignSystemKit", "FeatureDashboard",
                "FeatureFleet", "FeatureDeviceDetail", "FeatureInsights", "SignalFlowApp",
            ],
            swiftSettings: swift6
        )
    ]
)
