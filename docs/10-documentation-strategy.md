# 10. Documentation Strategy

For a portfolio whose *product is the engineering*, documentation is not overhead — it's the primary
interface to the reviewer. The strategy has three audiences and a layer for each.

| Audience | Layer | Artifact |
| --- | --- | --- |
| Reviewer / hiring manager (skims) | Narrative | `README.md` + this `docs/` suite |
| Engineer joining the project | Reference | DocC API docs, ADRs |
| Future-self / maintainer | Decisions | ADRs, diagram sources, CHANGELOG |

## 10.1 The `docs/` narrative suite

The numbered documents (`01-…` → `11-…`) tell the story in reading order: vision → requirements →
architecture → implementation strategy → value. Conventions:
- **Every non-trivial decision states its alternatives and why they were rejected** (see the tables
  throughout). A decision without a rejected alternative isn't a decision, it's an assumption.
- Documents **cross-link** rather than repeat (e.g. requirements link to the use case that satisfies
  them; concurrency links to the actor that owns a boundary).
- Diagrams are **Mermaid in-line**, so they render directly on GitHub with no build step and stay in
  version control as text (reviewable in diffs).

## 10.2 Architecture Decision Records (ADRs)

Significant, hard-to-reverse decisions are captured as **ADRs** in [`docs/adr/`](adr) using a light
**MADR** format. ADRs are immutable once accepted; a reversal is a *new* ADR that supersedes the old
one — so the repo preserves the *reasoning history*, which is exactly what a tech lead looks for.

Initial set:
- [ADR-0001 — Clean Architecture with SPM module boundaries](adr/0001-clean-architecture-with-spm-modules.md)
- [ADR-0002 — SwiftData, local-first, repository-mediated (no `@Query` in views)](adr/0002-swiftdata-local-first.md)
- [ADR-0003 — Simulated gateway as a first-class data source](adr/0003-simulated-gateway-first-class-datasource.md)
- [ADR-0004 — On-device Foundation Models behind a Domain port](adr/0004-foundation-models-on-device.md)

Each ADR answers: **Context** (forces at play) → **Decision** → **Consequences** (good and bad) →
**Alternatives considered**. The "bad consequences" section is deliberately honest — pretending a
decision has no downside is a junior tell.

## 10.3 DocC (API reference)

Each module ships a **DocC catalog**:
- Symbol documentation on all public types, with `- Parameters`, `- Returns`, `- Throws`.
- A landing **article per module** explaining its responsibility and where it sits in the layer map.
- **Concurrency contracts documented** — every port and actor states its isolation and `Sendable`
  expectations in prose, because that's the part future maintainers get wrong.
- A top-level **"Getting Started" tutorial** (`.tutorial`) walking through one vertical slice
  (telemetry frame → snapshot → screen).
- DocC builds in CI, so broken doc links fail the build.

## 10.4 Diagrams

- **Source-controlled, text-first** (Mermaid) so diagrams diff and never drift into a stale binary.
- A small set of canonical diagrams, each owning one concern: the **layer map**, the **read/write data
  flow** sequences, the **module dependency graph**, the **isolation map**, and the **domain class
  model**. They're embedded where relevant rather than dumped in one folder.
- `docs/diagrams/` holds any source for exported/static versions if a non-GitHub renderer is needed.

## 10.5 README structure (the 30-second test)

The README is optimized so a reviewer understands the project's *ambition and quality* in 30 seconds:
1. One-line positioning + the "why this exists" framing (it's a craft demonstration).
2. The table mapping *hard IoT problems → engineering techniques demonstrated* — this is the hook.
3. The architecture diagram + the single governing rule (dependencies point inward).
4. Technology choices table with **rationale per choice**.
5. A documentation map linking into `docs/`.

## 10.6 Living-documentation hygiene

- **ADRs are append-only**; superseded ones link forward.
- **CHANGELOG.md** (Keep a Changelog format) once implementation starts.
- **Doc tests where feasible** — code snippets in DocC compiled to prevent rot.
- **PR template** requires: which ADR(s) the change touches, and whether a new ADR is warranted.
- The `docs/` suite is versioned with the code, so the architecture description and the
  implementation never diverge — a reviewer can trust that what's written is what's built.
