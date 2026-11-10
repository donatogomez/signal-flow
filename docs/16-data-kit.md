# 16. DataKit

`DataKit` is the layer that **turns a telemetry source into the `DomainKit` repository ports**. Today
that source is `SimulationKit`; tomorrow it will be a real gateway and a SwiftData store. Either way,
features and use cases see only the abstract ports — they never learn where the data came from.

```
swift build ✅   swift test → 82 tests, 18 suites ✅   ./Scripts/check-boundaries.sh ✅
```

It depends only on **`DomainKit`** (the types it returns) and **`SimulationKit`** (the source it
adapts). No SwiftData, no networking, no Foundation Models, no UI.

## 16.1 Responsibility

DataKit answers one question: *how does raw telemetry become the domain snapshots, history, and
alerts that the use cases query?* Concretely it:

- **owns an in-memory store** (`InMemoryTelemetryStore`) — the data-access core;
- **ingests** SimulationKit's `AsyncStream<DeviceTelemetry>` into that store;
- **reconstructs domain entities** (`Device`, `Asset`, …) from accumulated telemetry;
- **manages alert lifecycle** using `DomainKit`'s rule logic;
- **exposes `DomainKit` ports** (`AssetRepository`, `DeviceRepository`, `TelemetryRepository`,
  `AlertRepository`, `InsightsProviding`) as the only public consumption surface.

## 16.2 Why it adapts SimulationKit into the DomainKit ports

The whole architecture rests on the Dependency Rule: features depend on **abstractions** (the ports),
never on a concrete source. DataKit is where the inversion is realized. SimulationKit produces a
stream of `DeviceTelemetry`; the use cases want `try await telemetry.latestReadings(forDevice:)`.
DataKit is the adapter between the two — so:

- the **Dashboard, Charts, Alerts, and Insights** features can be built *now*, entirely on realistic
  data, before any persistence or backend exists;
- when the live gateway and SwiftData arrive, **only DataKit changes** — the ports, use cases, and
  features are untouched. That "swap the source, keep everything else" property is the payoff.

A test (`consumableThroughDomainPortsOnly`) drives the whole layer through a function that names only
`DomainKit` types, proving no SimulationKit concept leaks into the consumption path.

```mermaid
flowchart LR
    SIM["SimulationKit\nAsyncStream&lt;DeviceTelemetry&gt;"] --> ADP[SimulationTelemetryAdapter ‹actor›]
    ADP --> STORE[(InMemoryTelemetryStore ‹actor›)]
    STORE --> REPOS["Store*Repository\n(DomainKit ports)"]
    REPOS --> UC["DomainKit use cases\n(Fleet · Detail · History · Insight)"]
    classDef domain fill:#1d3b2a,stroke:#2ecc71,color:#fff;
    class REPOS,UC domain;
```

## 16.3 Actor-based store design

`InMemoryTelemetryStore` is an `actor`. **All** mutable state lives inside it — the device catalog,
the latest snapshot per metric, bounded history, events, connectivity, and active alerts — so
concurrent ingestion and reads are race-free by construction, with no lock anywhere.

- The store's record types are **private** and never cross the boundary; queries return only
  `DomainKit` value types (`Asset`, `Device`, `TelemetryReading`, `Alert`).
- A `Device` snapshot is **reconstructed on demand** from accumulated telemetry: metrics from the
  readings seen, battery from the latest `batteryLevel`, connectivity from reading arrival and
  connect/disconnect events, location from the latest position. Status itself is *not* stored — the
  domain `DeviceHealthPolicy` derives it in the use case.
- The `Store*Repository` types are **thin, `Sendable` adapters** that forward port calls to the
  actor. Keeping them logic-free makes the store the single source of truth and keeps the ports
  trivially swappable.

### Alert lifecycle without duplicating domain rules
On each reading the store calls `DomainKit`'s `AlertRule.evaluate` for the **breach decision**, and
only manages the *lifecycle* around it: raise an alert once per breach, dedupe repeated breaches, and
clear it on recovery. Thresholds (which values warrant an alert) are configuration — `DataKit` picks
sensible defaults per asset kind in `DefaultAlertRules`, built from `DomainKit`'s `AlertRule`/
`Threshold`. No rule logic is reimplemented.

## 16.4 AsyncStream ingestion

`SimulationTelemetryAdapter` is the one component that touches the simulation stream. It offers two
ingestion modes:

- **Structured** (`ingestAll`) — `for await item in await engine.makeFleetStream() { await store.ingest(item) }`,
  running under the caller's task. With a bounded clock (`maxTicks`) it completes deterministically,
  which is exactly what tests want.
- **Managed** (`start`/`stop`) — owns a single background `Task`, stored on the actor so it can be
  cancelled. The task closure captures only the two actors (engine, store), **not `self`**, so there
  is no retain cycle.

The `SimulatedDataSource` façade wires the store, fleet, adapter, and repositories together and
exposes only domain ports plus `bootstrap()` / `ingestAll()` / `start()` / `stop()`. It's built via
`deterministic(seed:maxTicks:)` or `live(seed:timeScale:)` factories, so **no caller ever names a
SimulationKit type** — the bridge is fully encapsulated.

## 16.5 Startup & cancellation strategy

Both ends of the background ingestion lifecycle are made **observable and structural**, so tests can
prove behavior with no sleeps and no timing tolerances.

**Startup is observable.** `start()` only *schedules* the loop's `Task` and returns immediately — it
does **not** guarantee any item has been ingested yet. For when that guarantee is needed, the adapter
exposes `startAndWaitUntilFirstIngestion()`, which returns only once the loop has ingested its first
*reading*. It's backed by a one-shot `IngestionReadiness` actor: the loop calls `fire()` after the
first reading lands, and the waiter is resumed via a `CheckedContinuation` — no polling, no sleeps, no
racing the scheduler. (A loop that ends before producing a reading still fires readiness on exit, so a
waiter can never hang.)

**Cancellation is structural, with no task leaks, and `stop()` awaits the loop's completion** rather
than just requesting cancellation:

- `stop()` cancels the stored task and then `await task.value`. Cancelling ends the `for await`
  (AsyncStream is cancellation-aware), which terminates the underlying fleet stream through its
  `onTermination`, cancelling the producing task group all the way down. Because `stop()` awaits the
  loop to finish, **once `stop()` returns no telemetry from the cancelled session can still mutate the
  store.**
- The ingestion loop also checks `Task.isCancelled` **before** each `store.ingest`, so it stops at the
  first safe point rather than draining buffered items.
- `deinit` cancels the task as a backstop, so an abandoned adapter never leaves a stream running.

The test (`stopHaltsIngestion`) is therefore fully deterministic: it
`startAndWaitUntilFirstIngestion()` (proving ingestion is live, `count > 0`), `stop()`s, then reads the
count twice and asserts it's unchanged — because the loop is provably finished, a second read is
identical without waiting.

> **Two CI races we fixed, both structurally.**
> 1. **Writes after stop.** An earlier `stop()` only *requested* cancellation and returned; the
>    unstructured `Task` kept draining for one more accelerated tick on a loaded runner. Making
>    `stop()` await `task.value` made "stopped" a guarantee, not a hope.
> 2. **No writes *before* stop.** `start()` returns before the loop has run, so on a slow CI scheduler
>    the test could `stop()` before a single reading was ingested and see `count == 0`. The fix is a
>    deterministic readiness signal (`startAndWaitUntilFirstIngestion()`), not a longer sleep.
>
> The principle in both: replace "wait a bit and hope" with an explicit synchronization point. No
> sleeps, no tolerances — the invariants hold by construction.

## 16.6 Why persistence and networking are intentionally deferred

DataKit is deliberately **source- and storage-agnostic at this stage**. Persistence (SwiftData) and
networking (a live gateway) are separate concerns that each deserve their own focused step:

- The **in-memory store** already exercises the full shape of the data layer — ingestion, snapshot
  reconstruction, history, alert lifecycle, concurrency — so features can be built on it immediately.
  Adding SwiftData later is an *implementation* of the same store responsibilities behind the same
  ports, not a redesign.
- The **simulated gateway** stands in for networking as a first-class source (see ADR-0003), so the
  app runs end-to-end with zero infrastructure today. A `WebSocketGateway` later conforms to the same
  `TelemetryGateway` seam.

Deferring them keeps this change reviewable and the boundaries honest: each future layer slots into a
seam that already exists rather than forcing a rewrite.

## 16.7 Why this matters for iOS architecture

| Decision | Signal |
| --- | --- |
| Adapter realizes Dependency Inversion: source → ports | Understands that the value of Clean Architecture is *swappability*, demonstrated by a test that consumes the layer through domain ports alone |
| All mutable state in one actor; private records; `Sendable` value types out | Fluency with the Swift 6 isolation model — no locks, no `@unchecked` |
| Thin repositories over a store core (DAO + adapters) | Separation of data access from port conformance; one source of truth |
| Domain rules reused for breach decisions; DataKit owns only lifecycle | Disciplined layering — no business-logic duplication |
| Structured + managed ingestion, leak-free cancellation, retain-cycle-free task | Correct, production-grade `AsyncSequence` lifecycle management |
| Persistence/networking deferred behind existing seams | Judgment about sequencing and scope, with a credible path to evolve |

## 16.8 Using it

```swift
// Deterministic (tests / previews):
let source = SimulatedDataSource.deterministic(seed: 42, maxTicks: 120)
try await source.bootstrap()
await source.ingestAll()
let fleet = try await FetchFleetOverviewUseCase(
    assets: source.assets, devices: source.devices, alerts: source.alerts
)()

// Live (running app): real-time ingestion at 600× speed.
let live = SimulatedDataSource.live(seed: 42, timeScale: 600)
try await live.bootstrap()
await live.start()      // … await live.stop() to halt
```

## 16.9 Telemetry history: mutating in place

Each `(device, metric)` series in `InMemoryTelemetryStore` keeps its newest `historyLimit` readings
(10,000 by default) in a plain `Array`, oldest first.

**What was slow.** Ingestion used to copy the device record out of the `devices` dictionary, copy
the series out of the record, append, trim, and write both back. While the local copies existed the
series buffer had two owners, so the append had to copy it whole first. Every reading therefore
allocated and copied the entire series: about 768 KB per reading at 10,000 readings, with a cost
that grew linearly with history length even when nothing was evicted.

**The fix.** `ingest` now looks up the record once and mutates it through
`devices.values[index]`, and the series is appended and trimmed through
`record.history[metric, default: []]`. Both accessors yield the stored value in place, so the
buffer keeps a single owner and is never copied. Ordering, retention, device/metric isolation and
the public API are unchanged. `TelemetryHistoryTests` checks the store against a keep-the-newest
reference model (empty, first reading, below, at and over capacity, interleaved devices and
metrics, range queries after eviction) and under concurrent ingestion. The same tests pass against
the previous implementation.

**How it was measured.** `swift run -c release TelemetryStoreBenchmark`
([source](../Benchmarks/TelemetryStoreBenchmark/main.swift)). One series is prefilled to the
history limit, then 2,000 readings are ingested, each evicting the oldest. Each figure is the median
of 7 runs after 1 warm-up, and the table takes the median of 5 such invocations per build on an
Apple M1 Pro (macOS 26.3, Swift 6.3.3). Allocations are counted through libmalloc's
`malloc_logger` hook and include about one small allocation per call that comes from the
benchmark's own cross-actor call.

| History | Before, per reading | After, per reading | Improvement | Allocated per reading (before → after) |
| ---: | ---: | ---: | ---: | ---: |
| 100 | 3.30 µs | 0.89 µs | 73.2% | 10.3 KB → 0.2 KB |
| 1,000 | 22.71 µs | 1.76 µs | 92.3% | 96.3 KB → 0.2 KB |
| 2,000 | 44.17 µs | 3.68 µs | 91.7% | 192.3 KB → 0.2 KB |
| 5,000 | 108.55 µs | 8.15 µs | 92.5% | 384.3 KB → 0.2 KB |
| 10,000 | 217.93 µs | 16.22 µs | 92.6% | 768.3 KB → 0.2 KB |

Appending without eviction went from linear (23–218 µs) to a flat 0.65 µs, which is amortized
O(1). Reading a full 10,000-reading series (~1.04 ms) and the newest 10% (~0.36 ms) are unchanged
within 1–2%. Peak memory footprint is unchanged too (~12 MB for the whole benchmark), because the
old copies were freed straight away. The cost was allocation churn and copying, not retained
memory.

**What remains, and why it stays.** At capacity, ingestion still grows with history length because
`removeFirst` shifts the remaining elements, roughly a 720 KB `memmove` at 10,000 readings of 72
bytes each. Two alternatives were considered:

- *Trimming in batches* (letting a series grow to `historyLimit + historyLimit / 8`, then cutting it
  back) was prototyped and measured flat at ~1.07 µs per reading. It would make the stored array
  longer than the logical history, so every reader (`readings`, `ingestedReadingCount`, any future
  query) would have to clamp to the newest `historyLimit`.
- *A ring buffer* would remove the shift too. It would mean a custom collection with its own index
  arithmetic, conversions and tests.

The live app produces about 300 readings per second (10 devices × 3 metrics, one tick every 0.1 s).
At the 10,000-reading limit that is about 5 ms of work per second now, against about 65 ms before.
The remaining saving (~0.5% of one core) doesn't justify either structure today. Batched trimming
is the next step if the limit or the ingest rate grows substantially. `readings(in:)` still filters
and sorts the whole series on every query, because arrival order isn't guaranteed to be time order
for every source.

## 16.10 Periodic history reads

At about 300 readings per second, every series reaches the 10,000-reading limit about 30 seconds
after launch, so a full series is the normal case for its two periodic readers.

**What was slow.**

- *Watch snapshot* (every 5 s): the app read the whole history of two metrics for each of the 10 devices
  through `readings(in:)` and sorted it again, then `WatchSnapshotBuilder` kept the newest 8 of each.
- *Device detail* (every 3 s): the model read the whole history of three metrics and handed all of
  it to Swift Charts, which drew 30,000 Catmull-Rom line points for one screen a few hundred points
  wide. The mapping to `TrendPoint` and the chart work ran on the main actor.

**The fix.**

- `TelemetryRepository` gains `recentReadings(forDevice:metric:limit:)`: the newest `limit` readings
  by time, oldest-first. A protocol extension implements it for every conformer by reading the whole
  history, so the remote and stub repositories are unchanged.
- `InMemoryTelemetryStore` answers it in one backward pass over the series without copying it. It
  keeps a buffer of `limit` readings, so readings that arrive in time order cost one comparison each.
  Out-of-order arrival and ties are handled, and give the same result as sorting the series and
  taking its suffix.
- The watch snapshot asks for `WatchSnapshotBuilder.trendPointCount` readings.
- Device detail thins each series to at most 242 points before mapping it (`ChartDownsampling`). It
  keeps the first and last reading, and the lowest and highest of each of 120 equal-count runs in
  between, in their original order. The chart therefore spans the same time, has the same y-range,
  shows every spike, and ends on the same latest point. The hero's change caption reads the same
  first and last values. A shorter series is left unchanged.

**Tests.** The store's recent read is checked against the sorted history for out-of-order arrival,
a tie at the cut, a limit of zero, a limit above the count, a missing metric and an unknown device.
The default implementation is checked over an unordered stub. The detail model is checked at 2, 242,
243 and 10,000 readings: the point count, the endpoints, the extremes and the time order.

**How it was measured.** `swift run -c release HistoryReadBenchmark`
([source](../Benchmarks/HistoryReadBenchmark/main.swift)). The setup is 10 devices × 3 metrics,
one reading per simulated minute. The *watch read* is the 20 series the snapshot reads, and the
*detail refresh* is one `DeviceDetailModel.refresh()`. Each figure is the median of 15 runs after 2
warm-ups, and the table takes the median of 3 invocations per build on an Apple M1 Pro (macOS 26.3,
Swift 6.3.3). "Before" is `main` at `347a168` running the same harness without the new call.

| Readings per series | Watch read, before → after | Detail refresh, before → after | Chart points, before → after |
| ---: | ---: | ---: | ---: |
| 100 | 440 µs → 62 µs | 212 µs → 225 µs | 300 → 300 |
| 1,000 | 3.56 ms → 0.23 ms | 1.09 ms → 0.87 ms | 3,000 → 726 |
| 10,000 | 34.6 ms → 1.83 ms | 9.12 ms → 5.95 ms | 30,000 → 726 |

At 100 readings, the detail refresh takes the same path as before, and the difference is noise.

**What remains.**

- The detail refresh still reads the whole series on the store actor. That accounts for most of the
  5.95 ms, and it runs off the main actor.
- A binary search over the series when it is already in time order brought the refresh to about
  3.0 ms. It was left out: it needs an ordering check on every query plus a search, and it would only
  save store-actor time.
- Charts rendering itself was not measured, since there is no on-device baseline (see
  [§11.2](11-portfolio-value.md#112-known-limitations)). What can be stated is the 41× drop in
  points per screen.
