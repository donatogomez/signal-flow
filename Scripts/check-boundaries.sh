#!/usr/bin/env bash
#
# check-boundaries.sh — enforce SignalFlow's Clean Architecture import rules.
#
# Why this exists: SwiftPM scopes each target's *declared* dependencies, so on a clean/isolated
# build an undeclared `import` fails with "no such module". But on a full `swift build` SwiftPM
# emits every module into one shared search directory, so an accidental undeclared import can slip
# through locally. This script closes that gap in CI by statically rejecting forbidden imports.
# See docs/12-scaffolding.md.
#
# Exit non-zero on the first violation.

set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
report() { echo "❌ boundary violation: $1"; fail=1; }

# Rule 1 — DomainKit is pure: it must not import any other first-party module.
if grep -REn '^\s*import\s+(CoreKit|DesignSystemKit|DataKit|PersistenceKit|NetworkingKit|SimulationKit|Feature[A-Za-z]+|SignalFlowApp|TestingSupportKit)\b' \
        Sources/DomainKit 2>/dev/null; then
    report "DomainKit must not depend on any other SignalFlow target"
fi

# Rule 2 — Feature modules must not reach into the data/infrastructure layer, nor into the app's
# glance/integration surfaces (widgets, App Intents, Live Activities) — features stay independent.
for feature in Sources/Feature*; do
    [ -d "$feature" ] || continue
    if grep -REn '^\s*import\s+(DataKit|PersistenceKit|NetworkingKit|SimulationKit|IntelligenceKit|FoundationModels|SwiftData|SnapshotKit|WidgetSupportKit|AppIntentsKit|LiveActivityKit|ActivityKit|WatchConnectivity|WatchConnectivityKit)\b' "$feature" 2>/dev/null; then
        report "$(basename "$feature") must not import a concrete data/intelligence module or a glance surface"
    fi
done

# Rule 3 — SimulationKit is a leaf data source: it may import only DomainKit and CoreKit.
if grep -REn '^\s*import\s+(DataKit|PersistenceKit|NetworkingKit|DesignSystemKit|Feature[A-Za-z]+|SignalFlowApp)\b' \
        Sources/SimulationKit 2>/dev/null; then
    report "SimulationKit may depend only on DomainKit and CoreKit"
fi

# Rule 4 — DataKit is a data-layer module: it must not reach up into UI/features/app.
if grep -REn '^\s*import\s+(DesignSystemKit|Feature[A-Za-z]+|SignalFlowApp|SwiftUI|UIKit)\b' \
        Sources/DataKit 2>/dev/null; then
    report "DataKit must not import UI, feature, or app modules"
fi

# Rule 5 — IntelligenceKit implements a Domain port with FoundationModels: DomainKit only, no other
# first-party modules and no UI.
if grep -REn '^\s*import\s+(DataKit|PersistenceKit|NetworkingKit|SimulationKit|DesignSystemKit|Feature[A-Za-z]+|SignalFlowApp|SwiftUI|UIKit)\b' \
        Sources/IntelligenceKit 2>/dev/null; then
    report "IntelligenceKit may depend only on DomainKit (and FoundationModels)"
fi

# Rule 6 — SwiftData is owned exclusively by PersistenceKit. No other module may import it.
swiftdata_violators=$(grep -REln '^\s*import\s+SwiftData\b' Sources 2>/dev/null | grep -v '^Sources/PersistenceKit/' || true)
if [ -n "$swiftdata_violators" ]; then
    report "SwiftData may only be imported by PersistenceKit (found: $swiftdata_violators)"
fi

# Rule 7 — PersistenceKit adapts SwiftData to DomainKit: it may import DomainKit and SwiftData only,
# never another first-party module or UI.
if grep -REn '^\s*import\s+(CoreKit|DataKit|NetworkingKit|SimulationKit|IntelligenceKit|DesignSystemKit|Feature[A-Za-z]+|SignalFlowApp|SwiftUI|UIKit)\b' \
        Sources/PersistenceKit 2>/dev/null; then
    report "PersistenceKit may depend only on DomainKit (and SwiftData)"
fi

# Rule 8 — NetworkingKit is the remote-HTTP layer: DomainKit + Foundation only, never UI/SwiftData,
# another data module, or features.
if grep -REn '^\s*import\s+(CoreKit|DataKit|PersistenceKit|SimulationKit|IntelligenceKit|DesignSystemKit|Feature[A-Za-z]+|SignalFlowApp|SwiftUI|SwiftData|UIKit|FoundationModels|Combine)\b' \
        Sources/NetworkingKit 2>/dev/null; then
    report "NetworkingKit may depend only on DomainKit (and Foundation)"
fi

# Rule 9 — WidgetSupportKit renders **persisted** state only. It may read PersistenceKit (+ DomainKit
# + DesignSystemKit), but must never touch the live data engine (DataKit/SimulationKit/NetworkingKit)
# or own SwiftData. This is what keeps widgets reading the app's reconciled snapshot, not a divergent
# simulation. See docs/24-widgetkit.md.
if grep -REn '^\s*import\s+(DataKit|SimulationKit|NetworkingKit|IntelligenceKit|SwiftData)\b' \
        Sources/WidgetSupportKit 2>/dev/null; then
    report "WidgetSupportKit must read persisted state only (no DataKit/SimulationKit/NetworkingKit/SwiftData)"
fi

# Rule 10 — SnapshotKit is the UI-free read model shared by glance surfaces. It may read DomainKit +
# PersistenceKit, but must never import UI, WidgetKit, the live data engine, or SwiftData directly.
if grep -REn '^\s*import\s+(CoreKit|DataKit|SimulationKit|NetworkingKit|IntelligenceKit|DesignSystemKit|Feature[A-Za-z]+|SignalFlowApp|WidgetKit|SwiftUI|SwiftData|UIKit|AppIntents)\b' \
        Sources/SnapshotKit 2>/dev/null; then
    report "SnapshotKit may depend only on DomainKit and PersistenceKit"
fi

# Rule 11 — AppIntentsKit exposes App Intents over **persisted** state only. It reads via SnapshotKit
# (+ DomainKit + AppIntents/Observation), and must never touch the live data engine or SwiftData.
if grep -REn '^\s*import\s+(DataKit|SimulationKit|NetworkingKit|IntelligenceKit|SwiftData|WidgetKit|DesignSystemKit|Feature[A-Za-z]+|SignalFlowApp)\b' \
        Sources/AppIntentsKit 2>/dev/null; then
    report "AppIntentsKit must read persisted state only (via SnapshotKit; no DataKit/SimulationKit/NetworkingKit/IntelligenceKit/SwiftData)"
fi

# Rule 12 — LiveActivityKit drives Live Activities from **deterministic domain state**. It may use
# DomainKit + SnapshotKit (+ ActivityKit, iOS-guarded), but must never reach the live data engine,
# Foundation Models, SwiftData, or UI — so Live Activity content can't be AI-driven or data-coupled.
if grep -REn '^\s*import\s+(DataKit|SimulationKit|NetworkingKit|IntelligenceKit|FoundationModels|PersistenceKit|SwiftData|DesignSystemKit|WidgetKit|SwiftUI|Feature[A-Za-z]+|SignalFlowApp)\b' \
        Sources/LiveActivityKit 2>/dev/null; then
    report "LiveActivityKit must depend only on DomainKit + SnapshotKit (+ ActivityKit); no data engine, AI, SwiftData, or UI"
fi

# Rule 13 — WatchSupportKit (the watchOS companion's UI/models) reads persisted snapshots via SnapshotKit
# and the synced snapshot via WatchConnectivityKit. It must stay thin: no business logic, no data engine,
# no AI, no sibling glance surfaces, no features — and it must NOT import WatchConnectivity directly
# (that stays isolated inside WatchConnectivityKit; `WatchConnectivity\b` won't match `WatchConnectivityKit`).
if grep -REn '^\s*import\s+(DataKit|SimulationKit|NetworkingKit|IntelligenceKit|FoundationModels|WidgetKit|ActivityKit|WatchConnectivity|WidgetSupportKit|AppIntentsKit|LiveActivityKit|Feature[A-Za-z]+|SignalFlowApp)\b' \
        Sources/WatchSupportKit 2>/dev/null; then
    report "WatchSupportKit must depend only on DomainKit + SnapshotKit + WatchConnectivityKit (no data engine, AI, raw WatchConnectivity, or features)"
fi

# Rule 14 — WatchConnectivityKit is the ONLY module allowed to import WatchConnectivity. It reads
# DomainKit + SnapshotKit + PersistenceKit to build/persist the wire snapshot, but never the live data
# engine, AI, UI, or features.
if grep -REn '^\s*import\s+(DataKit|SimulationKit|NetworkingKit|IntelligenceKit|FoundationModels|SwiftUI|DesignSystemKit|WidgetKit|ActivityKit|Feature[A-Za-z]+|SignalFlowApp)\b' \
        Sources/WatchConnectivityKit 2>/dev/null; then
    report "WatchConnectivityKit may depend only on DomainKit + SnapshotKit + PersistenceKit (+ WatchConnectivity); no data engine, AI, UI, or features"
fi

# Rule 15 — WatchConnectivity is owned exclusively by WatchConnectivityKit. No other module may import it.
wc_violators=$(grep -REln '^\s*import\s+WatchConnectivity\b' Sources 2>/dev/null | grep -v '^Sources/WatchConnectivityKit/' || true)
if [ -n "$wc_violators" ]; then
    report "WatchConnectivity may only be imported by WatchConnectivityKit (found: $wc_violators)"
fi

if [ "$fail" -eq 0 ]; then
    echo "✅ architecture boundaries respected"
fi
exit "$fail"
