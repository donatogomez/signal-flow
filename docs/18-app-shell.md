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
    Root->>C: onAppear → requestStart()
    C->>DS: bootstrap()  (register catalog — fleet queryable at once)
    C->>DS: start()      (begin background ingestion)
    Note over App,C: scenePhase .background → requestStop(); .active → requestStart()
```

1. `@main struct SignalFlowApp: App` creates the composition root once: `AppContainer.live()`.
2. The `WindowGroup` hosts `RootView`, injected with the container.
3. `RootView` calls `container.requestStart()` on appear, which **bootstraps** the data layer (registering the
   fleet catalog so the UI has data immediately, even before telemetry) and **starts ingestion**.
4. Scene-phase changes drive start/stop (below).
5. The outcome is published as `AppContainer.startupState`: `.starting`, then `.ready`,
   `.degraded(.restoreFailed | .persistenceUnavailable)` or `.failed` (see "Failure handling" below).

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
  It's requested from both `RootView` (on appear) and on scene `.active`, so repeated requests are
  no-ops. Requests are recorded synchronously and applied one at a time in request order (see
  [Concurrency §7.3](07-concurrency.md#73-lifecycle-and-actor-reentrancy)).
- **Stop** halts ingestion on scene `.background`. Crucially, `AppContainer.stop()` → `source.stop()`
  **awaits the ingestion loop to completion** before returning (the CI race fixed in
  [DataKit §16.5](16-data-kit.md#165-startup--cancellation-strategy)). So teardown is clean: once `stop()`
  returns, no telemetry from the cancelled session can still mutate the store.
- **Restart** works because `stop()` clears the ingestion task and `start()` relaunches it without
  re-bootstrapping.
- **Failure** doesn't count as a start: a failed bootstrap begins no ingestion and is retried only by
  a start requested after it ([Concurrency §7.3](07-concurrency.md#startup-failures-and-retry)).

```swift
@main struct SignalFlowApp: App {
    @State private var container = AppContainer.live()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup { RootView(container: container) }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:     container.requestStart()   // synchronous: ordered at the call
                case .background: container.requestStop()
                default:          break
                }
            }
    }
}
```

### Failure handling

Failures are classified once and handled where they can be interpreted:

| Class | Example | Handling |
| --- | --- | --- |
| Expected absence | No watch paired, no saved snapshot yet, store read of an unknown id | Silent fallback (`try?`), no log |
| Recoverable operational | Snapshot write, restore, insight save, watch send | Logged; bounded retry where safe (persistence), otherwise the next cycle |
| Critical functional | Catalog can't be built, so the app can't start | `startupState = .failed`; full-screen state with **Try Again** |
| Cancellation | View disappears during an insight request | Propagated; never a fallback, failure or saved result |
| Programming invariant | Constant thresholds or units rejected | Treated as critical at startup (`.fault` log); `try?` on hot paths |

What the user sees comes from `startupState`, not from error text:

- **Starting / ready:** the tabs, with each screen's own loading state.
- **Degraded:** the tabs, plus a discreet, dismissible note on the Overview tab ("Saved data couldn't
  be restored…" or "Data isn't being saved on this device.").
- **Failed:** a `ContentUnavailableView` instead of the tabs, since with no catalog they'd have nothing
  to show; **Try Again** calls `requestStart()`.

Screens never show raw errors. A screen that fails to load says what failed and that SignalFlow will
try again automatically (the 3 s refresh does); Insights, which loads once on appear, offers **Try
Again** instead.

### Diagnostics

Apple's unified logging (`os.Logger`), subsystem `com.signalflow.SignalFlow`, one category per
concern: `lifecycle` (startup outcome), `persistence` (restore, writes, widget reads), `insights`
(on-device generation falling back), `watch-sync`. Nothing is logged per reading. Repeated failures on
a cadence (persistence flushes, watch sends) are logged when they start and when they recover, not on
every attempt. Error descriptions are `privacy: .private`; generated insight text is never logged.

```bash
log stream --predicate 'subsystem == "com.signalflow.SignalFlow"' --level info
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
The failure paths are covered the same way: a failed bootstrap starts nothing and isn't recorded as
done, queued starts don't retry it, a later start recovers, a stop requested during a retry wins,
cancellation is neither failure nor success, and both degraded modes are reported.
This is the meaningful seam to test — the `@main` shell itself is a handful of declarative lines.

## 18.8 Running it

```bash
swift run SignalFlowHost        # launches the host build of the app
```

To ship to iOS: add an Xcode app target whose sources are `Sources/SignalFlow/SignalFlowApp.swift`
(or a one-line `@main` that imports the `SignalFlowApp` library), link the package, and build for a
simulator/device. No app logic moves — the shell is already written and tested here.
