# 20. Foundation Models Insights

SignalFlow's first real on-device AI feature: an **Insights** screen that uses Apple's Foundation
Models to turn recent telemetry into a plain-language summary, an anomaly hypothesis, and an
operational recommendation — with a deterministic fallback and a clear privacy story.

```
swift build ✅   swift test → 105 tests, 25 suites ✅   ./Scripts/check-boundaries.sh ✅
xcodebuild -scheme SignalFlow -sdk iphonesimulator … → ** BUILD SUCCEEDED ** ✅
```

## 20.1 Why Foundation Models

Numbers are easy for a machine and hard for a human at a glance. A grower looking at "humidity 78%,
min 61, max 81, average 70, rising over 240 readings" has to *interpret* it. Foundation Models turn
that into one honest sentence — on-device, with no backend, no API keys, and no data leaving the
phone. It's the right tool precisely where language beats a chart: explaining a multi-hour trend and
hypothesizing a cause.

The framework also fits the project's constraints exactly: it's **first-party** (zero third-party
deps), runs **offline**, and supports **guided generation**, so we get typed output without
`JSONSerialization` or fragile prompt-parsing.

## 20.2 What remains deterministic (the safety boundary)

AI **enhances** the insight system; it never touches safety logic. The hard line:

| Concern | Decided by | AI involvement |
| --- | --- | --- |
| Alert raised / cleared | `DomainKit.AlertRule.evaluate` (thresholds) | **none** |
| Device status (nominal/warning/critical/offline) | `DomainKit.DeviceHealthPolicy` | **none** |
| Trend direction, min/max/avg | `DomainKit.InsightStatistics` (pure Swift) | **none** |
| Active-alert / event **counts** | data layer (already evaluated) | **none** — passed in as facts |
| Wording of summary / anomaly / recommendation | Foundation model | phrasing only |
| Advisory insight "severity" (nominal/watch/concern) | `InsightContext.advisorySeverity` (alerts ⇒ concern, volatile ⇒ watch) | **none** — the model is told the level, it doesn't pick it |

The model is never asked "is this device in breach?" — thresholds are evaluated deterministically and
the model only ever sees the *resulting count*. `InsightSeverity` is deliberately a separate type from
`AlertSeverity`/`DeviceStatus` so a reviewer can see at a glance that it carries no safety weight.

## 20.3 Grounding strategy — "facts in Swift, words in the model"

Every number an insight is built from is computed in Swift and handed to the provider; the model
phrases, it never produces, values.

```mermaid
flowchart LR
    REPO["Repositories (DataKit)"] --> UC["GenerateDeviceInsightUseCase"]
    UC --> STATS["InsightStatistics.make()<br/>min · max · avg · latest · trend"]
    STATS --> CTX["InsightContext<br/>(grounded facts)"]
    CTX --> PORT["InsightsProviding port"]
    PORT -. deterministic .-> DET["DeterministicInsightsProvider"]
    PORT -. on-device AI .-> FM["FoundationModelsInsightProvider"]
    FM --> DRAFT["@Generable InsightDraft<br/>(guided generation)"]
    DRAFT --> OUT["DeviceInsight"]
    DET --> OUT
```

1. `GenerateDeviceInsightUseCase` (DomainKit) gathers grounded facts — device name, asset kind, the
   metric's `InsightStatistics`, and **counts** of active alerts and recent events — into an
   `InsightContext`.
2. The provider builds a constrained prompt from those facts and uses **guided generation**
   (`@Generable` / `@Guide`) so the model returns a typed `InsightDraft`, not free text. No
   `JSONSerialization`, no string parsing.
3. The instructions are explicit: *use only the provided facts, never invent numbers, frame anomalies
   as hypotheses, do not give safety verdicts.*
4. `severity` and `confidence` are computed in Swift — not asked of the model. Severity comes from
   `InsightContext.advisorySeverity`, the same rule the deterministic provider uses: the model never
   sees thresholds, so a severity it chose would be ungrounded (it once rendered an alert-free reefer
   cooling down as a red "concern"). `confidence` only measures data sufficiency (sample count / 50),
   so the Insights screen shows the reading count rather than a "confidence" percentage.

## 20.4 Availability & fallback strategy

Apple Intelligence isn't on every device or simulator. Degradation is graceful and layered:

- **Composition root decides** (`AppContainer.live()`): if `SystemLanguageModel.default.isAvailable`,
  it injects `FoundationModelsInsightProvider` (with the deterministic provider as its runtime
  fallback); otherwise it injects the deterministic provider directly. Both conform to the same
  `InsightsProviding` port, so nothing downstream changes.
- **Provider self-guards at call time**: even when wired, `FoundationModelsInsightProvider` re-checks
  availability and catches any model error, delegating to the deterministic fallback. So an
  availability change or a transient failure never breaks the feature. Failures are logged (category
  `insights`), never with the generated text.
- **Cancellation is not a failure.** A cancelled request (the Insights screen went away) throws
  `CancellationError` instead of falling back, whether the framework reports it as such or fails
  because the task was cancelled. `PersistingInsightsProvider` checks for cancellation once the
  result is back and then records nothing, and the Insights screen keeps its previous state rather
  than showing an empty feed. A first load cancelled after some cards appeared goes back to loading, so
  a partial feed is never left on screen as if it were complete. Cancellation is cooperative: one that arrives after that check doesn't
  undo the save, which then holds a valid insight nobody is waiting for.
- **The UI is honest**: every `DeviceInsight` carries a `source` (`.foundationModel` /
  `.deterministic`). The Insights screen shows a banner — *"Generated on-device by Apple Intelligence"*
  or *"On-device AI is unavailable — showing a deterministic insight instead."*

Availability is an **injectable closure** on the provider, so tests force the unavailable path
deterministically and **CI stays green on machines without Apple Intelligence** — no test ever invokes
the real model.

### Concurrent generations

The Insights feed starts one generation per device at once (10 in the simulated fleet). Whether that
should be capped was measured rather than assumed. `swift run -c release InsightsConcurrencyProbe`
([source](../Benchmarks/InsightsConcurrencyProbe/main.swift)) generates the feed's insights through
`FoundationModelsInsightProvider` with at most 1, 2, 3 or 10 in flight. The figures below are 3 rounds
each after a warm-up, on an Apple M1 Pro (macOS 26.3), from two runs of the probe. *First result* is
from the second run, which added it:

| In flight | Wall time (s) | First result (s) | Median call (s) | Model / fallback |
| ---: | ---: | ---: | ---: | --- |
| 1 | 37.4–40.5 | 2.7–3.0 | 3.4–4.1 | 10 / 0 |
| 2 | 35.7–40.7 | 3.4–4.2 | 7.3–9.0 | 10 / 0 |
| 3 | 36.9–45.0 | 3.1–5.2 | 10.7–13.5 | 10 / 0 |
| 10 | 34.7–40.2 | 3.6–5.6 | 20.9–24.8 | 10 / 0 |

The system model runs one request at a time, and the others wait. Starting all 10 neither speeds
the feed up nor makes any request fail or fall back. A cap would only spread the same ~37 s
differently. The fan-out stays uncapped.

### Progressive first load

The numbers also show that a feed shown only once every insight is back takes over half a minute to
appear on device. So the **first** load shows each observation as soon as it is generated: the first
card at 3.6–5.6 s instead of 35–40 s, then about one more every 3.5 s, so 10 screen updates for 10
devices instead of one.

- **Order.** Each card is inserted at its place in the attention order: severity, then confidence,
  then device name, then id. Cards already shown never swap with each other; a more urgent one can
  appear above them. The finished feed is the same as if it had appeared at once.
- **Ties.** The tiebreak by name matters, because confidence saturates at 1 once a series has 50
  samples, so most cards tie on severity and confidence. Before, ties came out in whichever order
  generations finished, which changed from one load to the next.
- **Refresh.** A refresh is not progressive. It keeps the current feed until the new one is complete,
  then replaces it, so old and new observations never mix and a device never shows twice.
- **What stays the same.** Cancellation and persistence are unchanged: each insight is still recorded
  by `PersistingInsightsProvider` when its own generation finishes, unless that request was
  cancelled. A cancelled first load goes back to loading (see above).
- **Memory.** The model holds at most one item per device in both modes.

With the deterministic provider, the whole feed is ready within milliseconds either way.

## 20.5 Privacy model

- **On-device only.** Insights run through Apple's on-device system model. There is no networking in
  the project and no external API is called — telemetry never leaves the device for AI processing.
- **No egress, no keys, no accounts.** The grounded facts are assembled and consumed locally; nothing
  is logged off-device.
- **Surfaced to the user.** The provenance banner states that telemetry stays on the device, so the
  privacy property is visible, not just implied.

## 20.6 Architecture & boundaries

```mermaid
flowchart TD
    subgraph App["Composition root (SignalFlowApp)"]
        AC["AppContainer — picks the provider"]
    end
    subgraph Feature["FeatureInsights — DomainKit + DesignSystemKit only"]
        IM["InsightsModel"] --> IS["InsightsScreen"]
    end
    subgraph Domain["DomainKit"]
        UC["GenerateDeviceInsightUseCase"]
        PORT["InsightsProviding"]
    end
    DET["DataKit.DeterministicInsightsProvider"]
    FM["IntelligenceKit.FoundationModelsInsightProvider<br/>(imports FoundationModels)"]

    AC -->|injects port| IM
    IM --> UC --> PORT
    DET -. conforms .-> PORT
    FM -. conforms .-> PORT
    AC --> DET
    AC --> FM
    classDef domain fill:#1d3b2a,stroke:#2ecc71,color:#fff;
    class UC,PORT domain;
```

- **`FeatureInsights`** depends only on `DomainKit` + `DesignSystemKit`. It never imports
  `FoundationModels`, `IntelligenceKit`, or `DataKit` — enforced by `check-boundaries.sh` (Rule 2).
- **`IntelligenceKit`** is the *only* target that imports `FoundationModels`; it depends on `DomainKit`
  alone (Rule 5). The deterministic provider stays in `DataKit`.
- The `InsightsProviding` **port** is the seam: deterministic and AI providers are interchangeable
  behind it, and the composition root chooses.

## 20.7 Why this matters for iOS design

| Decision | Signal |
| --- | --- |
| AI phrases facts; Swift computes them | Understands LLM grounding; refuses to let a model invent operational numbers |
| Safety logic stays deterministic; advisory severity is a separate type | Knows *where not to use AI* — the strongest signal of all |
| Guided generation (`@Generable`) instead of JSON parsing | Uses the framework's type-safe path; no fragile string handling |
| One `InsightsProviding` port, provider chosen at the composition root | Dependency Inversion that makes AI swappable and testable |
| `FoundationModels` isolated to one target, enforced by CI | Clean Architecture that actually holds |
| Injectable availability → deterministic tests, green CI without Apple Intelligence | Testable AI integration, not a demo that only runs on the author's device |
| Provenance + on-device privacy surfaced in the UI | Apple platform privacy principles applied and made visible |

## 20.8 Using it

```swift
// Composition root picks the provider based on availability:
let deterministic = DeterministicInsightsProvider()
let insights: any InsightsProviding = FoundationModelsInsightProvider.systemModelAvailable
    ? FoundationModelsInsightProvider(fallback: deterministic)
    : deterministic

// Features only ever see the port:
let insight = try await GenerateDeviceInsightUseCase(
    devices: devices, assets: assets, telemetry: telemetry,
    alerts: alerts, events: events, insights: insights
)(deviceID: deviceID, metric: .temperature, range: range)
// insight.source tells the UI whether the model or the fallback produced it.
```

In the app, the **Insights** tab lets you pick a device and metric and shows the result with its
provenance banner.
