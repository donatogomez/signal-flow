# 24. WidgetKit

Two Home Screen widgets — **Fleet Status** and **Critical Alerts** — that surface the fleet's health
without opening the app. They render from **persisted state only**, read out of a SwiftData store
shared with the app through an App Group, and deep-link back into the relevant screen on tap.

```
swift build ✅   swift test → 161 tests, 35 suites ✅   ./Scripts/check-boundaries.sh ✅
xcodebuild -scheme SignalFlow -sdk iphonesimulator … → ** BUILD SUCCEEDED ** ✅  (app + embedded extension)
```

## 24.1 What the widgets show

| Widget | Small | Medium |
| --- | --- | --- |
| **Fleet Status** | Online count + warning/critical chips + "updated" time | Three status tiles (online / warning / critical) + "updated" time |
| **Critical Alerts** | Top 3 alerts: device + severity swatch | Top 4 alerts: device + severity + message |

Both support `systemSmall` and `systemMedium`, use semantic fonts (Dynamic Type), carry
`accessibilityLabel`s, and take their colors/symbols from `DesignSystemKit` so "critical" looks the
same on the widget as it does in-app.

## 24.2 Architecture

The reusable engineering lives in a **`WidgetSupportKit`** SwiftPM library; the Xcode
**`SignalFlowWidgets`** app-extension target is a ~10-line `@main WidgetBundle` shell over it — exactly
the same split as `SignalFlowHost` (the iOS app) is over `SignalFlowApp`. Putting the logic and views
in a package means they are built by `swift build` and unit-tested by `swift test`; the extension just
declares which widgets to vend.

```
SignalFlowWidgets.appex        ← Xcode app-extension target (@main WidgetBundle shell)
        │ links
        ▼
WidgetSupportKit  (SwiftPM library)
   ├─ FleetStatusWidget / CriticalAlertsWidget   (Widget + SwiftUI views)
   ├─ AppIntentTimelineProvider(s)               (async, Swift-6-clean)
   ├─ WidgetSnapshotReader → PersistenceKit       (reads persisted snapshots)
   ├─ FleetSummary / WidgetAlert                  (pure aggregation + selection)
   └─ WidgetRoute                                 (deep-link contract, shared with the app)
        │ depends on
        ▼
   DomainKit · PersistenceKit · DesignSystemKit
```

`WidgetSupportKit` depends on **DomainKit, PersistenceKit, DesignSystemKit** — and crucially **not** on
`DataKit`, `SimulationKit`, or `NetworkingKit`. It also never imports `SwiftData`: PersistenceKit owns
that (enforced by `Scripts/check-boundaries.sh`, Rule 6), and the widget reaches the store only through
PersistenceKit's `PersistenceStoring` port, which speaks `DomainKit` value types.

## 24.3 Why widgets read PersistenceKit, not DataKit

This is the central design decision, and it follows from how a widget actually runs:

- **A widget is a separate process with a tiny time/memory budget.** It is woken briefly by the system
  to produce a timeline, then suspended. It cannot host the live data stack — `DataKit`'s
  `SimulatedDataSource` (and a real backend behind `NetworkingKit`) is a long-lived, actor-based
  ingestion engine that belongs to the *app*. Spinning that up per refresh would be wrong and
  wasteful, and `SimulationKit` would just invent *different* numbers than the app last showed.
- **The app already commits the truth to disk.** As telemetry flows, the app persists the latest
  per-device state, active alerts, and readings into SwiftData (see
  [SwiftData Persistence](docs/21-swiftdata-persistence.md)). That persisted snapshot is the
  authoritative, *already-reconciled* view — exactly what a glanceable widget should mirror.
- **So the widget reads the snapshot, not the engine.** `WidgetSnapshotReader` calls
  `PersistenceStoring.loadSnapshot()` and aggregates the result. The widget shows what the app last
  saw — never a divergent simulation — and stays cheap, offline-friendly, and deterministic.

In short: **DataKit produces; PersistenceKit preserves; the widget observes.** Reading the data source
directly would duplicate the engine and risk showing numbers the user never saw in the app.

## 24.4 App Groups & shared persistence (no duplicated storage)

The app and the extension are different processes, so they can only share data through an **App
Group** container. Both open the **same** SwiftData store file inside
`group.com.signalflow.shared`:

```swift
// PersistenceController
public static let appGroupIdentifier = "group.com.signalflow.shared"

public static func sharedStoreURL() -> URL? {
    FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
        .appending(path: "SignalFlow.store")
}

public static func makeSharedContainer() throws -> ModelContainer {
    try makeContainer(url: sharedStoreURL())   // falls back to the app-private store if unavailable
}
```

- The **app** builds its `PersistenceStore` over `makeSharedContainer()` (wired in `AppContainer.live()`),
  so everything it persists lands in the shared store.
- The **widget** opens the *same* container via `PersistenceController.makeSharedStore()` and reads it.
- There is **one** store, written by the app and read by the widget — no second copy, no syncing.

The App Group is declared in both targets' entitlements (`SignalFlow.entitlements` and
`SignalFlowWidgets.entitlements`). When the group is unavailable (e.g. a plain `swift build` with no
entitlement, or a misconfigured environment), `sharedStoreURL()` returns `nil` and the code degrades
to the app-private container rather than crashing.

## 24.5 Refresh strategy (TimelineProvider)

Both widgets use an **`AppIntentTimelineProvider`** (the async-method variant — see §24.7) that emits a
single entry and asks WidgetKit to reload after a fixed interval:

```swift
public enum WidgetTimeline {
    public static let refreshInterval: TimeInterval = 15 * 60   // 15 minutes
    public static func nextReload(after date: Date) -> Date { date.addingTimeInterval(refreshInterval) }

    public static func fleet(_ data: WidgetData, now: Date) -> Timeline<FleetStatusEntry> {
        Timeline(entries: [FleetStatusEntry(date: now, fleet: data.fleet)], policy: .after(nextReload(after: now)))
    }
}
```

Rationale:

- **One entry, periodic reload — not aggressive polling.** The widget renders persisted state that the
  *foreground app* refreshes far more often than a background widget ever could. There's nothing to
  gain from minute-by-minute reloads (WidgetKit throttles them and they'd burn the daily refresh
  budget), so we ask for a fresh read every 15 minutes via `.after`.
- **Deterministic.** The single interval lives in one place, the provider produces exactly one entry
  per refresh, and the same pure functions back the tests — so timeline behavior is reproducible
  rather than time-of-day dependent.
- **Event-driven freshness is still possible.** The app can call `WidgetCenter.shared.reloadTimelines`
  after a significant change to push an immediate update; the periodic policy is the floor, not the
  ceiling. (Left as a future hook to keep this change focused.)

## 24.6 Deep linking

Each widget attaches a `signalflow://…` URL via `.widgetURL(_:)`; the app parses it back with
`WidgetRoute` and selects the matching tab in `RootView` via `.onOpenURL`:

| Widget | URL | Destination |
| --- | --- | --- |
| Fleet Status | `signalflow://dashboard` | Dashboard tab |
| Critical Alerts | `signalflow://alerts` | Alerts tab |

`WidgetRoute` is the single source of truth for the scheme/host, shared by the producer (widget) and
the consumer (app), so the two can't drift apart on a string.

## 24.7 Swift 6 strict concurrency note

The classic completion-handler `TimelineProvider` doesn't fit Swift 6: passing the non-`Sendable`
completion closure into a `Task` trips `#SendingClosureRisksDataRace`. Rather than reach for
`@unchecked Sendable` (banned in this codebase), both providers adopt **`AppIntentTimelineProvider`**,
whose `snapshot(for:in:)` / `timeline(for:in:)` are `async` — so the persisted read is a clean
`await` with no closure to smuggle across isolation. A no-parameter `SignalFlowWidgetConfiguration`
intent satisfies the configuration requirement.

## 24.8 Tests

`Tests/SignalFlowKitTests/Widgets/WidgetSupportTests.swift`:

| Test | What it proves |
| --- | --- |
| `fleetAggregation` | devices bucket into online/warning/critical/offline via the same `DeviceHealthPolicy` the app uses |
| `acknowledgedAlertDoesNotCount` | an acknowledged alert stops driving the critical bucket |
| `lastUpdated` | the "updated" time tracks the newest reading |
| `alertSelection` | top alerts sort unacked → severity → recency and join device names |
| `alertUnknownDevice` | a nameless device falls back gracefully |
| `snapshotGeneration` | the reader builds widget data from a **real in-memory SwiftData store** through PersistenceKit |
| `fleetTimeline` | one entry at `now` + a deterministic 15-minute next reload |
| `alertsTimeline` | the timeline trims to the requested family limit |
| `deepLinks` | every `WidgetRoute` round-trips through its URL; foreign URLs are rejected |

The aggregation/selection tests run on pure value types; `snapshotGeneration` exercises the genuine
PersistenceKit → SwiftData path end-to-end.
