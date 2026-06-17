# ADR-0002 — SwiftData, local-first, repository-mediated (no `@Query` in views)

- **Status:** Accepted
- **Date:** 2026-06-17
- **Deciders:** Project author

## Context

SignalFlow must be fully usable offline (FR-8), persist a high-frequency telemetry history, and keep
the UI responsive while a `ModelActor` ingests bursts off the main thread. SwiftUI offers `@Query`,
which binds a view directly to SwiftData and is wonderfully concise — but it couples the view to the
persistence engine and to `@Model` types, which conflicts with the enforced Dependency Rule from
[ADR-0001](0001-clean-architecture-with-spm-modules.md).

Forces:
- Want first-party persistence that integrates with Observation (SwiftData).
- Want the UI to read **domain entities**, not persistence models.
- Want features testable with fakes, and the persistence engine swappable in principle.
- `@Model` types are not freely `Sendable`; they must not cross isolation boundaries.

## Decision

Use **SwiftData** as the local store, treat the **local store as the UI's source of truth**
(local-first), and access it **only through Domain repository ports** — **not** via `@Query` in
views. A dedicated `@ModelActor` (`PersistenceStore`) owns all reads/writes off the main actor and
**maps `@Model` records to `Sendable` domain entities at the boundary**, so SwiftData objects never
leave the data layer.

User-authored changes are optimistic and durable via an **outbox**; telemetry is append-only with
sequence-based ordering/dedup (see [Data Layer](../06-data-layer.md)).

## Consequences

### Positive
- Dependency Rule preserved even on the hot path: features depend on `TelemetryRepository`, not
  SwiftData.
- Features are testable with `FakeTelemetryRepository`; previews run with no store.
- `@Model` non-`Sendable` problems vanish — records are mapped to value types inside the actor.
- Off-main ingestion keeps the UI smooth under telemetry bursts.
- The store could be re-implemented (e.g. raw SQLite) without touching features.

### Negative / costs
- We forgo `@Query`'s conciseness and write mapping + repository plumbing by hand.
- A mapping layer is extra code and a place bugs can hide (mitigated by round-trip property tests).
- We don't get SwiftData's automatic view-level change animations for free; the repository streams
  drive updates instead.

### Neutral
- Requires a `VersionedSchema`/`SchemaMigrationPlan` from v1 (adopted deliberately for "evolve for
  years").

## Alternatives considered

- **`@Query` directly in views.** Rejected: breaks the Dependency Rule, couples UI to persistence,
  hurts testability — despite being the most concise option.
- **Core Data.** Rejected: more boilerplate, weaker Observation integration, and SwiftData is the
  modern first-party choice this portfolio aims to demonstrate.
- **Remote-as-source-of-truth (no local-first).** Rejected: violates the offline requirement and the
  field-technician persona; produces spinner-heavy UX.
- **A third-party database (GRDB, Realm).** Rejected: violates the zero-dependency constraint; not
  needed.
