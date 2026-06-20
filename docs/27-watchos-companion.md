# 27. watchOS Companion

A minimal, glanceable Apple Watch companion: **Fleet Summary → Critical Alerts → Device Snapshot**,
reading the same persisted fleet state the iPhone app maintains. It completes the Apple-ecosystem story
— the same domain truth now renders on iPhone, Home Screen widgets, Siri/Shortcuts, the Dynamic Island,
and the wrist.

```
swift build ✅   swift test → 182 tests, 38 suites ✅   ./Scripts/check-boundaries.sh ✅
xcodebuild -scheme SignalFlow -sdk iphonesimulator … → ** BUILD SUCCEEDED ** ✅  (no regression)
xcodebuild -scheme "SignalFlow Watch App" -destination 'id=<watchOS 26.5 sim>' … → ** BUILD SUCCEEDED ** ✅
  installed on watch simulator ✅   launched ✅   no crash on launch ✅
```

> All watch code (`WatchSupportKit` — every screen, model, and provider) is compiled cross-platform by
> `swift build` and unit-tested on the macOS host, so its validity is verified in CI without a watch.
> It has additionally been **verified on a real watchOS 26.5 simulator** (see §27.4): the Xcode target
> builds, installs, and launches without crashing.

## 27.1 Architecture

The watch app is a **thin shell** over a `WatchSupportKit` SwiftPM module — exactly the pattern used for
the iOS host and the widget extension. No business logic is duplicated on the watch.

```
SignalFlow Watch App   (Xcode watchOS target — @main shell: SignalFlowWatchApp → WatchRootView)
        │ links
        ▼
WatchSupportKit  (SwiftPM, depends on DomainKit + SnapshotKit)
   ├─ WatchRootView / FleetSummary / CriticalAlerts / DeviceSnapshot   watch-native SwiftUI screens
   ├─ WatchStore                                                       @Observable, loads a snapshot
   ├─ FleetSummaryViewModel / AlertListViewModel                       pure projections (tested)
   └─ WatchSnapshot + PersistedWatchSnapshotProvider                   reads via SnapshotKit
        │ depends on
        ▼
   DomainKit   SnapshotKit ──→ PersistenceKit ──→ SwiftData
```

`WatchSupportKit` depends only on **DomainKit** + **SnapshotKit**. It has **no** edge to `DataKit`,
`SimulationKit`, `NetworkingKit`, `IntelligenceKit`, or any feature module — enforced by
`Scripts/check-boundaries.sh` (Rule 13). The watch reuses the exact `SnapshotKit` aggregation
(`FleetSummary`, `WidgetAlert`, `WidgetSnapshotReader`) that backs the widgets and App Intents, so a
device counts as "critical" on the wrist for precisely the same deterministic reason it does everywhere
else.

### Project integration

The `SignalFlow Watch App` target is **standalone** in the Xcode project: it has its own scheme and is
**not** embedded in (nor a dependency of) the iOS app target. That's a deliberate CI choice — building
`-scheme SignalFlow -sdk iphonesimulator` stays byte-for-byte unchanged and never triggers a watch
build, so existing CI can't regress. The watch builds via its own command (below). Making it an embedded
companion later is a one-line project change (add an "Embed Watch Content" phase); it's kept separate
here to keep each platform's CI build hermetic.

## 27.2 Why the watch reads persisted snapshots (and never runs DataKit/SimulationKit)

- **A watch app is resource-constrained and short-lived.** It shouldn't host the live ingestion engine.
  `DataKit`'s actor-based `SimulatedDataSource` (and a future `NetworkingKit` backend) belongs to the
  iPhone app.
- **Running the simulation on the watch would *fabricate a different fleet*.** `SimulationKit` is seeded
  RNG; a second instance on the watch would invent its own numbers, diverging from what the user sees on
  iPhone. The watch must mirror the phone's reconciled truth, not generate a parallel reality.
- **So the watch only reads.** `PersistedWatchSnapshotProvider` loads the persisted snapshot through
  `SnapshotKit.WidgetSnapshotReader` (PersistenceKit → SwiftData) and never starts ingestion. This keeps
  the watch cheap, deterministic, and consistent with the phone — the same rationale as the widgets and
  App Intents (see [WidgetKit](docs/24-widgetkit.md), [App Intents](docs/25-app-intents.md)).

## 27.3 UI decisions for watchOS

- **Glanceable, severity-first.** The Fleet Summary leads with a single large headline
  (`"1 critical"` / `"2 warning"` / `"All clear"`) coloured by the worst state, then compact stat rows.
- **Navigation is a `NavigationStack`.** Fleet Summary → (NavigationLink) Critical Alerts →
  (`navigationDestination(for: WidgetAlert.self)`) Device Snapshot. Severity drives ordering: alerts are
  sorted most-severe-then-most-recent.
- **Native components only.** `List`, `Label`, `ContentUnavailableView`, `LabeledContent`,
  monospaced-digit counts. No custom chrome, no iOS-only modifiers — the views compile on watchOS *and*
  the macOS host (so they're built by `swift build` and the logic is unit-tested in CI).
- **Clear empty state.** When the persisted store has no devices yet, the watch shows a
  `ContentUnavailableView` — *"Open SignalFlow on your iPhone to sync fleet status to your watch."* — so
  the absence of data is explained rather than looking broken.

## 27.4 Data delivery & limitations

- **App Group containers are per-device.** The iPhone and the watch don't automatically share the
  `group.com.signalflow.shared` SwiftData store across the device boundary. In a shipping product, the
  iPhone would push snapshots to the watch via **WatchConnectivity** (or the watch would sync its own
  store). That sync layer is intentionally **out of scope** here — so on a fresh watch the store is empty
  and the app shows its empty state, which is exactly the documented behavior (requirement 5). The read
  path, models, screens, and navigation are all real and tested; only the cross-device transport is
  stubbed out as future work.
- **No physical Apple Watch needed.** All logic is unit-tested on the macOS host, and `WatchSupportKit`
  (the whole watch UI) is compiled by `swift build`. The `xcodebuild` watch build needs the **watchOS
  simulator runtime** installed (it resolves a watch destination); the SDK alone is not enough. On a
  machine without that runtime, `xcodebuild` reports *"watchOS … is not installed"* during destination
  resolution — that's an environment/component gap, not a project error.
- **Standalone, not embedded** (see §27.1) — installing on a real paired watch would require the
  embed-watch-content step; the target builds, installs, and runs in the watchOS Simulator as-is.

### Verified on the watchOS 26.5 Simulator

With the watchOS 26.5 runtime installed, the target was end-to-end verified on an Apple Watch
Series 11 (46mm) simulator:

| Step | Result |
| --- | --- |
| `xcodebuild build` (scheme `SignalFlow Watch App`, watchOS 26.5 sim) | **BUILD SUCCEEDED** |
| `simctl install` onto the watch simulator | success |
| `simctl launch com.signalflow.SignalFlow.watchkitapp` | launched (got a PID) |
| process liveness after launch | alive in `launchctl`, **no crash log** |

The only build console note is benign and expected — `appintentsmetadataprocessor … No AppIntents.framework
dependency found` — because the watch app intentionally doesn't link App Intents.

**Observed runtime behavior:** the app launches straight into its **empty state** —
*"Open SignalFlow on your iPhone to sync fleet status to your watch."* This is the **expected** behavior
today: App Group containers are per-device, and the WatchConnectivity sync that would push the iPhone's
persisted snapshot to the watch is **intentionally not implemented yet** (see the App Group note at the
top of this section). The read path, models, screens, navigation, and empty state are all real and
exercised; only the cross-device transport is pending — a future iteration.

### Build command (documented for CI)

Run on a machine with the watchOS simulator runtime installed (e.g. GitHub's `macos` runners, or locally
via *Xcode → Settings → Components*). Target a **concrete simulator by `id`** — the generic destination
needs the runtime to enumerate devices, and several same-named watches make `name=` ambiguous:

```bash
# list the available watch simulators and pick an id
xcrun simctl list devices available | grep -i watch

xcodebuild build \
  -project App/SignalFlow.xcodeproj \
  -scheme "SignalFlow Watch App" \
  -destination 'id=<watchOS 26.5 simulator udid>' \
  CODE_SIGNING_ALLOWED=NO
```

## 27.5 How this completes the Apple ecosystem story

SignalFlow now renders one deterministic domain truth across the whole platform family:

| Surface | Reads from | Module |
| --- | --- | --- |
| iPhone app | live engine → persists | Features + DataKit |
| Home Screen widgets | persisted snapshot | WidgetSupportKit → SnapshotKit |
| Siri / Shortcuts / Spotlight | persisted snapshot | AppIntentsKit → SnapshotKit |
| Dynamic Island / Lock Screen | deterministic alert state | LiveActivityKit |
| **Apple Watch** | **persisted snapshot** | **WatchSupportKit → SnapshotKit** |

Every glance surface hangs off the same `SnapshotKit` read model and `DomainKit` policies — the central
architectural payoff: adding a whole new platform was a thin, read-only module plus a target, with the
boundary enforced in CI, and zero changes to the domain or data layers.

## 27.6 Tests

`Tests/SignalFlowKitTests/Watch/WatchSupportTests.swift`:

| Test | Requirement |
| --- | --- |
| `fleetSummaryModel` | fleet summary model — counts + severity-first headline |
| `emptyState` | empty state — a fleet with no devices reads as no-data |
| `alertSeverityOrdering` | alert list model + severity ordering |
| `providerReadsPersistedSnapshot` | snapshot provider behavior over a **real in-memory SwiftData** store |
| `providerEmptyStore` | provider reports no-data for an empty store |
| `storeRefresh` | the `WatchStore` loads through its provider |

All run on the macOS host — no Apple Watch required.
