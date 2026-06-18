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

# Rule 2 — Feature modules must not reach into the data/infrastructure layer.
for feature in Sources/Feature*; do
    [ -d "$feature" ] || continue
    if grep -REn '^\s*import\s+(DataKit|PersistenceKit|NetworkingKit|SimulationKit|IntelligenceKit|FoundationModels)\b' "$feature" 2>/dev/null; then
        report "$(basename "$feature") must not import a concrete data/intelligence module"
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

if [ "$fail" -eq 0 ]; then
    echo "✅ architecture boundaries respected"
fi
exit "$fail"
