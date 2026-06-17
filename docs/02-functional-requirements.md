# 2. Functional Requirements

Requirements are expressed as capabilities with a priority. The MVP is the smallest slice that is
**demonstrably production-shaped** — it must look like something a team could ship and maintain,
not a toy.

## 2.1 MVP (v1.0)

### Fleet & devices
- **FR-1** Register/import a set of monitored devices (asset type, name, location, thresholds).
- **FR-2** Fleet overview: every device with current status (Nominal / Warning / Critical / Offline)
  derived from domain rules, sortable and filterable by asset type and status.
- **FR-3** Device detail: latest readings for every metric the device reports, with units and
  freshness ("updated 3s ago" / "stale, 4m ago").

### Live telemetry
- **FR-4** Subscribe to a live telemetry stream and update the UI in near-real-time without manual
  refresh, backed by `AsyncSequence`.
- **FR-5** Connectivity awareness: per-device online/offline and signal-strength indication;
  graceful handling of dropouts and reconnection (with history backfill).

### History & visualization
- **FR-6** Persist all received telemetry locally (SwiftData), retained per a configurable policy.
- **FR-7** Time-series charts (Swift Charts) per metric with selectable ranges (1h / 24h / 7d) and
  threshold bands overlaid.
- **FR-8** Offline-first: the entire app (fleet, detail, history, charts) is fully usable with no
  network using the last synced data.

### Alerting
- **FR-9** Rule-based alerts from domain thresholds (hard limits) and basic trend/slope rules.
- **FR-10** Alert inbox: list, filter, and **acknowledge** alerts; acknowledgements persist and
  sync via an outbox when connectivity returns.
- **FR-11** Local notifications for critical alerts (foreground + background).

### On-device intelligence
- **FR-12** AI **trend summary** per device ("last 24h in one paragraph"), generated on-device.
- **FR-13** AI **anomaly explanation** attached to any flagged event.
- **FR-14** AI **fleet digest** ("what needs my attention this morning").

### Cross-cutting
- **FR-15** Settings: thresholds, retention policy, units, data source (live gateway vs simulator).
- **FR-16** A built-in **deterministic simulator** data source so the app is fully demoable with no
  backend — selectable at runtime, indistinguishable to the rest of the app from a live gateway.
- **FR-17** Accessibility: Dynamic Type, VoiceOver labels on all status/chart elements, sufficient
  contrast, color-independent status (never color alone).

### MVP acceptance themes
- Strict concurrency compiles clean (`-strict-concurrency=complete`) with no `@unchecked Sendable`
  escape hatches in app code.
- Every use case and the sync/reconciliation logic is unit-tested with Swift Testing.
- The app launches into a meaningful state with **no network and no configuration** (simulator).

## 2.2 Future roadmap (post-MVP)

Sequenced to show the architecture *absorbs* growth rather than fighting it — the headline portfolio
claim is "designed to evolve for years."

**v1.1 — Depth on existing capabilities**
- Map view for GPS-tracked assets (MapKit), route + geofence breach alerts.
- Configurable, composable alert rules (rule builder) beyond fixed thresholds.
- Report export (PDF/CSV) with the AI incident narrative attached.

**v1.2 — Conversational & predictive**
- Conversational query over the fleet using Foundation Models **tool calling** ("which trucks risk
  a breach in the next 2 hours?"), where the model calls into repositories for grounded answers.
- Predictive nudges from on-device trend extrapolation (battery-death ETA, threshold-breach ETA).

**v1.3 — Platform reach**
- iPad/Mac Catalyst-free multiplatform via SwiftUI (`NavigationSplitView` 3-column).
- Apple Watch companion (glanceable fleet status, critical alerts).
- WidgetKit + Live Activities for an in-progress excursion.

**v2.0 — Multi-tenant & collaboration**
- Multi-user accounts, roles, and shared fleets (introduces a real auth boundary).
- Real broker integration (MQTT/WebSocket) hardened for production, replacing the reference gateway.
- CloudKit sync of user-authored data (thresholds, acknowledgements, notes) across a user's devices.

## 2.3 Nice-to-have features

- **Siri / App Intents**: "Hey Siri, how's my fleet?" → spoken AI digest.
- **Anomaly "replay"**: scrub a timeline and watch status recompute, for incident review.
- **Custom metric plugins**: a typed, extensible metric registry so new sensor types need no
  schema migration (architecturally enabled by the `Metric` value-type design — see
  [Domain Design](05-domain-design.md)).
- **Theming / design tokens** showcase in the Design System module.
- **Localization** (the AI summaries naturally lend themselves to multilingual output).

## 2.4 Traceability

Every functional requirement maps to an owning module and use case so scope stays honest:

| FR | Primary module | Primary use case(s) |
| --- | --- | --- |
| FR-1, FR-2, FR-3 | `FeatureFleet`, `FeatureDeviceDetail` | `ObserveFleet`, `ObserveDevice` |
| FR-4, FR-5 | `CoreTelemetry`, Data | `StreamLiveTelemetry` |
| FR-6, FR-7, FR-8 | `CorePersistence`, `FeatureHistory` | `LoadTelemetryHistory` |
| FR-9, FR-10, FR-11 | `FeatureAlerts`, Domain | `EvaluateAlertRules`, `AcknowledgeAlert` |
| FR-12, FR-13, FR-14 | `FeatureInsights`, `CoreIntelligence` | `SummarizeTrend`, `ExplainAnomaly`, `GenerateFleetDigest` |
| FR-15, FR-16 | `App`, `CoreTelemetry` | composition / `SelectDataSource` |

See [Repository Structure](04-repository-structure.md) for the module definitions referenced above.
