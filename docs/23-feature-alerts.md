# 23. FeatureAlerts

An **Alerts** console: a single screen for triaging what's wrong in the fleet *right now* and seeing
what's already been resolved. It lists fleet-wide **active alerts** with device/asset context,
offers a **resolved history**, lets an operator **acknowledge** an alert, and filters by severity —
all through `DomainKit` ports, with the alert lifecycle kept fully deterministic.

```
swift build ✅   swift test → 152 tests, 34 suites ✅   ./Scripts/check-boundaries.sh ✅
xcodebuild -scheme SignalFlow -sdk iphonesimulator … → ** BUILD SUCCEEDED ** ✅
```

## 23.1 What the screen does

The Device Detail screen already shows one device's alerts. FeatureAlerts answers the *operator's*
question instead: across the whole fleet, what needs my attention, and what just happened?

- **Active tab** — every unresolved alert in the fleet, each with its device, asset, severity,
  message, and time. Ordered so attention flows correctly: **unacknowledged first, then most severe,
  then most recent** (`AlertsModel.activeOrdering`). An acknowledged-but-still-active alert sinks
  below fresh ones without disappearing.
- **History tab** — alerts that have since cleared, newest first, each noting whether it had been
  acknowledged before it resolved.
- **Severity filter** — a toolbar `Menu` narrowing either list to info / warning / critical.
- **Acknowledge** — a per-row action on active, unacknowledged alerts.
- **States** — `ProgressView` while first loading; `ContentUnavailableView` for the error case and
  for each empty case (healthy fleet, empty history, or a filter that matches nothing).

The list is a plain SwiftUI `List` with native severity tags and relative timestamps — information
density and severity hierarchy without bespoke chrome.

## 23.2 Architecture & dependency boundaries

FeatureAlerts is a vertical slice that depends on **`DomainKit` + `DesignSystemKit` only** — the same
rule every feature follows, enforced by the package graph *and* `Scripts/check-boundaries.sh`. It
cannot name `DataKit`, `PersistenceKit`, `NetworkingKit`, or `SimulationKit`.

```
AlertsScreen (SwiftUI view)
  └─ AlertsModel  (@MainActor @Observable)
       ├─ AssetRepository          ┐
       ├─ DeviceRepository         │ DomainKit ports — the only contracts the feature sees
       ├─ AlertRepository          │
       └─ AlertHistoryProviding    ┘
```

The model receives all four as `any …` protocol existentials through its initializer; the concrete
`Store…Repository` implementations are wired **only** in the composition root
(`SignalFlowApp.AppContainer` → `RootView`). The feature has no idea its data comes from an in-memory
simulation store — swapping in a networked source would not touch a line of FeatureAlerts.

### The one additive DomainKit change

`AlertRepository` is intentionally **active-only** (`activeAlerts(forDevice:)`) — it models live
state, not an archive. The History tab needs a fleet-wide, time-ordered query of *resolved* alerts,
which no existing port expresses. Rather than overload `AlertRepository` (and force every conformer
to grow a method) or have the feature reach past its ports, we added one focused port:

```swift
public protocol AlertHistoryProviding: Sendable {
    /// Resolved alerts across the fleet, newest first, capped at `limit`.
    func alertHistory(limit: Int) async throws -> [Alert]
}
```

Single method, additive, no existing contract touched. It mirrors how `InsightsProviding` and the
other ports are shaped, and keeps the read model honest: "active" and "historical" are different
questions answered by different ports.

The history itself is produced in the data layer: when `InMemoryTelemetryStore` clears an alert on
recovery, it **archives** the cleared `Alert` (preserving its acknowledgement) into a bounded buffer
that `StoreAlertHistoryRepository` reads. This history is **session-scoped and in-memory** — it is
not persisted across launches (the SwiftData layer restores devices/readings, not the alert archive).
That's a deliberate scope choice for a portfolio simulation, and an obvious seam for a future
`PersistenceKit`-backed `AlertHistoryProviding`.

## 23.3 The acknowledgement flow

Acknowledging is a forward-only domain operation (`Alert.acknowledge(at:)` — it never un-acknowledges)
that flows cleanly through the layers and updates the UI **deterministically**:

```
tap "Acknowledge"
  → AlertsModel.acknowledge(id)
      → AlertRepository.acknowledgeAlert(id, at: now())   // store stamps acknowledgedAt
      → AlertsModel.refresh()                              // re-reads ports, rebuilds rows
  → row re-renders as "Acknowledged" and sinks in the ordering
```

`refresh()` rebuilds the lists from the ports rather than mutating in place, so the screen always
reflects store truth — no optimistic local state to drift. The `now` closure is injected (defaulting
to `Date()`), so tests acknowledge at a fixed instant.

### Why acknowledgement matters beyond the row

A device's health is computed by the pure `DomainKit.DeviceHealthPolicy`, which **ignores
acknowledged alerts** (`activeAlerts.filter { !$0.isAcknowledged }`). So acknowledging a critical
alert doesn't just restyle a row — it removes that alert from the device's status calculation, so the
Dashboard and Fleet surfaces stop showing the device as critical. The alert stays *active but
acknowledged* (an operator has seen it; the condition hasn't physically cleared yet) until a
recovering reading clears it, at which point it's archived to history with its acknowledgement
intact. This end-to-end behavior is covered by `acknowledgeClearsDeviceHealth` in the DataKit tests.

## 23.4 Why alerts stay deterministic (not AI-driven)

SignalFlow has an on-device AI feature ([Insights](docs/20-foundation-models-insights.md)), but
alerts are deliberately **outside** the AI boundary. Whether an alert is raised or cleared is decided
solely by `AlertRule.evaluate` against numeric thresholds in the data layer; FeatureAlerts only
*reads* that state, joins context, and acknowledges. No model is asked "is this a problem?" — that
keeps safety logic auditable, reproducible, and testable, and it's why the alert lifecycle can be
verified with deterministic Swift Testing tests rather than probabilistic assertions.

## 23.5 How it reuses existing layers

Nothing here is a parallel stack:

| Concern | Reused from |
| --- | --- |
| Alert raising / clearing / dedup | `AlertRule.evaluate` + `InMemoryTelemetryStore` (DataKit) |
| Acknowledgement semantics | `Alert.acknowledge(at:)` (DomainKit, forward-only) |
| Active alerts, device & asset context | `AlertRepository`, `DeviceRepository`, `AssetRepository` |
| Health interaction | `DeviceHealthPolicy` (already ignores acknowledged) |
| Severity tags, spacing, asset symbols | `DesignSystemKit` (`SeverityTag`, `Spacing`, `AssetKind.symbol`) |
| `@Observable` model + phase/observe pattern | same shape as `FeatureInsights` / `FeatureFleet` |

The only net-new surface is the `AlertHistoryProviding` port, its store-backed implementation, and
the feature itself (`AlertsModel`, `AlertsScreen`, `AlertsPresentation`).

## 23.6 Tests

| Test | What it proves |
| --- | --- |
| `loadsActiveAlerts` | active alerts load with joined device/asset context |
| `loadsHistory` | resolved alerts surface in the History tab |
| `filtersBySeverity` | the severity filter narrows the visible list |
| `acknowledgeUpdatesRow` | acknowledging flips the row and drops the unacknowledged count |
| `ordersUnacknowledgedFirst` | unacknowledged sorts ahead of a more-severe acknowledged alert |
| `emptyState` | a healthy fleet loads to an empty (not failed) state |
| `errorState` | a throwing port surfaces `.failed` |
| `clearedAlertIsArchived` | a recovered alert moves to history rather than vanishing |
| `archivedAlertKeepsAcknowledgement` | history records prior acknowledgement |
| `acknowledgeClearsDeviceHealth` | acknowledging removes an alert from device health end-to-end |

Model tests run against port fakes (including a stateful actor-based `AlertRepository` so
acknowledgement actually mutates); the archiving and health tests run against the real
`InMemoryTelemetryStore`.
