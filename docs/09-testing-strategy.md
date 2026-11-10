# 9. Testing Strategy

The architecture is what makes testing cheap: business rules are pure, collaborators are domain
ports, and time and randomness are injected. So almost everything that matters can be tested on the
macOS host with no device, no network, no real model and no sleeps. The suite uses **Swift
Testing** only.

```bash
swift test   # 284 tests, 44 suites, ~0.7 s on an M-series Mac
```

## 9.1 What is covered

One test target (`SignalFlowKitTests`), organized by module:

| Area | Tests | What they pin down |
| --- | ---: | --- |
| DomainKit | 43 | Value-object validation, threshold/rule evaluation, health policy, alert lifecycle, insight statistics and grounded insight severity, use cases and the default recent-readings read against stub ports |
| DataKit | 42 | Store ingestion and alert raise/clear/archive, bounded history and the newest-readings read against a reference model, deterministic insights, simulated source ↔ use cases, remote data source, **concurrent ingestion, cancellation and lifecycle reentrancy**, failed and partial persistence writes retried without loss or duplicates, cancelled insights not recorded |
| Features | 25 | `@MainActor` model state transitions (loading/loaded/failed, a cancelled load never shown as empty), the dashboard verdict (never "all nominal" for an empty or degraded fleet), filtering, sorting, acknowledgement, chart thinning that keeps endpoints and extremes |
| NetworkingKit | 20 | Request building, status/decoding error mapping, retry/backoff (with an injected sleeper), DTO ↔ domain mapping |
| SimulationKit | 19 | Seed determinism, clock pacing, event generation, fleet composition, stream cancellation |
| Watch / WatchConnectivity / WatchWidgets | 41 | Snapshot building, codec round-trip, latest-wins store (a failed save isn't reported as stored), complication entries, relevance |
| PersistenceKit | 16 | Mapping round-trips, idempotent appends (also after a partial commit), a failed save leaving nothing pending, concurrently created stores, retention pruning, latest-per-series restore, end-to-end restoration through DataKit |
| Localization | 12 | Every catalog key has a Spanish translation; labels resolve per locale |
| LiveActivities / Widgets / AppIntents | 27 | Live Activity decision state machine, freshness and takeover after relaunch, widget timelines and summaries, intent results |
| CoreKit, IntelligenceKit, AppShell | 23 | RNG, Foundation Models fallback path, cancellation without fallback and grounded prompt, composition-root lifecycle (request ordering with an operation in flight, cancellation, overlapping starts, failed restore, failed bootstrap and retry, stop during a retry, degraded modes) |

## 9.2 Test doubles — plain types, no framework

There is no mocking library. Because every collaborator is a domain port, doubles are ordinary
`Sendable` structs and actors that return scripted data:

- `Stubs.swift` (DomainKit tests) and `FeatureTestSupport.swift` (feature tests) hold stub
  repositories and insight providers.
- `StubHTTPClient` (in NetworkingKit) is an `actor` that replays a scripted sequence of responses.
- Persistence tests use a real `PersistenceStore` over an **in-memory** SwiftData container, except
  the history-trimming tests, which use an on-disk store in a temporary directory.
- The Foundation Models provider takes its availability check as an injected closure, so the
  fallback path is tested on machines without Apple Intelligence.

Tests assert on outcomes, not on recorded calls.

## 9.3 Testing concurrent code deterministically

- **Bounded, instant simulations.** `ImmediateSimulationClock` plus `maxTicks` turn a live
  simulation into a finite, reproducible input. The same seed yields byte-identical telemetry.
- **Events instead of sleeps.** `startAndWaitUntilFirstIngestion()` resumes when the first reading
  is actually ingested, so tests wait for a fact, not for time.
- **Forcing interleavings.** The lifecycle-reentrancy test parks the ingestion loop inside its sink
  with a continuation-based latch, triggers `stop()`, issues `start()` while `stop()` is suspended,
  and only then releases the loop. The interleaving is deterministic, and the test fails against the
  previous implementation.
- **Ordering without scheduler luck.** The container tests hold the first start open inside its
  restore, issue the rest of a lifecycle sequence while it is in flight, and only then release it. The
  final state must match the last request, the catalog is restored once, and cancelling a request's
  task doesn't withdraw it. None of this depends on the order in which tasks get scheduled.
- **Real wall-clock time** is used only where pacing itself is under test (the accelerated clock and
  cancelling a slow stream), with generous bounds.

The lifecycle, persistence-failure, insights and watch suites have been run 100 times in a row
without a failure. The test process used to crash now and then (`SIGSEGV` inside Core Data's
`_generateTriggerSQL`) when several tests created their first `ModelContainer`s at the same time.
That was a race inside Core Data that every new store in a process is exposed to, not a test-only
problem, so container creation is now serialized where containers are made
([SwiftData §21.6](21-swiftdata-persistence.md#216-concurrency-model),
[#30](https://github.com/donatogomez/signal-flow/issues/30)). Because only a process's first
creations were exposed, no test inside the suite can detect it reliably; it is measured by running
`ContainerCreationStress` in fresh processes.

## 9.4 What is deliberately not tested here

- **Most platform-only code paths.** ActivityKit, the `WCSessionDelegate` bridges and watchOS
  WidgetKit views are behind `#if os(...)`/`#if canImport(...)`. They are compiled by the CI
  `xcodebuild` job, and their decision logic is extracted into platform-neutral types (e.g.
  `LiveActivityDecision`, `WatchComplicationEntry`) that *are* tested here. Only the ActivityKit
  service also runs on a simulator, in the app-hosted `SignalFlowTests` bundle
  ([Live Activities §26.8](26-live-activities.md#268-tests)); WatchConnectivity needs a paired watch
  and the widget views need snapshot tooling, so neither runs in CI.
- **UI rendering.** There are no snapshot or UI tests; presentation is tested at the model level.
- **The real on-device model.** Output is non-deterministic and availability-dependent; only the
  grounding inputs, the draft mapping and the fallback are tested.

## 9.5 Coverage philosophy

Confidence per test, not a coverage percentage: near-exhaustive on pure domain rules and mappers
(cheap, high-stakes), state-machine-complete on feature models, and scenario tests for the paths
where concurrency or persistence could lose or corrupt data.
