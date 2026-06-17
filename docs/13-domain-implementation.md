# 13. Domain Implementation (`DomainKit`, as built)

This documents the **implemented** domain layer — the first real production code in SignalFlow — and
why its choices read as senior-level Swift 6. It supersedes the specifics in
[docs/05](05-domain-design.md) where they differ (deltas in
[§5.7](05-domain-design.md#57-implementation-reconciliation-as-built)).

`DomainKit` is **pure**: it imports only the Swift standard library and `Foundation` (for `Date`,
`UUID`, `Codable`). It depends on **no other SignalFlow target** — enforced by the SPM graph and the
boundary check. Everything is a `Sendable` value type or a `Sendable` protocol, so the whole layer is
ready to cross actor boundaries the moment the data layer introduces them.

```
swift build      # ✅   swift test → 36 tests, 7 suites ✅   ./Scripts/check-boundaries.sh ✅
```

## 13.1 What was implemented

| Group | Types |
| --- | --- |
| **Identifiers** | `Identifier<Scope>` + `AssetID`, `DeviceID`, `ReadingID`, `MetricID`, `AlertID`, `AlertRuleID`, `EventID` |
| **Value objects** | `MeasurementUnit`, `MetricKind`, `MeasuredValue`, `Threshold`, `TimeRange`, `AlertSeverity`, `AssetKind`, `DeviceStatus`, `Location`, `BatteryStatus`, `ConnectivityStatus` |
| **Entities** | `MetricDefinition`, `TelemetryReading`, `Device`, `Asset`, `Alert`, `AlertRule`, `DeviceEvent` |
| **Policy** | `DeviceHealthPolicy` (pure status derivation) |
| **Insight** | `TelemetryInsight` |
| **Errors** | `ValidationError`, `DomainError` |
| **Ports** | `AssetRepository`, `DeviceRepository`, `TelemetryRepository`, `AlertRepository`, `InsightsProviding` |
| **Use cases** | `FetchFleetOverviewUseCase`, `FetchDeviceDetailUseCase`, `FetchTelemetryHistoryUseCase`, `EvaluateAlertRulesUseCase`, `GenerateTelemetryInsightUseCase` (+ `FleetOverview`/`DeviceSummary`/`DeviceDetail` results) |

Folder layout mirrors these groups under `Sources/DomainKit/{Identifiers, ValueObjects, Entities,
Policies, Insights, Errors, Ports, UseCases, Support}`.

## 13.2 The decisions that signal senior Swift

### Type-safe identifiers with a phantom type
`Identifier<Scope>` wraps a `UUID`; `Scope` is a compile-time-only tag. `DeviceID` and `AssetID` are
therefore **distinct, non-interchangeable types** that cannot be mixed up at a call site, with zero
runtime cost and **one** id implementation instead of six copy-pasted structs.

```swift
public struct Identifier<Scope>: Sendable { public let rawValue: UUID }
public typealias DeviceID = Identifier<Device>   // Device used purely as a marker
```

### Make illegal states unrepresentable — validation in initializers
Value objects with invariants have **throwing initializers**, so an invalid value literally cannot
exist: `MeasuredValue` rejects non-finite magnitudes, `BatteryStatus` rejects percentages outside
`0…100`, `Threshold` requires at least one finite bound with `lower ≤ upper`, `TimeRange` requires
`start ≤ end`, `Location` requires on-Earth coordinates, and every named entity rejects empty names.
The validating initializer is **also invoked on `Codable` decode** for these value objects, so the
invariant survives serialization rather than being a constructor-only fiction.

### Units in the type system
`MeasuredValue` is `{ magnitude, unit }`, never a bare `Double`. `MetricDefinition.validate(_:)`
rejects a unit mismatch (`°C` where `%` is expected) and out-of-range values — killing the
"was that Celsius or Fahrenheit?" defect class at compile/validation time.

### Business judgement as a pure function
"Is this device OK?" lives in `DeviceHealthPolicy.status(connectivity:activeAlerts:)` — no I/O, no
clock, fully deterministic. It ignores acknowledged alerts and returns the worst unacknowledged
severity (or `offline`/`degraded` from connectivity). This single pure function is exhaustively
table-tested.

### Pure, deterministic alerting
`AlertRule.evaluate(_:on:at:alertID:)` is a pure function returning `Alert?`. Identity (`alertID`)
and time (`at`) are **injected**, so tests assert exact outputs with no randomness. `EvaluateAlertRulesUseCase`
exposes both an async wrapper (fetch + evaluate) and a **pure `static` core**, and injects the clock
and id generator as `@Sendable` closures — production passes real ones, tests pass fixed values.

### Strict-concurrency-ready by construction
Entities/value objects are `Sendable` value types; every port is a `Sendable` protocol; use cases
store dependencies as `any SomeRepository` existentials (Sendable because the protocols are). Nothing
uses `@unchecked Sendable`. `FetchDeviceDetailUseCase` already runs its two independent reads with
structured `async let`. The concurrency test suite *compiles* domain values across actor and
task-group boundaries — that it builds under Swift 6 is the assertion.

### Dependency Inversion via ports
Repositories and `InsightsProviding` are **protocols owned by the Domain**; no implementations live
here. Use cases depend on the abstractions, which is why the entire layer is testable with hand-written
stubs and needs no network, database, or model.

## 13.3 Testing (Swift Testing)

36 tests across 7 suites, all deterministic and infrastructure-free:

- **Value-object validation** — finite/percentage/coordinate/time-range/name rules, mostly
  **parameterized** (`@Test(arguments:)`).
- **Threshold & rule evaluation** — table-driven breach matrix; enabled/disabled and severity paths.
- **Entity invariants** — empty-name rejection, name trimming, **forward-only acknowledgement**
  (`#expect(throws:)`), and a **Codable round-trip** (`entity == decode(encode(entity))`).
- **Device health policy** — every status path including acknowledged-alerts-ignored.
- **Use cases** — async behavior through stub repositories, including `insufficientData` guarding.
- **Concurrency safety** — domain values across an `actor` and a `TaskGroup`.

Mocking uses **plain stub structs** (in the test target) rather than a framework — the ports are
small enough that this is simpler and less brittle. Reusable fakes will graduate to `TestingSupportKit`
when more than the domain layer needs them.

## 13.4 Deliberate deferrals

Recorded so they read as scope discipline, not gaps:
- **`AsyncStream` live ports** — introduced with `DataKit`/`CoreTelemetry`, where a real producer and
  back-pressure exist to model.
- **Staleness-based offline detection** (injected-`Clock` status policy) — lands when live time flows
  through the system; today status derives from explicit `ConnectivityStatus`.
- **Persistence/serialization shapes** — `@Model` types and DTOs live in the data layer; the Domain's
  `Codable` conformances exist for transport convenience and round-trip testing, not as a storage
  schema.

## 13.5 Why this is the right foundation

The data, intelligence, and feature layers all build on these abstractions. Because the Domain is
pure and its ports are stable, those layers can be implemented and swapped (live gateway vs.
simulator, on-device model vs. template fallback) without the business rules ever changing — which is
the entire "designed to evolve for years" thesis, now demonstrated in code rather than asserted in a
diagram.
