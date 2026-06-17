# ADR-0004 — On-device Foundation Models behind a Domain port

- **Status:** Accepted
- **Date:** 2026-06-17
- **Deciders:** Project author

## Context

SignalFlow turns numeric telemetry into language: trend summaries, anomaly explanations, and a fleet
digest (FR-12–14). We need this to be **useful, private, offline-capable, testable, and
architecturally contained**, and to demonstrate current AI literacy without devolving into a gimmick.
LLMs also famously invent numbers — unacceptable for a system whose users make operational decisions.

Forces:
- Privacy/regulatory expectations of logistics/industrial customers (no data egress).
- Must work offline (field personas) and with zero backend/keys.
- Must be testable and previewable without AI hardware or nondeterministic output.
- Must not let a model fabricate telemetry values.
- Must degrade gracefully where the model is unavailable.

## Decision

Integrate Apple's **on-device Foundation Models** via a Domain port, `InsightService`, defined in
`DomainKit` using **plain value types only**. The single concrete implementation,
`OnDeviceInsightService`, lives in `IntelligenceKit` (the only target importing `FoundationModels`)
and is an **actor** owning one `LanguageModelSession`. Outputs use **`@Generable` guided generation**
for typed, validated structures. **All statistics are computed in pure Swift and passed in**; the
model only phrases them ("facts in Swift, words in the model"). If the model is unavailable, the
service returns a **deterministic template-based summary** built from the same statistics.

## Consequences

### Positive
- No inference cost, no API keys, no data egress; works offline — a genuine product advantage, not
  just a tech demo.
- The Domain and UI never import `FoundationModels`; tests/previews inject `ScriptedInsightService`,
  so the whole app builds and runs without AI hardware or model availability.
- Guided generation removes fragile string parsing; grounding + "hypothesis" framing curbs
  hallucination; template fallback prevents the feature from vanishing on unsupported devices.
- The actor serializes a stateful session, avoiding concurrent-use corruption.

### Negative / costs
- On-device models are smaller/less capable than frontier cloud models; summary quality is bounded
  and device-dependent.
- Foundation Models availability varies by device/OS, requiring availability handling and a fallback
  path (extra code).
- Inference latency/battery cost must be managed (cancellation on screen exit, optional streaming).

### Neutral
- Establishes a seam where a cloud model *could* be added later behind the same port — but that would
  reintroduce egress/cost and is deliberately not the default.

## Alternatives considered

- **A cloud LLM API (OpenAI/Anthropic/etc.).** Rejected: data egress, per-token cost, API-key setup,
  and a hard network dependency — all contrary to the privacy/offline/zero-setup goals. (The port
  keeps this option open if ever justified.)
- **No AI; rules/templates only.** Rejected: misses a current, differentiating capability and the
  multi-hour-trend narration that genuinely beats raw numbers. (Templates are retained as the
  *fallback*, not the primary.)
- **Letting the model compute/aggregate the numbers.** Rejected outright: unacceptable hallucination
  risk for operational data. Statistics stay in deterministic Domain code.
- **Putting `FoundationModels` types in the Domain.** Rejected: would couple the core to a framework
  and break testability; the port uses plain value types instead.
