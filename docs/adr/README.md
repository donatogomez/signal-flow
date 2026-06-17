# Architecture Decision Records

This directory captures the **significant, hard-to-reverse decisions** behind SignalFlow, using a
light [MADR](https://adr.github.io/madr/) format. ADRs are **immutable once accepted** — if a
decision is reversed, a new ADR supersedes the old one, preserving the reasoning history.

## Index

| ADR | Title | Status |
| --- | --- | --- |
| [0001](0001-clean-architecture-with-spm-modules.md) | Clean Architecture with SPM module boundaries | Accepted |
| [0002](0002-swiftdata-local-first.md) | SwiftData, local-first, repository-mediated (no `@Query` in views) | Accepted |
| [0003](0003-simulated-gateway-first-class-datasource.md) | Simulated gateway as a first-class data source | Accepted |
| [0004](0004-foundation-models-on-device.md) | On-device Foundation Models behind a Domain port | Accepted |

## Template

```markdown
# ADR-NNNN — <title>

- **Status:** Proposed | Accepted | Superseded by ADR-XXXX
- **Date:** YYYY-MM-DD
- **Deciders:** <who>

## Context
The forces at play: requirements, constraints, the problem being solved.

## Decision
The choice made, stated plainly.

## Consequences
### Positive
### Negative / costs
### Neutral

## Alternatives considered
For each: what it was, and why it was rejected.
```

Every ADR must include rejected alternatives **and** honest negative consequences. A decision with no
trade-offs is an assumption in disguise.
