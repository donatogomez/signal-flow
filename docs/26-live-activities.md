# 26. Live Activities & Dynamic Island

A **critical-alert Live Activity**: when a device raises an active, unacknowledged *critical* alert,
SignalFlow surfaces it outside the app — on the Lock Screen / StandBy and in the Dynamic Island — for
as long as it's ongoing, and deep-links back into the device when tapped.

```
swift build ✅   swift test → 176 tests, 37 suites ✅   ./Scripts/check-boundaries.sh ✅
xcodebuild -scheme SignalFlow -sdk iphonesimulator … → ** BUILD SUCCEEDED ** ✅
```

## 26.1 What it shows

| Surface | Content |
| --- | --- |
| **Lock Screen / StandBy** | Severity, status badge, device name, asset name (if available), the alert reason, and "since" time |
| **Dynamic Island — compact** | Leading: red octagon · Trailing: device name |
| **Dynamic Island — minimal** | Red octagon |
| **Dynamic Island — expanded** | Severity + status, device name, reason, asset · since-time |

Requirement-1 fields — device name, asset name (optional), severity, alert reason, started timestamp,
current status — all live in the activity's `ContentState` (`CriticalAlertState`).

## 26.2 ActivityKit architecture

ActivityKit is **iOS-only**, but `swift build`/`swift test` run on the macOS host. So the code is split:

```
LiveActivityKit  (SwiftPM, depends on DomainKit + SnapshotKit)
├─ CriticalAlertState / AlertActivityStatus     platform-agnostic content model  ← unit-tested
├─ AlertContext / CriticalAlertSelector         deterministic critical selection ← unit-tested
├─ LiveActivityDecision                         pure start/update/end brain       ← unit-tested
├─ CriticalAlertActivityAttributes   #if os(iOS)  ActivityAttributes (+ deepLink)
└─ CriticalAlertActivityService      #if os(iOS)  Activity.request/update/end   (#else: no-op stub)

WidgetSupportKit
└─ CriticalAlertLiveActivity         #if os(iOS)  ActivityConfiguration: Lock Screen + Dynamic Island UI

SignalFlowApp / AppContainer         drives reconciliation from DomainKit ports
```

- The **logic** (mapping, selection, lifecycle) is plain Swift — compiles everywhere, fully testable on
  the macOS CI host.
- The **ActivityKit** pieces are guarded with `#if os(iOS)`. (`#if canImport(ActivityKit)` is *not*
  enough — the framework imports on macOS but its symbols are marked unavailable, so the host build
  fails; `#if os(iOS)` is the correct guard.)
- `CriticalAlertActivityService` ships an `#else` **no-op stub** with the same API, so `AppContainer`
  calls `reconcile(_:)` unconditionally — no `#if` at the call site.
- The **UI** is an `ActivityConfiguration` hosted by the existing `SignalFlowWidgets` extension (added to
  its `WidgetBundle` under `#if os(iOS)`).

### Boundary: ActivityKit never leaks into features

`LiveActivityKit` depends only on `DomainKit` + `SnapshotKit` (+ ActivityKit, guarded). Feature modules
don't link it — and `Scripts/check-boundaries.sh` Rule 2 now forbids features from importing any glance
surface (`SnapshotKit`/`WidgetSupportKit`/`AppIntentsKit`/`LiveActivityKit`/`ActivityKit`), while Rule 12
keeps `LiveActivityKit` itself off the data engine, Foundation Models, SwiftData, and UI.

## 26.3 Dynamic Island layout strategy

Deliberately glanceable, not overloaded:

- **Minimal & compact-leading**: a single red `exclamationmark.octagon.fill` — instantly "something is
  critical." **Compact-trailing**: the device name, truncated.
- **Expanded**: four regions with one idea each — *leading* severity, *trailing* status badge, *center*
  device, *bottom* reason + asset/since. No charts, no counts, no live timers competing for attention.
- Colour comes from `DesignSystemKit` semantics (`AlertSeverity.tint`), so "critical" is the same red as
  everywhere else; `keylineTint` matches.

## 26.4 Lifecycle rules

Reconciliation runs on a steady, cancellation-safe cadence from `AppContainer.observeCriticalAlertActivity()`
(tied to `RootView`'s `.task`). Each tick builds `AlertContext`s from the `DomainKit` ports and calls
`LiveActivityDecision.decide(tracked:criticalContexts:)`:

| Condition | Action |
| --- | --- |
| No activity running + an active **unacknowledged critical** alert exists | **start** |
| Tracked alert still active+unacknowledged, content changed | **update** |
| Tracked alert still active+unacknowledged, unchanged | none |
| Tracked alert **acknowledged** | **end** — final frame `status: .acknowledged` |
| Tracked alert no longer active (**resolved/cleared**) | **end** — final frame `status: .resolved` |

**Chosen end behavior (the documented decision):** the activity ends as soon as the alert is
**acknowledged _or_ resolved**, whichever comes first. On end it shows a brief final
"Acknowledged"/"Resolved" frame (`dismissalPolicy: .after(8s)`), then the system dismisses it.

*Why end on acknowledge?* It mirrors the rest of the app: `DeviceHealthPolicy` already stops counting
acknowledged alerts toward device health, so an acknowledged critical alert is no longer an *ongoing*
crisis that warrants a persistent, attention-grabbing Live Activity. Only one activity runs at a time —
the most recent active unacknowledged critical alert.

## 26.5 Why alerts stay deterministic — and AI is not involved

Whether an alert exists, and whether it's *critical*, is decided entirely by `AlertRule.evaluate`
against numeric thresholds in the data layer (see [FeatureAlerts](docs/23-feature-alerts.md)). The Live
Activity layer only **reads** that state:

- `CriticalAlertSelector` filters by `severity == .critical` and raise time — pure functions of domain
  state.
- `LiveActivityDecision` is a pure state machine over those facts.
- `IntelligenceKit` / Foundation Models are **not linked** by `LiveActivityKit` (CI-enforced, Rule 12),
  so an on-device model can never influence whether an activity starts, what it says, or when it ends.

This keeps a high-visibility, outside-the-app safety signal **reproducible and auditable** — never the
output of a probabilistic model.

## 26.6 Deep-linking behavior

Tapping the activity opens the **device's detail screen** when the device is known, else the **Alerts**
tab. This reuses the existing deep-link system: `SnapshotKit.DeepLink` wraps `DeepLinkRoute` (the tab
contract shared with widgets and App Intents) and adds `case device(DeviceID)` →
`signalflow://device/<uuid>`. `RootView.onOpenURL` resolves a `DeepLink`: a `.route` selects the tab, a
`.device` selects the Fleet tab and pushes that device's detail. The activity's `widgetURL` comes from
`CriticalAlertActivityAttributes.deepLink`, which prefers the device and falls back to `.route(.alerts)`.

## 26.7 Simulator / device limitations

- Live Activities run on a real device or the iOS Simulator; they require the app to call
  `Activity.request(...)`, which the macOS host build (CI) can't exercise — hence ActivityKit code is
  `#if os(iOS)`-guarded and **not** unit-tested. CI tests the deterministic logic instead, so **no
  physical device is required** for `swift test`.
- The app declares `NSSupportsLiveActivities = YES` (set via `INFOPLIST_KEY_NSSupportsLiveActivities` on
  the app target). Users can disable Live Activities in Settings; `start()` checks
  `ActivityAuthorizationInfo().areActivitiesEnabled` and quietly does nothing when disabled.
- The Dynamic Island only renders on Dynamic Island-capable hardware; on other devices the same activity
  appears on the Lock Screen / as a banner. StandBy uses the Lock Screen layout.
- Because the data engine here is a simulation, a critical alert appears when simulated telemetry
  breaches a threshold; on device you'd see the activity start within a reconcile tick of that breach.

## 26.8 Tests

`Tests/SignalFlowKitTests/LiveActivities/LiveActivityTests.swift`:

| Test | Requirement |
| --- | --- |
| `stateMapping` | activity state mapping (domain alert + context → `CriticalAlertState`) |
| `criticalSelection` | critical alert selection (critical only, most-recent first) |
| `noActivityForNonCritical` | no activity for non-critical alerts |
| `lifecycleStart` / `lifecycleNoStartWhenAcknowledged` | lifecycle: start only for unacknowledged criticals |
| `lifecycleUpdate` / `lifecycleNoChange` | lifecycle: update on change, idempotent otherwise |
| `lifecycleEndOnAcknowledge` / `lifecycleEndOnResolve` | lifecycle: end-on-ack vs end-on-resolve, with final status |
| `deepLinkGeneration` | deep-link route generation (tabs + device, round-trip) |

All run on the macOS host — no device, no ActivityKit — satisfying the CI constraint.
