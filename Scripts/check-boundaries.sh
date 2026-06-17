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

# Rule 2 — Feature modules must not reach into the data layer.
for feature in Sources/Feature*; do
    [ -d "$feature" ] || continue
    if grep -REn '^\s*import\s+(DataKit|PersistenceKit|NetworkingKit|SimulationKit)\b' "$feature" 2>/dev/null; then
        report "$(basename "$feature") must not import a concrete data module"
    fi
done

if [ "$fail" -eq 0 ]; then
    echo "✅ architecture boundaries respected"
fi
exit "$fail"
