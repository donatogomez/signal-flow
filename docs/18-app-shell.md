# 18. App Shell

SignalFlow is now a **runnable application**: a `@main` entry point that boots the data layer and
launches into the existing `RootView`. This document covers the bootstrap, the dependency
composition, and lifecycle management.

```
swift build ✅  (produces a runnable `SignalFlow` binary)
swift test → 96 tests, 22 suites ✅   ./Scripts/check-boundaries.sh ✅
```

## 18.1 Target layout

Two targets make up the shell, split so the composition is testable while the entry point stays
trivial:

| Target | Kind | Contents |
| --- | --- | --- |
| `SignalFlowApp` | library | The **composition root**: `AppContainer` (DI + lifecycle) and `RootView` (navigation). Depends on DataKit + every feature. Importable by tests. |
| `SignalFlowHost` | executable | The `@main` entry point only (host runner; the iOS app target reuses the same file) — `SignalFlowApp.swift`. A few lines over `AppContainer`/`RootView`. |

> **Why an executable target?** SwiftPM cannot emit an iOS `.app` bundle — only Xcode can. Making the
> entry point a SwiftPM `executableTarget` means `swift build` compiles *and links* the real `@main`
> shell (verified in CI), and `swift run SignalFlowHost` launches it on the host. The **identical**
> `SignalFlowApp.swift` / `AppContainer` / `RootView` files host an Xcode iOS app target unchanged —
> the only thing Xcode adds is the bundle, `Info.plist`, and signing. Keeping the code in the package
> means it stays inside the `swift build` / `swift test` / boundary-check loop rather than drifting in
> an unverified project file.

## 18.2 Bootstrap process

```mermaid
sequenceDiagram
    participant OS
    participant App as @main SignalFlowApp
    participant C as AppContainer (@MainActor)
    participant DS as DataKit SimulatedDataSource
    participant Root as RootView

    OS->>App: launch
    App->>C: AppContainer.live()   (assemble the source + ports)
    App->>Root: WindowGroup { RootView(container:) }
    Root->>C: .task { await start() }
    C->>DS: bootstrap()  (register catalog — fleet queryable at once)
    C->>DS: start()      (begin background ingestion)
    Note over App,C: scenePhase .background → stop(); .active → start()
```

1. `@main struct SignalFlowApp: App` creates the composition root once: `AppContainer.live()`.
2. The `WindowGroup` hosts `RootView`, injected with the container.
3. `RootView.task` calls `container.start()`, which **bootstraps** the data layer (registering the
   fleet catalog so the UI has data immediately, even before telemetry) and **starts ingestion**.
4. Scene-phase changes drive start/stop (below).

## 18.3 Dependency composition

`AppContainer` is the single place concrete dependencies are assembled. It owns the `DataKit`
`SimulatedDataSource` and exposes it **only** as `DomainKit` ports:

```swift
@MainActor @Observable
public final class AppContainer {
    private let source: SimulatedDataSource
    public var assets:    any AssetRepository    { source.assets }
    public var devices:   any DeviceRepository   { source.devices }
    public var telemetry: any TelemetryRepository { source.telemetry }
    public var alerts:    any AlertRepository    { source.alerts }
    public var events:    any EventRepository    { source.events }
    public var insights:  any InsightsProviding  { source.insights }

    public static func live() -> AppContainer    { .init(source: .live(seed: 42, timeScale: 600)) }
    public static func preview() -> AppContainer  { .init(source: .deterministic(seed: 42, maxTicks: 80)) }
}
```

The features (`FeatureDashboard`, `FeatureFleet`, `FeatureDeviceDetail`) receive these `any …Repository`
values and nothing else. They cannot name `DataKit` or `SimulationKit` — the boundary check enforces
it. So the entire knowledge of "what's behind the ports" is contained in this one type.

### Why the composition root owns DataKit

This is the payoff of the whole architecture. Dependencies point inward toward `DomainKit`; the
concrete data layer is plugged in at the outermost layer. Concentrating that wiring in `AppContainer`
means:

- **Swapping the source is a one-line change here.** When SwiftData persistence or a live
  `WebSocketGateway` land, `AppContainer.live()` points at a different `*DataSource` — features,
  use cases, and `RootView` are untouched.
- **Test/preview parity.** `AppContainer.preview()` substitutes a deterministic source; previews and
  tests run with no network, no real model, no flakiness, through the same ports as production.
- **One audit point.** A reviewer reads a single file to see exactly what the app is made of.

## 18.4 Lifecycle management

Lifecycle is explicit and cancellation-safe:

- **Start** is idempotent: `start()` bootstraps once (`didBootstrap` guard) and (re)starts ingestion.
  It's called from both `RootView.task` and on scene `.active`, so repeated calls are no-ops.
- **Stop** halts ingestion on scene `.background`. Crucially, `AppContainer.stop()` → `source.stop()`
  **awaits the ingestion loop to completion** before returning (the CI race fixed in
  [DataKit §16.5](16-data-kit.md#165-cancellation-strategy)). So teardown is clean: once `stop()`
  returns, no telemetry from the cancelled session can still mutate the store.
- **Restart** works because `stop()` clears the ingestion task and `start()` relaunches it without
  re-bootstrapping.

```swift
@main struct SignalFlowApp: App {
    @State private var container = AppContainer.live()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup { RootView(container: container) }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:     Task { await container.start() }
                case .background: Task { await container.stop() }
                default:          break
                }
            }
    }
}
```

## 18.5 Navigation

`RootView` is a `TabView` (Dashboard, Fleet). The Fleet tab is a `NavigationStack` with a value-based
destination: a row tap appends a `DeviceID` to the stack path, and `navigationDestination(for:)`
pushes `DeviceDetailScreen`. Navigation is therefore data-driven and deep-link-ready, and features
stay decoupled — Fleet emits a `DeviceID`; the root decides what to show.

## 18.6 Preview support

`AppContainer.preview()` provides a deterministic, fast source; `RootView`'s `#Preview` uses it so the
canvas fills with reproducible telemetry. The same factory backs the unit tests, so "what the preview
shows" and "what the tests assert" come from one place.

## 18.7 Testing

`AppContainerTests` verifies the composition root rather than pixels: starting the container boots the
data layer and exposes a 10-device fleet through the ports, `start()` is idempotent, `stop()` tears
down without hanging, and a `DomainKit` use case runs end-to-end purely through the container's ports.
This is the meaningful seam to test — the `@main` shell itself is a handful of declarative lines.

## 18.8 Running it

```bash
swift run SignalFlowHost        # launches the host build of the app
```

To ship to iOS: add an Xcode app target whose sources are `Sources/SignalFlow/SignalFlowApp.swift`
(or a one-line `@main` that imports the `SignalFlowApp` library), link the package, and build for a
simulator/device. No app logic moves — the shell is already written and tested here.
