# 25. App Intents

Four App Intents that make SignalFlow scriptable, voice-invokable, and Spotlight-suggestable:

| Intent | Kind | Effect |
| --- | --- | --- |
| **Open Dashboard** | navigation | Foregrounds the app on the Dashboard tab |
| **Open Fleet Status** | navigation | Foregrounds the app on the Fleet tab |
| **Open Critical Alerts** | navigation | Foregrounds the app on the Alerts tab |
| **Show Fleet Summary** | data | Speaks/returns a one-line fleet summary **without opening the app** |

```
swift build ✅   swift test → 166 tests, 36 suites ✅   ./Scripts/check-boundaries.sh ✅
xcodebuild -scheme SignalFlow -sdk iphonesimulator … → ** BUILD SUCCEEDED ** ✅
```

## 25.1 Module architecture

The intents live in a new **`AppIntentsKit`** SwiftPM library, linked by the iOS app target so the
intents and the `AppShortcutsProvider` land in the app binary (where Shortcuts/Spotlight discovery and
App Intents metadata extraction look for them).

A refactor preceded this feature: the UI-free "read a persisted snapshot + the deep-link contract"
core was extracted out of `WidgetSupportKit` into a new **`SnapshotKit`** so that both glance surfaces
— Widgets and App Intents — share it without App Intents having to depend on SwiftUI/WidgetKit.

```
                 SignalFlowApp (RootView, host)
                 │ links                 ▲ observes AppNavigationModel
                 ▼                        │
   ┌────────── AppIntentsKit ────────────┘
   │   OpenDashboard / OpenFleetStatus / OpenCriticalAlerts  (navigation intents)
   │   ShowFleetSummary                                      (data intent)
   │   SignalFlowShortcuts : AppShortcutsProvider            (Shortcuts/Siri/Spotlight)
   │   AppNavigationModel · AppIntentsEnvironment            (bridges + DI seam)
   │        │ depends on
   ▼        ▼
 DomainKit  SnapshotKit ──→ PersistenceKit ──→ SwiftData
              (FleetSummary · WidgetSnapshotReader · DeepLinkRoute)
```

`AppIntentsKit` depends only on **DomainKit** and **SnapshotKit** (+ Apple's `AppIntents`). It has **no**
edge to `DataKit`, `SimulationKit`, `NetworkingKit`, or `IntelligenceKit` — enforced by
`Scripts/check-boundaries.sh` (Rules 10 & 11).

## 25.2 Deep-link strategy

A single `DeepLinkRoute` enum (in `SnapshotKit`) is the one source of truth for the app's routes,
shared by **widgets, App Intents, Spotlight, and external URLs**:

```swift
public enum DeepLinkRoute: String, Sendable, CaseIterable {
    case dashboard, fleet, alerts, insights
    public static let scheme = "signalflow"
    public var url: URL { URL(string: "\(Self.scheme)://\(rawValue)")! }   // signalflow://alerts
    public init?(url: URL) { … }                                            // parse it back
}
```

There are **two** ways a route reaches the UI, both converging on a single tab-selection in `RootView`:

1. **URL deep links** (`signalflow://dashboard|fleet|alerts|insights`) — used by widgets, Spotlight, and
   external callers. `RootView.onOpenURL` parses the URL into a `DeepLinkRoute` and selects the tab.
2. **App Intents** — an `AppIntent` can't push a tab directly, so the navigation intents publish a
   `DeepLinkRoute` to the shared `@MainActor` `AppNavigationModel`; `RootView` observes `pendingRoute`
   (via `.onChange`, plus a `.task` to catch a route requested during cold launch) and selects the tab.

Keeping the route enum in one place means producers and the consumer can never drift apart on a string,
and adding a destination is a one-line change that every surface picks up.

## 25.3 Why intents read persisted data, not live services

The "Show Fleet Summary" intent answers **without opening the app**, which means it can run in a
short-lived background launch with a tiny resource budget. The same reasoning as the widgets applies
(see [WidgetKit](docs/24-widgetkit.md)):

- **The live data engine belongs to the foreground app.** `DataKit`'s actor-based `SimulatedDataSource`
  (and, later, a `NetworkingKit` backend) is a long-lived ingestion stack. Spinning it up to answer a
  one-shot Siri query would be wasteful, and `SimulationKit` would invent *different* numbers than the
  app last showed.
- **The app already persisted the reconciled truth.** As telemetry flows, the app writes the latest
  per-device state and active alerts to SwiftData. That snapshot is exactly what a glance answer should
  reflect.
- **So the intent reads the snapshot through a small abstraction.** `ShowFleetSummaryIntent` calls a
  `FleetSummaryProviding` whose live implementation reads `SnapshotKit.WidgetSnapshotReader`
  (PersistenceKit → SwiftData). The answer mirrors the app and stays cheap, offline-friendly, and
  deterministic.

### Dependency injection seam

App Intents ship a `@Dependency` property wrapper, but it traps at runtime when resolving a **protocol
existential** (`any FleetSummaryProviding`) against a registered concrete type. Rather than reach for
`@unchecked Sendable`, the intent reads its provider from a tiny `@MainActor` holder
(`AppIntentsEnvironment.fleetSummaryProvider`): process-global, isolation-safe, set once at launch by
`AppIntentsBootstrap.register()` (called from the app's `init`), and trivially overridable in tests.
Because all intents run **in the app's process** (there's no separate App Intents extension target),
that single registration covers foreground *and* background Shortcuts/Siri invocations.

## 25.4 Shortcuts, Siri & Spotlight

`SignalFlowShortcuts: AppShortcutsProvider` registers all four intents automatically — no per-user
setup. Each `AppShortcut` carries natural-language phrases (with `\(.applicationName)`), a short title,
and an SF Symbol, so the actions appear in the Shortcuts app, surface as Spotlight suggestions, and are
voice-invokable (e.g. *"What's my SignalFlow fleet summary"*).

## 25.5 Privacy considerations

- **No new data leaves the device.** Intents read the same on-device SwiftData store the app already
  maintains; nothing is sent anywhere. The "summary" is computed locally from persisted counts.
- **No live capture from a background query.** Because intents read persisted snapshots rather than
  starting ingestion, answering a Siri query doesn't quietly spin up sensors/among networking.
- **Least privilege.** `AppIntentsKit` cannot even *name* the data engine or `IntelligenceKit`
  (CI-enforced), so an intent can't accidentally trigger on-device AI or a network call.
- **Spoken output is non-sensitive.** The summary is aggregate device counts, not per-device or
  location detail.

## 25.6 Tests

`Tests/SignalFlowKitTests/AppIntents/AppIntentsTests.swift` (serialized — the navigation model and DI
seam are process-global):

| Test | Requirement |
| --- | --- |
| `routeGeneration` | route generation — every `DeepLinkRoute` builds + round-trips its URL; foreign URLs rejected |
| `openIntentsRequestRoutes` | deep-link handling — each Open intent's `perform()` publishes the right route |
| `summaryGeneration` | summary generation — `spokenSummary` reads naturally across fleet states |
| `providerReadsPersistedSnapshot` | intent data provider behavior — the provider aggregates a **real in-memory SwiftData** snapshot via SnapshotKit |
| `showFleetSummaryIntentUsesProvider` | the data intent resolves its provider and returns the spoken summary |

## 25.7 Portfolio value

- **Modern Apple integration done correctly:** App Intents + `AppShortcutsProvider` for zero-setup
  Shortcuts/Siri/Spotlight, with a clean deep-link model shared across widgets and intents.
- **Architecture under pressure:** rather than let a new surface reach into the data layer, the shared
  read model was factored into `SnapshotKit` and the boundary enforced in CI — showing how clean
  architecture scales as integration surfaces multiply.
- **Swift 6 judgement:** worked *with* strict concurrency (a `@MainActor` DI seam and navigation
  bridge) instead of escaping it, and recognised/avoided a real `@Dependency` sharp edge rather than
  papering over it.
