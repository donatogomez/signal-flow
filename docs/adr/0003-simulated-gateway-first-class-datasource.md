# ADR-0003 — Simulated gateway as a first-class data source

- **Status:** Accepted
- **Date:** 2026-06-17
- **Deciders:** Project author

## Context

SignalFlow is a portfolio project with no production backend, yet it must demonstrate live streaming,
charts, alerting, and AI insight convincingly. A reviewer's impression is dramatically better if they
can **clone and Run** and immediately see a live, animated, AI-annotated fleet — versus reading a
README and imagining it. We also need **deterministic** data to test the streaming/sync/alerting
paths without flakiness.

Forces:
- Zero-infrastructure demo (no backend, no API keys, no account).
- Deterministic, reproducible scenarios for tests (including injected anomalies).
- Must not become a special-case that the rest of the app has to know about.

## Decision

Define a single `TelemetryGateway` protocol and ship **two production implementations behind it**: a
real `WebSocketGateway` and a **`SimulatedGateway` treated as a first-class data source** (not a test
stub). The simulator generates physically plausible telemetry (diurnal curves, battery decay,
door/connectivity events, injectable anomalies) using an **injected `Clock` and seeded RNG**, so the
same seed reproduces the same scenario exactly. The active gateway is selectable in Settings (FR-15/
FR-16) and is **indistinguishable** to the repository, use cases, UI, and AI from a live broker.

## Consequences

### Positive
- **Clone → Run → live AI-annotated fleet**, no setup. Strong first-run impression for reviewers.
- The same simulator doubles as a **deterministic integration-test fixture** (seed `42` ⇒ identical
  data), which is what makes concurrency tests reproducible.
- Demonstrates the value of the gateway abstraction: swapping simulated ↔ live is a one-line DI
  change; the production path (`WebSocketGateway`) is real, just not wired by default.
- Lets us showcase rare states on demand (excursions, dropouts) for screenshots/demos.

### Negative / costs
- Building a *believable* simulator is real work (signal models, event scheduling).
- Risk of the simulator and the live gateway drifting in behavior; mitigated by both conforming to
  the same protocol and a shared conformance test suite.
- A naive reviewer might mistake "simulated" for "fake/incomplete" — addressed explicitly in the
  README and [Portfolio Value §11.4](../11-portfolio-value.md#114-honest-weaknesses-and-why-naming-them-is-itself-a-signal).

### Neutral
- Requires `Clock`/RNG injection throughout the telemetry path (also wanted for testing anyway).

## Alternatives considered

- **Bundled static fixture data (JSON replay).** Rejected: not live, no continuous streaming or
  back-pressure to demonstrate, and poor for showcasing real-time UI.
- **A real hosted backend / public broker.** Rejected: introduces infrastructure, keys, cost, and a
  network dependency that breaks the zero-setup goal and offline story.
- **Simulator as a test-only target.** Rejected: it's too valuable for the demo experience to hide in
  tests; promoting it to a real data source is the differentiating decision.
