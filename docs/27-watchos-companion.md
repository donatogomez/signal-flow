# 27. watchOS Companion

A glanceable Apple Watch companion: **Fleet Summary → Active Alerts / Devices → Device Snapshot**,
rendering the fleet state the iPhone syncs over WatchConnectivity. It completes the Apple-ecosystem story
— the same domain truth now renders on iPhone, Home Screen widgets, Siri/Shortcuts, the Dynamic Island,
and the wrist — and its UI is **fully localized** (English + Spanish), matching the rest of the app.

```
swift build ✅   swift test → 212 tests, 40 suites ✅   ./Scripts/check-boundaries.sh ✅
xcodebuild -scheme SignalFlow -destination 'platform=iOS Simulator,id=<paired iPhone>' … → ** BUILD SUCCEEDED ** ✅  (embeds + builds the watch app)
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
WatchSupportKit  (SwiftPM, depends on DomainKit + SnapshotKit + WatchConnectivityKit)
   ├─ WatchRootView / FleetSummary / CriticalAlerts / Devices / DeviceSnapshot   watch-native SwiftUI screens
   ├─ WatchStore                                                       @Observable, loads a snapshot
   ├─ FleetSummaryViewModel / AlertListViewModel / AlertRowViewModel   pure projections (tested)
   │  DeviceListViewModel / DeviceSnapshotViewModel
   └─ WatchSnapshot + Synced/PersistedWatchSnapshotProvider            reads synced snapshot / SnapshotKit
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

The `SignalFlow Watch App` target is **embedded** in the iOS app: the app target has an _Embed Watch
Content_ copy-files phase (`$(CONTENTS_FOLDER_PATH)/Watch`) plus a target dependency on the watch app.
Installing the iPhone app therefore installs its companion watch app, which is what makes
`WCSession.isWatchAppInstalled` report `true` — without the embed, the phone has no companion to sync to
(`WCErrorCodeWatchAppNotInstalled`). The watch's bundle id (`com.signalflow.SignalFlow.watchkitapp`) is
prefixed by the iOS app's, and its `Info.plist` carries `WKApplication` + `WKCompanionAppBundleIdentifier`.

**Build consequence:** the iOS build graph now also builds the watch app for `watchsimulator`, so the iOS
build must target a **concrete iPhone simulator that has a paired watch** (`xcrun simctl list pairs`). The
`generic/platform=iOS Simulator` destination can't resolve a paired watch and mis-targets the watch's
Swift-package products to `iphonesimulator` (`Build input file cannot be found: …WatchSupportKit.o`); a
concrete paired destination builds cleanly. The watch app still also builds on its own scheme (below).

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
  (`"1 critical"` / `"2 warnings"` / `"All clear"`) coloured by the worst state, then compact stat rows
  (online / warning / critical / offline) and an *"Updated <relative>"* freshness line.
- **Three screens, one `NavigationStack`.** Fleet Summary → **Active Alerts** *and* **Devices** (both
  reachable from the summary) → **Device Snapshot**. Navigation is value-based
  (`navigationDestination(for: WidgetAlert.self)` / `WatchDeviceSnapshot.self`); tapping an alert resolves
  its device (joined by name) so the snapshot shows full device detail, falling back to an alert-only view
  when the device isn't in the synced set.
- **Device Snapshot shows the operational detail a glance needs:** status, battery (with a charging
  bolt), connectivity, *last seen*, and a few **telemetry highlights** (newest reading per metric,
  environmental-signals first, capped at three) — all *if present*, so a sparse device degrades cleanly.
- **Severity is visual everywhere.** Status/severity drive both an SF Symbol and a tint (green / orange /
  red / grey); alerts sort most-severe-then-most-recent, devices sort worst-status-first then by name.
- **Native components only.** `List`, `Label`, `ContentUnavailableView`, `LabeledContent`,
  monospaced-digit counts. No custom chrome, no iOS-only modifiers — the views compile on watchOS *and*
  the macOS host (so they're built by `swift build` and the logic is unit-tested in CI).
- **Clear empty states.** No synced fleet yet → *"Open SignalFlow on your iPhone to sync fleet status to
  your watch."*; no active alerts → a reassuring seal; no devices → a neutral placeholder.

### Localization (English + Spanish)

The watch UI is fully localized through `WatchSupportKit`'s string catalog
(`Sources/WatchSupportKit/Resources/Localizable.xcstrings`) — the fleet headline (pluralized:
`"2 warnings"` → `"2 advertencias"`), the `"x/y online"` summary (`"8/10 en línea"`), the
online/offline/warning/critical/degraded labels (`"En línea"` / `"Sin conexión"` / `"Advertencia"` /
`"Crítico"`), the device-snapshot field labels (battery, connectivity, last seen, telemetry), and every
empty state. Telemetry metric names reuse `SnapshotKit.AlertText.metricName` (the same catalog the widgets
and Live Activity use), so the watch never re-translates domain semantics. **`DomainKit` stays
language-neutral** — its `displayName`s remain English diagnostics; localization lives entirely in the
presentation layer (`WatchSupportKit` / `SnapshotKit`).

**Root cause of the earlier English-only watch UI.** The Spanish translations shipped (the
`SignalFlowKit_WatchSupportKit.bundle` carried `es.lproj`), but the **watch app bundle advertised only its
development region**, so watchOS launched it in English and `String(localized:bundle:.module)` resolved
`en.lproj` even on a Spanish device. The fix is `CFBundleLocalizations = [en, es]` in the watch
`Info.plist` (mirroring how the widget extension declares Spanish): the app now advertises Spanish, runs in
Spanish on a Spanish device, and the package bundles' `es.lproj` resolves. *(SwiftPM copies `.xcstrings`
in uncompiled, so on the macOS test host `String(localized:)` only ever yields the English source; the
Spanish/plural translations are therefore verified by reading the catalog directly — see §27.6.)*

## 27.4 Data delivery & limitations

- **App Groups don't cross the device boundary — so WatchConnectivity is required.** An App Group
  container is shared between an app and its *extensions on the same device*; it does **not** sync between
  the iPhone and the Apple Watch (separate devices, separate sandboxes). So the watch cannot read the
  iPhone's `group.com.signalflow.shared` SwiftData store. The iPhone must **send** the data, and the only
  supported channel for that is **WatchConnectivity** (`WCSession`). This is now implemented (see
  *WatchConnectivity sync* below) — a fresh watch shows the empty state only until the first snapshot
  arrives.
- **No physical Apple Watch needed.** All sync logic is unit-tested on the macOS host, and `WatchSupportKit`
  (the whole watch UI) is compiled by `swift build`. The `xcodebuild` watch build needs the **watchOS
  simulator runtime** installed (it resolves a watch destination); the SDK alone is not enough. On a
  machine without that runtime, `xcodebuild` reports *"watchOS … is not installed"* during destination
  resolution — that's an environment/component gap, not a project error.
- **Embedded companion** (see §27.1) — the watch app is embedded in the iOS app, so installing the iPhone
  app installs it on a paired watch and `WCSession.isWatchAppInstalled` reports `true`. The target also
  builds, installs, and runs in the watchOS Simulator standalone.

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

**Observed runtime behavior:** on a fresh watch the app launches into its **empty state** —
*"Open SignalFlow on your iPhone to sync fleet status to your watch."* — and, once the paired iPhone
sends a snapshot over WatchConnectivity, it refreshes to show live fleet status and critical alerts.
(Exercising the full device-to-device hop requires a paired iPhone + Watch simulator pair or hardware;
the snapshot build/encode/persist/decode logic is all unit-tested without a watch.)

### WatchConnectivity sync

Because App Groups don't cross the device boundary (above), the iPhone **pushes** a compact snapshot to
the watch. This lives entirely in a dedicated **`WatchConnectivityKit`** module — the *only* module that
imports `WatchConnectivity` (CI-enforced, Rule 15); features and even `WatchSupportKit` never import the
framework directly.

```
iPhone (SignalFlowApp / AppContainer)                Watch (SignalFlow Watch App)
  reads DomainKit ports → PersistedSnapshot            WatchSnapshotReceiver (WCSession delegate)
  WatchSnapshotBuilder.build → WatchSyncSnapshot         └─ decode → WatchSyncSnapshotStore (local JSON, latest-wins)
  PhoneSnapshotSync.send                                    └─ onUpdate → WatchStore.refresh()
   └─ WCSession.updateApplicationContext([data])  ──▶    SyncedWatchSnapshotProvider reads the store → UI
```

- **What's synced** (`WatchSyncSnapshot`, `Codable` — never `JSONSerialization`): the **fleet summary**,
  per-**device snapshots** (name, asset, status, **battery, connectivity, last-seen, and the newest
  telemetry highlights**), the **active critical alerts**, and a **`lastUpdated`** timestamp. The
  enriched per-device fields are what the Device Snapshot screen renders; they're built on the iPhone by
  `WatchSnapshotBuilder` from the same persisted `Device` + readings the app shows.
- **Transport:** `updateApplicationContext` — it keeps only the *latest* state and delivers it even when
  the watch is asleep, so a simple periodic push (on app start + every few seconds while on screen, from
  `AppContainer.observeWatchSync`) is the simplest reliable strategy. The receiver keeps the newest
  snapshot by `lastUpdated` and ignores stale/out-of-order deliveries.
- **Watch persistence:** the received snapshot is written to a small local JSON file
  (`WatchSyncSnapshotStore`) so it survives relaunches; the watch UI always renders from that store. The
  watch still **never** starts `DataKit`/`SimulationKit`/`NetworkingKit`/`IntelligenceKit`.
- **Out of scope:** **acknowledging (or otherwise acting on) alerts from the watch** — the companion is
  read-only by design; mutating fleet state from the wrist would need a two-way `WCSession` command path
  back to the iPhone's use cases, which isn't built. Also out of scope: background/complication push,
  `transferUserInfo` queues, reachability-based live messaging, and per-watch locale of the **alert
  message** text (the iPhone builds that localized string in its own locale and sends it; the watch's own
  chrome — labels, headline, statuses — *is* localized on-device, see §27.3).

### Build command (documented for CI)

Run on a machine with the watchOS simulator runtime installed (e.g. GitHub's `macos` runners, or locally
via *Xcode → Settings → Components*). Target a **concrete simulator by `id`** — the generic destination
needs the runtime to enumerate devices, and several same-named watches make `name=` ambiguous. (The iOS
app build also embeds the watch app; target a paired iPhone simulator there — see §27.1.)

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
| `watchLabelMapping` | status / severity / connectivity map to the right catalog labels (key selection) |
| `onlineCountSummary` | the `"x/y online"` summary uses the localizable online key |
| `spanishCatalogLabels` | **Spanish labels** present & correct in the shipped catalog (online/offline/warning/critical/degraded, device-snapshot fields, empty states) |
| `spanishCatalogHeadlinePlurals` | **headline localization** — `%lld warning` / `%lld critical` pluralized in Spanish (and English) |
| `spanishCatalogOnlineCount` | **online count localization** — `%lld/%lld online` → `%lld/%lld en línea` |
| `alertRowModel` | **alert row** — device name, passthrough message, severity label |
| `deviceSnapshotModel` | **device snapshot model** — status, battery (rounded %), connectivity, last-seen, telemetry highlights |
| `deviceSnapshotModelMinimal` | device snapshot copes with absent battery / telemetry |
| `deviceListOrdering` | **severity ordering** — devices sort worst-status-first, then by name |
| `deviceListEmpty` | empty state — no synced devices |

`Tests/SignalFlowKitTests/WatchConnectivity/WatchConnectivitySyncTests.swift` additionally covers
`buildsEnrichedDeviceSnapshots` — the iPhone builder populating battery / connectivity / newest-per-metric
telemetry and round-tripping them through the `Codable` wire format.

Spanish strings are asserted by reading `Localizable.xcstrings` directly (SwiftPM ships it uncompiled, so
`String(localized:)` on the macOS host only yields the English source — see §27.3). All run on the macOS
host — no Apple Watch required.
