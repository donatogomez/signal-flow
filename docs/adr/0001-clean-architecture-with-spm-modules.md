# ADR-0001 — Clean Architecture with SPM module boundaries

- **Status:** Accepted
- **Date:** 2026-06-17
- **Deciders:** Project author (Principal iOS Architect role)

## Context

SignalFlow must look like a system a team could maintain for years and that absorbs a substantial
roadmap (maps, conversational AI, multiplatform, multi-tenant) without rewrites. The recurring
failure mode in iOS codebases is **architectural erosion**: business rules leak into views, the data
layer leaks into the UI, and "MVVM" decays into 1,000-line view models that can't be tested without a
running backend. Folder-based "layering" doesn't prevent this because nothing stops an import.

Forces:
- Need testability of business logic with no device/network/model.
- Need the boundary to be *enforced*, not merely documented.
- Single maintainer (must not over-engineer into multi-repo ceremony).
- Strict concurrency requires clear ownership/isolation, which maps naturally onto layers.

## Decision

Adopt **Clean Architecture** with the Dependency Rule (source dependencies point inward toward a
pure Domain), and **enforce layer boundaries at the Swift Package Manager target level**: one app
target (composition root only) plus a local package `SignalFlowKit` whose layers/features are
**separate targets** with explicitly declared dependencies.

Key constraints encoded in the build graph:
- `DomainKit` depends on nothing.
- `Feature*` targets may depend on `DomainKit`, `ApplicationKit`, `DesignSystem` — **never** on
  `DataKit`/`IntelligenceKit`.
- Only the **App target** sees concrete implementations and wires them via DI.

## Consequences

### Positive
- The Dependency Rule becomes a **compile error**, not a code-review note. A view *cannot* import a
  repository implementation or a SwiftData model.
- Business logic (Domain) is pure and tested with zero infrastructure.
- Fast incremental builds; clear ownership; the roadmap slots into existing seams.
- Isolation boundaries (actors, `@MainActor`) align with module boundaries.

### Negative / costs
- More `Package.swift` wiring and more targets to navigate than a single app target.
- Cross-cutting changes touch several targets.
- Some boilerplate at the composition root (explicit DI wiring).

### Neutral
- Encourages many small protocols (ports); good for testing, more types overall.

## Alternatives considered

- **Folders in the app target (convention-only layering).** Rejected: boundaries unenforced; this is
  precisely the erosion failure mode we're guarding against.
- **MVVM without explicit use cases.** Rejected: business logic accretes in view models; poor
  testability; doesn't scale to the roadmap.
- **Multiple separate Swift packages / multi-repo.** Rejected for now: stronger isolation but heavy
  ceremony and slower navigation for a solo portfolio. The single multi-target package keeps the door
  open to split later (a target can graduate to its own package with no source changes).
- **A third-party architecture/DI framework.** Rejected: violates the zero-dependency constraint and
  isn't needed — initializer injection at the composition root suffices.
