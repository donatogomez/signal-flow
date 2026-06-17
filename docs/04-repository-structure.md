# 4. Repository Structure

## 4.1 Strategy: one app target, one local Swift Package, many targets

SignalFlow uses a **single Xcode project** with a thin app target plus a **local Swift Package**
(`SignalFlowKit`) that contains every layer as a separate **target**. This is deliberately *not* a
multi-repo or multi-package setup.

**Why this over the alternatives:**

| Option | Pros | Cons | Verdict |
| --- | --- | --- | --- |
| Everything in the app target, folders only | Simplest | Boundaries are convention-only; nothing stops a view importing a repo | ❌ defeats the purpose |
| One local package, many targets | Compiler-enforced boundaries, fast incremental builds, one checkout | Slightly more `Package.swift` | ✅ **chosen** |
| Many local packages | Stronger isolation, independent versioning | Heavy ceremony for a solo portfolio; slower to navigate | ⚠️ overkill now, design allows later split |
| Multi-repo | True team-scale | Absurd for one app | ❌ |

The key win: **a target can only see targets it declares as dependencies.** That turns the
Dependency Rule from a code-review request into a compile error. Recorded in
[ADR-0001](adr/0001-clean-architecture-with-spm-modules.md).

## 4.2 Folder structure

```
signal-flow/
├── README.md
├── docs/                          # ← architecture & product docs (this suite)
│   ├── 01-product-vision.md … 11-portfolio-value.md
│   ├── adr/                       # Architecture Decision Records (MADR)
│   └── diagrams/                  # source for exported diagrams
├── SignalFlow.xcodeproj
├── SignalFlow/                    # App target — composition root ONLY
│   ├── SignalFlowApp.swift        # @main, builds the DI container
│   ├── AppContainer.swift         # dependency wiring
│   ├── AppRouter.swift            # top-level navigation
│   └── Resources/                 # assets, Info.plist, entitlements
├── SignalFlowKit/                 # local Swift Package — all the engineering
│   ├── Package.swift
│   ├── Sources/
│   │   ├── DomainKit/
│   │   ├── ApplicationKit/
│   │   ├── DataKit/
│   │   ├── IntelligenceKit/
│   │   ├── CoreTelemetry/
│   │   ├── CorePersistence/
│   │   ├── CoreConcurrency/
│   │   ├── DesignSystem/
│   │   ├── TestSupport/           # shared fakes, builders, fixtures
│   │   ├── FeatureFleet/
│   │   ├── FeatureDeviceDetail/
│   │   ├── FeatureHistory/
│   │   ├── FeatureAlerts/
│   │   ├── FeatureInsights/
│   │   └── FeatureSettings/
│   └── Tests/
│       ├── DomainKitTests/
│       ├── ApplicationKitTests/
│       ├── DataKitTests/
│       ├── IntelligenceKitTests/
│       └── Feature*Tests/
└── .github/workflows/ci.yml       # build + test + lint gate
```

## 4.3 Core modules

Reusable, feature-agnostic foundations. They have **no knowledge of any feature**.

| Module | Responsibility | Notable types | Depends on |
| --- | --- | --- | --- |
| `DomainKit` | The business core: entities, value objects, policies, **ports** (repository/service protocols), domain errors | `Device`, `DeviceSnapshot`, `Metric`, `Reading`, `Alert`, `Threshold`, `TelemetryRepository` (protocol) | — |
| `ApplicationKit` | Use cases / interactors orchestrating the Domain | `ObserveFleet`, `SummarizeTrend`, `AcknowledgeAlert` | `DomainKit` |
| `DataKit` | Implements Domain ports; mappers, DTOs, repository impls, sync/outbox | `LiveTelemetryRepository`, `SwiftDataAlertStore` | `DomainKit`, `CoreTelemetry`, `CorePersistence` |
| `IntelligenceKit` | Implements the `InsightService` port using Foundation Models | `OnDeviceInsightService`, `@Generable` schemas | `DomainKit`, FoundationModels |
| `CoreTelemetry` | Gateway abstraction + live & simulated sources, framing, back-pressure | `TelemetryGateway` (protocol), `SimulatedGateway`, `WebSocketGateway` | `CoreConcurrency` |
| `CorePersistence` | SwiftData stack, `ModelActor`, migration plan, retention | `PersistenceController`, `@Model` types | `CoreConcurrency` |
| `CoreConcurrency` | Concurrency utilities: injectable `Clock`, `AsyncStream` helpers, debounce/throttle, cancellation scopes | `DebouncedStream`, `TaskBox` | — |
| `DesignSystem` | Reusable SwiftUI components, design tokens, status semantics, chart styles | `StatusBadge`, `MetricGauge`, `Tokens` | — |
| `TestSupport` | Shared test doubles, data builders, deterministic gateway/clock | `FakeTelemetryRepository`, `DeviceBuilder` | `DomainKit` (+ test-only) |

> **Note on DTO/`@Model` location:** SwiftData `@Model` types live in `CorePersistence`/`DataKit`,
> never in `DomainKit`. The Domain's `Device` is a plain `Sendable` struct; the persisted
> `DeviceRecord` is a separate `@Model`. Mappers in `DataKit` translate between them. This is the
> single most common place engineers accidentally break Clean Architecture, so it's called out
> explicitly and tested.

## 4.4 Feature modules

Each feature is a vertical slice: its presentation models, views, navigation routes, and
feature-specific use-case compositions. Crucially, **features depend on `DomainKit` +
`ApplicationKit` + `DesignSystem`, never on `DataKit` or `IntelligenceKit`.**

| Feature | Screens | Consumes (use cases) |
| --- | --- | --- |
| `FeatureFleet` | Fleet overview, status grouping/filtering | `ObserveFleet` |
| `FeatureDeviceDetail` | Live metrics, freshness, per-metric drill-in | `ObserveDevice` |
| `FeatureHistory` | Swift Charts time-series, range selection | `LoadTelemetryHistory` |
| `FeatureAlerts` | Alert inbox, acknowledge, notification routing | `ObserveAlerts`, `AcknowledgeAlert` |
| `FeatureInsights` | Trend summary, anomaly explanation, fleet digest | `SummarizeTrend`, `ExplainAnomaly`, `GenerateFleetDigest` |
| `FeatureSettings` | Thresholds, retention, data-source selection | `UpdateThresholds`, `SelectDataSource` |

### Why features can't see the data layer

If `FeatureFleet` could `import DataKit`, a tired engineer at 6 p.m. would `LiveTelemetryRepository()`
directly in a view and the architecture would rot. Because the feature target doesn't declare that
dependency, the import fails to build (and a CI boundary check catches the SwiftPM full-build edge
case — see [§12.3](12-scaffolding.md#123-how-the-boundaries-are-actually-enforced)). The only way to
get a repository into a feature is through an injected protocol. The boundary defends itself.

## 4.5 Dependency injection

A small, explicit, **compile-time** container — no runtime resolver, no reflection, no third-party
framework (which would also violate the "no dependencies" rule).

```swift
// SignalFlow/AppContainer.swift  (composition root — the ONLY place that knows concretes)
@MainActor
struct AppContainer {
    let observeFleet: ObserveFleet
    let summarizeTrend: SummarizeTrend
    // … one entry per use case the app needs

    static func live() -> AppContainer {
        let persistence = PersistenceController.live()
        let gateway: any TelemetryGateway = SimulatedGateway()      // swappable
        let telemetryRepo: any TelemetryRepository =
            LiveTelemetryRepository(gateway: gateway, store: persistence.store)
        let insight: any InsightService = OnDeviceInsightService()
        return AppContainer(
            observeFleet: ObserveFleet(repository: telemetryRepo),
            summarizeTrend: SummarizeTrend(repository: telemetryRepo, insight: insight)
        )
    }

    static func preview() -> AppContainer { /* fakes from TestSupport */ }
}
```

Properties of this approach:
- **Type-safe**: a missing dependency is a compiler error, not a crash at first launch.
- **Greppable & honest**: every concrete binding is in one file you can read top-to-bottom.
- **Preview/test parity**: `.preview()` and test containers swap implementations trivially, which is
  why SwiftUI previews and tests run with no network and no Foundation-Models hardware.
- **Roadmap-safe**: introducing accounts/multi-tenant later means new bindings here, not a rewrite.

## 4.6 Build & CI

A single GitHub Actions workflow gates every push:
1. `swift build` of `SignalFlowKit` with `-strict-concurrency=complete` (warnings-as-errors).
2. `swift test` (Swift Testing) across all test targets.
3. Lint/format check (SwiftFormat config committed; no external dependency added to the package).
4. DocC build to catch broken documentation (see [Documentation Strategy](10-documentation-strategy.md)).

Fast incremental builds are a real benefit of the multi-target package: touching `FeatureAlerts`
doesn't rebuild `DomainKit`.
