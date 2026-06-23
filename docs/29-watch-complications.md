# 29. watchOS Complications & Smart Stack

A glanceable **Fleet Health** complication for the Apple Watch face and the Smart Stack, rendering the
same fleet snapshot the iPhone syncs to the watch — critical/warning counts, online ratio, the top
critical alert, and an honest stale/fresh state. It completes the watch story: the user no longer has to
*open* the companion to know whether the fleet is healthy.

```
swift build ✅   swift test → 222 tests, 41 suites ✅   ./Scripts/check-boundaries.sh ✅
xcodebuild -scheme SignalFlow -destination 'platform=iOS Simulator,id=<paired iPhone>' … → ** BUILD SUCCEEDED **
  (builds the watch app + the embedded watch widget extension for watchsimulator)
xcodebuild -scheme "SignalFlow Watch App" -destination 'id=<watchOS 26.5 sim>' … → ** BUILD SUCCEEDED **
```

> All complication logic (`WatchWidgetSupportKit` — the projection, freshness, relevance and top-alert
> selection) is compiled cross-platform by `swift build` and unit-tested on the macOS host, so its
> validity is verified in CI without a watch. The WidgetKit views + `TimelineProvider` are
> `#if os(watchOS)`-guarded and built by the watchOS extension target.

## 29.1 Architecture

The watch widget extension is a **thin `@main` shell** over a `WatchWidgetSupportKit` SwiftPM module —
exactly the pattern used for the iOS widgets (`WidgetSupportKit`) and the watch app (`WatchSupportKit`).
No business logic lives in the extension target.

```
SignalFlowWatchWidgets   (Xcode watchOS WidgetKit extension — @main SignalFlowWatchWidgetBundle)
        │ links                                        │ embedded in (PlugIns)
        ▼                                              ▼
WatchWidgetSupportKit  (SwiftPM)                 SignalFlow Watch App
   ├─ WatchComplicationEntry / WatchComplicationModel   pure projection + freshness + relevance (tested)
   ├─ WatchComplicationViewModel                        localized, glanceable strings (tested)
   └─ FleetComplication / WatchFleetProvider / views    #if os(watchOS) WidgetKit + accessory families
        │ depends on
        ▼
   DomainKit   SnapshotKit   WatchConnectivityKit ──→ WatchSyncSnapshotStore (local synced JSON)
```

`WatchWidgetSupportKit` depends only on **DomainKit + SnapshotKit + WatchConnectivityKit**. It has **no**
edge to `DataKit`, `SimulationKit`, `NetworkingKit`, `IntelligenceKit`, `PersistenceKit`/`SwiftData`,
raw `WatchConnectivity`, any sibling glance surface (`WidgetSupportKit`/`AppIntentsKit`/`LiveActivityKit`),
any feature, or the app — enforced by `Scripts/check-boundaries.sh` **Rule 16**. The complication renders
the exact `SnapshotKit` read model (`FleetSummary`, `WidgetAlert`) the watch app, widgets and App Intents
already speak, so a device counts as "critical" on the watch face for the same deterministic reason it
does everywhere else.

### Why a separate module from `WidgetSupportKit`

The iOS widgets read the **App Group** SwiftData store via `SnapshotKit.WidgetSnapshotReader`. App Groups
**don't cross the iPhone↔Watch device boundary** (see [§27](27-watchos-companion.md)), so the watch
complication can't use that path. It instead reads the watch-local **synced** snapshot
(`WatchConnectivityKit.WatchSyncSnapshotStore`, the same JSON file the watch app renders from). Different
data source, different platform, different families — a dedicated module keeps each surface honest and the
boundaries crisp.

## 29.2 Data source & freshness

- **Source of truth:** `WatchSyncSnapshotStore.load()` → `WatchSyncSnapshot` (fleet summary · device
  snapshots · critical alerts · `lastUpdated`). The iPhone pushes it over WatchConnectivity; the watch
  app persists it; the complication's `TimelineProvider` reads the same file. The widget extension shares
  the watch app's App Group (`group.com.signalflow.shared`) so it sees that file.
- **Projection (pure, tested):** `WatchComplicationModel.entry(from:now:)` maps the snapshot to a
  `WatchComplicationEntry` — counts, the most-pressing critical alert (most severe, then most recent), a
  freshness anchor (`fleet.lastUpdated ?? snapshot.lastUpdated`), and a `WatchSnapshotFreshness`.
- **Staleness:** if the anchor is older than `staleThreshold` (30 min) the entry is `.stale` — the
  complication **still shows the last-known data**, but flags it ("Stale · 40m ago" instead of
  "Updated 3m ago"). No data yet → `.noData` → a neutral "No data".
- **Refresh policy:** a single entry now, reload after `refreshInterval` (15 min) — like the iOS widgets,
  the watch app refreshes the synced store far more often than a complication can reload.

## 29.3 Display content & families

Severity-first, concise, glanceable. Examples: `"2 critical · 8/10 online"`, `"2 warnings"`,
`"All nominal"`, `"No data"`, and a freshness footnote `"Updated 3m ago"` / `"Stale · 40m ago"`.

| Family | Layout |
| --- | --- |
| `accessoryInline` | one tinted line — the status line + a severity glyph |
| `accessoryCircular` | the worst count + glyph over `AccessoryWidgetBackground` |
| `accessoryCorner` | a corner glyph with a curved status label (`.widgetLabel`) |
| `accessoryRectangular` | status headline + top critical device + freshness footnote |

Tapping any family opens the watch app (`widgetURL(DeepLinkRoute.fleet.url)`). All text is localized
(English + Spanish) via the extension's `Localizable.xcstrings`; domain enums stay language-neutral.

## 29.4 Smart Stack relevance

The same extension feeds the Smart Stack. Each entry exposes `relevanceScore` (pure, tested), bridged to
WidgetKit via `TimelineEntryRelevance`:

- `critical × 10 + warning × 3` — criticals dominate, warnings matter, …
- … all-nominal gets a small non-zero floor (`0.5`) so it can still surface when quiet, …
- … and **stale** data is damped (`× 0.5`) so a fresh-but-quiet fleet can out-rank an old alarming one.

So the Fleet Health widget rises to the top of the Smart Stack precisely when there's something worth a
glance, and recedes when the fleet is calm.

## 29.5 Xcode integration

- New target **`SignalFlowWatchWidgets`** (`com.apple.product-type.app-extension`, `SDKROOT = watchos`,
  bundle id `com.signalflow.SignalFlow.watchkitapp.widgets`, `NSExtensionPointIdentifier =
  com.apple.widgetkit-extension`).
- **Embedded in the watch app**, not the iOS app: the `SignalFlow Watch App` target gained an *Embed
  Foundation Extensions* copy phase (PlugIns) + a target dependency on the widget extension. Building the
  watch app (directly, or as the iOS app's embedded companion) therefore builds and embeds the
  complication.
- The extension shares the watch app's App Group entitlement so it can read the synced snapshot file.
- The existing iPhone widgets (`SignalFlowWidgets`) are **untouched** — a different target, on a different
  platform, reading a different (App Group) source.

## 29.6 Tests

`Tests/SignalFlowKitTests/WatchWidgets/WatchComplicationTests.swift` (all on the macOS host, no watch):

| Test | Requirement |
| --- | --- |
| `fleetProjection` | fleet summary projection — counts from the synced snapshot |
| `noDataEntry` | empty snapshot → no-data entry + status line |
| `freshVsStale` / `freshnessFallsBackToSyncTime` | stale vs fresh state (still carries last-known data) |
| `relevanceScoring` | Smart Stack relevance (severity-ranked, stale-damped) |
| `topAlertSelection` | top critical alert selection (most recent) |
| `statusLine` / `compactCount` | composed, severity-first display text |
| `spanishCatalog` / `spanishCatalogPlurals` | localized strings / catalog coverage (en + es) |

## 29.7 Limitations / out of scope

- **Freshness is bounded by sync cadence.** The complication is exactly as fresh as the last
  WatchConnectivity push (the iPhone currently pushes while its app is foreground). Background refresh /
  complication push is a separate future PR; the stale treatment is the honest interim.
- **No per-complication configuration** (`StaticConfiguration`) — one Fleet Health widget; deliberate for
  a focused glance.
- **One-way still.** The complication only reads the synced snapshot; acknowledging alerts from the watch
  remains out of scope (it would need a reverse command channel writing into the domain).
- **Device-specific complications** (a single device's status) are not included — the glance is the
  whole-fleet rollup.
