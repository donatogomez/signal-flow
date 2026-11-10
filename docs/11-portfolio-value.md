# 11. Evidence Map & Known Limitations

SignalFlow exists to show how I build iOS software, so this document does two things: it maps each
engineering claim to the code that backs it, and it lists what the project deliberately does **not**
do. If a claim here can't be traced to a file, it shouldn't be here.

## 11.1 Evidence map

| Area | What is implemented | Where to look |
| --- | --- | --- |
| Module boundaries | 21 SwiftPM library targets; features can't import the data layer because they don't declare it, plus a CI script that rejects forbidden imports | [`Package.swift`](../Package.swift), [`check-boundaries.sh`](../Scripts/check-boundaries.sh), [ADR-0001](adr/0001-clean-architecture-with-spm-modules.md) |
| Concurrency model | One owner per piece of mutable state (device actors, store actor, `@ModelActor`); `TaskGroup` fan-out; cancellation via `onTermination` and `.task`; reentrancy-safe lifecycle | [Concurrency](07-concurrency.md), `SimulationKit/Actors`, `DataKit/Adapter`, `SignalFlowApp/AppContainer.swift` |
| Domain modeling | Phantom-typed ids, validating value objects, forward-only alert acknowledgement, pure rules and health policy | `DomainKit/Identifiers`, `DomainKit/ValueObjects`, `DomainKit/Entities`, `DomainKit/Policies` |
| Deterministic simulation | Seeded RNG, simulated clock separating instants from pacing, stable seeded identities | `CoreKit`, `SimulationKit/Clock`, [SimulationKit](15-simulation-kit.md) |
| Persistence | SwiftData behind a `@ModelActor`, domain-only API, batched writes, per-series retention, restore-on-launch, App Group store shared with widgets | `PersistenceKit`, `DataKit/Persistence`, [SwiftData Persistence](21-swiftdata-persistence.md) |
| On-device AI | Foundation Models guided generation over facts computed in Swift; severity and confidence computed in Swift too; deterministic fallback; alerting never depends on the model | `IntelligenceKit`, `DomainKit/Insights`, [ADR-0004](adr/0004-foundation-models-on-device.md) |
| Networking | `URLSession` client with typed endpoints, DTO mapping, error mapping and retry; behind a gateway, not wired by default | `NetworkingKit`, [NetworkingKit](22-networking-kit.md) |
| Platform surfaces | Widgets, App Intents, Live Activity, watchOS app + complications — all read persisted or synced state only | `WidgetSupportKit`, `AppIntentsKit`, `LiveActivityKit`, `Watch*Kit` |
| Testing | 272 Swift Testing tests, plus 4 app-hosted ActivityKit tests in the simulator; stub ports; in-memory SwiftData; deterministic concurrency tests | [Testing Strategy](09-testing-strategy.md), `Tests/` |
| Decisions | ADRs with rejected alternatives and consequences | [`docs/adr`](adr) |

## 11.2 Known limitations

These are deliberate scope decisions, not oversights:

- **Simulated data only.** The app runs on a built-in simulator. A REST gateway exists behind the same
  seam but is not wired, and there is no auth, live broker (WebSocket/MQTT) or sync protocol.
- **Polling, not observation.** Screens re-read the ports every 3 s instead of observing a change
  stream from the store (see [Concurrency §7.4](07-concurrency.md#74-presentation-polling-not-stream-observation)).
- **No back-pressure.** Telemetry streams use unbounded buffers. With the clock-paced simulator, the
  buffer stays bounded because a SwiftData flush takes ~320 ms of the ~850 ms budget (measured on an
  M1 Pro), not because anything enforces it. A real source would need a bounded policy
  ([§7.2](07-concurrency.md#72-the-telemetry-pipeline)).
- **The store file grows while the app runs.** Row counts are capped, but SwiftData's persistent
  history records every insert and prune and is never deleted. That is ~70 bytes per reading, roughly
  75 MB per hour of foreground use at the live rate. A fix is proposed but not applied
  ([§21.9](21-swiftdata-persistence.md#persistent-history-grows-without-bound)).
- **Restore is a snapshot, not a history.** Relaunch restores the latest value per metric, active
  alerts, events and insights. Charts start filling again from new telemetry.
- **Persistence is best-effort, not durable delivery.** A failed write is retried from memory, within
  a bound, until it succeeds; if the app ends first, those items are lost. Write failures are logged,
  not shown in the UI ([§21.4](21-swiftdata-persistence.md#when-a-write-fails)).
- **Glance surfaces can't tell "no data" from "unreadable".** Widgets and App Intents fall back to an
  empty payload when the shared store can't be read; the failure is only logged.
- **Mostly host-only test execution.** The suite runs on macOS. Of the iOS/watchOS-only code, only the
  ActivityKit service runs in a simulator, in an app-hosted bundle
  ([§26.8](26-live-activities.md#268-tests)). WatchConnectivity delegates and watch WidgetKit views are
  compiled in CI but not exercised by tests.
- **No UI or snapshot tests**, and no measured performance baselines on device.
- **Insight severity is rule-based, not predictive.** An insight is a *concern* when the device has
  active alerts and a *watch* when its trend is volatile; it doesn't forecast a threshold crossing.
  The model only phrases the insight and never picks its severity. Insights are also generated when
  the Insights tab appears, not every 3 s like device status, so a reefer whose alert has just cleared
  can still show a *concern* from a few seconds earlier until the feed regenerates.
- **Foundation Models output is device-dependent**, and unavailable on devices without Apple
  Intelligence, where the deterministic provider is used.
- **Single package, solo maintainer.** One multi-target package rather than several, the simplest
  setup that still enforces boundaries.
