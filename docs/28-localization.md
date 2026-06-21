# 28. Localization (English + Spanish)

SignalFlow is fully localized in **English (source)** and **Spanish**, across every user-facing surface
— iPhone app, all five features, the watchOS companion, widgets, App Intents/Siri, and Live
Activities / Dynamic Island. It uses Apple's **modern** localization stack only: `String(localized:)`,
`LocalizedStringResource`, and **String Catalogs (`.xcstrings`)**. No `NSLocalizedString`, no legacy
`.strings`/`.stringsdict`, no third-party frameworks.

```
swift build ✅   swift test → 190 tests, 39 suites ✅   ./Scripts/check-boundaries.sh ✅
xcodebuild -scheme SignalFlow -sdk iphonesimulator … → ** BUILD SUCCEEDED ** ✅
~152 localized keys across 11 string catalogs, each with a complete Spanish translation.
```

## 28.1 Architecture: localization lives in the presentation layer

The non-negotiable rule (requirement #9): **`DomainKit` stays language-neutral.** Domain enums
(`DeviceStatus`, `AlertSeverity`, `ConnectivityStatus.State`, `InsightSeverity`, `AssetKind`,
`MetricKind`, …) carry **no** display strings beyond stable, neutral identifiers used for keys, sorting,
and identity. All user-facing text is produced in the layers above:

```
DomainKit            language-neutral enums + neutral `displayName` (keys/sorting/identity only)
   ▲
DesignSystemKit      the single home for localized domain labels:
                       DeviceStatus.label, AlertSeverity.label, ConnectivityStatus.State.label,
                       InsightSeverity.label, InsightSource.label, DeviceEvent.Kind.title,
                       AssetKind.localizedName, MetricKind.localizedName
   ▲
Features / Watch /   screen copy, titles, buttons, empty/error/loading states
Widgets / Intents /  (each module owns its own Localizable.xcstrings)
LiveActivities
```

### Why the domain stays neutral — a concrete reason

`MetricKind.displayName` and `AssetKind.displayName` remain in DomainKit and are **used for sorting and
SwiftUI identity** (e.g. `ForEach(id:)`, `sorted { $0.metric.displayName < … }`). If those were
localized, the sort order and view identity would *shift by language* — a subtle correctness bug. So
the neutral name stays in the domain, and DesignSystemKit adds a parallel `localizedName` used purely
for display. Same enum, two responsibilities, cleanly separated by layer.

### Domain labels are centralized

`DesignSystemKit/SemanticStyle.swift` is the one place that maps a domain concept to its localized
label, so "Critical" reads identically — and is translated once — everywhere it appears (dashboard,
fleet, alerts, widgets, Live Activity). Each label is `String(localized: "Key", bundle: .module)`, which
returns the already-translated string, so the hundreds of call sites that render `status.label` needed
**zero changes** to become localized.

## 28.2 String Catalogs (`.xcstrings`)

Every localizable target ships `Resources/Localizable.xcstrings` (a JSON String Catalog) and declares
`resources: [.process("Resources")]`; the package sets `defaultLocalization: "en"`. Code resolves keys
against the **module's** catalog:

```swift
// one tiny helper per module
func loc(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .module) }

// usage
.navigationTitle(loc("Dashboard"))
ContentUnavailableView(loc("No matching devices"), systemImage: "magnifyingglass")
```

- **English is the source language**: the key *is* the English text, so there's no separate `en` entry
  to maintain (except where plural rules differ).
- **Pluralization** uses the catalog's native plural variations, e.g. `"%lld active alerts"` →
  `one`/`other` in both languages (no `.stringsdict`).
- **`Bundle.module`** is essential: in a SwiftPM library the default bundle is the *app's*, so omitting
  it would silently fail to find the module's catalog.
### App Intents & App Extensions — the main-bundle edge case

App Intents metadata (intent titles, descriptions, shortcut short-titles, **and WidgetKit
`WidgetConfigurationIntent` descriptions**) is special: the metadata extractor (`appintentsmetadataprocessor`)
**requires the strings to resolve from the *main* bundle of the running target** — it rejects a
`LocalizedStringResource` bound to a SwiftPM module's `Bundle.module` (it fails the build with
*"AppIntents requires 'LocalizedStringResource' to use the main bundle"*), and it also rejects a
wrapper-function initializer (it must be a string literal or an inline `LocalizedStringResource(...)`).

So intent strings are written as **plain literals** in the module, and their translations live in a
`Localizable.xcstrings` placed in the **executable target's** bundle, not the module's:

| Intent kind | Lives in | Translations catalog | Resolved from |
| --- | --- | --- | --- |
| App's intents (Open Dashboard, Show Fleet Summary, …) | `AppIntentsKit` (literals) | `App/SignalFlow/Localizable.xcstrings` | the **app** target's main bundle |
| Widget config intent (`SignalFlowWidgetConfiguration.description`) | `WidgetSupportKit` (literal) | `App/SignalFlowWidgets/Localizable.xcstrings` | the **widget extension's** main bundle |

The widget case is the subtle one: the `SignalFlowWidgetConfiguration` intent is *defined* in the
`WidgetSupportKit` SwiftPM module, but its description is shown by the widget **extension**, whose main
bundle is `SignalFlowWidgets.appex` — so the catalog must be added to that extension target (its own
`Resources` build phase), not to the module. The module's `Bundle.module` catalog would never be
consulted for it. Everything else the widgets render (display names, labels, empty states) is ordinary
SwiftUI text and *does* localize from `WidgetSupportKit`'s module catalog as usual.

- Everything that is **not** App Intents metadata uses `String(localized:bundle:.module)` /
  `Text("…", bundle: .module)` against its own module catalog.

## 28.3 Supported languages

| Language | Code | Role |
| --- | --- | --- |
| English | `en` | Source / development language (the keys) |
| Spanish | `es` | Complete, natural translation of every key |

A test (`noMissingSpanish`) fails if any DesignSystemKit catalog key lacks a Spanish value, so the core
domain vocabulary can't silently regress to English.

## 28.4 How to add a future language (e.g. French)

1. Add the language to `defaultLocalization`? No — `defaultLocalization` stays `en`. Instead add `"fr"`
   entries to each `Resources/Localizable.xcstrings` (in Xcode: open the catalog, **+ → French**, and
   fill in the translations; Xcode round-trips the same JSON these files use).
2. Nothing in code changes — `loc(…)` / `String(localized:)` pick up the new language automatically.
3. Run `swift build` + `swift test` + the iOS `xcodebuild`; optionally extend the localization tests to
   assert the new language's values the same way the Spanish ones are asserted.

That's the payoff of centralizing domain labels in DesignSystemKit and keeping per-module catalogs: a
new language is **data**, not code.

## 28.5 Testing strategy (deterministic, not locale-dependent)

`Tests/SignalFlowKitTests/Localization/LocalizationTests.swift` is written to avoid brittle,
machine-locale-dependent assertions:

- **Mapping correctness** — that `DeviceStatus.critical.label` uses the `"Critical"` key — is asserted
  by comparing the public mapping to the resolver for the expected key **in the same locale**, so the
  equality holds regardless of the CI machine's region.
- **Translation correctness** — the Spanish values — is asserted by **decoding the shipped `.xcstrings`
  catalog** and checking the `es` entries. This is deterministic and toolchain-independent: Xcode
  compiles `.xcstrings` → `.lproj` for the real app (proven by the iOS `xcodebuild` build), whereas the
  SwiftPM CLI only *copies* the raw catalog, so asserting catalog **content** is the reliable way to
  test translations without depending on runtime `es` resolution being compiled in CI.
- A completeness test fails on any key missing a Spanish translation.

## 28.6 Known limitation

`loc(…)` resolves with `Locale.current` (the system / per-app language), which is the correct behavior
for shipping localization and honors the iOS per-app language setting. It does **not** react to a
SwiftUI `.environment(\.locale, …)` override at runtime (used in some previews / in-app language
switchers). Adopting that would mean threading `LocalizedStringResource` (rather than resolved `String`)
through every call site; it's intentionally out of scope here, where the app follows the system
language.
