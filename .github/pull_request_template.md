<!--
SignalFlow PR template. See docs/14-git-workflow-and-ci.md.
Keep PRs small and single-purpose. main must stay green.
-->

## Summary
<!-- What does this PR do, in one or two sentences? -->

## Why
<!-- The rationale. What problem does it solve / what value does it add? -->

## Changes
<!-- Bullet the notable changes. Keep the diff focused — no unrelated drive-bys. -->
-

## Architecture
- [ ] No new cross-boundary imports (features don't reach the data layer; `DomainKit` stays pure)
- [ ] Relevant ADR referenced below, or a new ADR added if a significant decision was made

Related ADR(s): <!-- e.g. ADR-0001, or "n/a" -->

## Testing
<!-- What did you verify, and how? Paste relevant command output. -->
- [ ] `swift build`
- [ ] `swift test` (tests added/updated for new behavior)
- [ ] `./Scripts/check-boundaries.sh`

## Trade-offs / follow-ups
<!-- Honest notes on limitations, deferred work, or things a reviewer should know. -->

## Self-review checklist
- [ ] Single-purpose and reviewable in one sitting
- [ ] Conventional Commit title (squash-merge subject)
- [ ] `main` will remain stable after merge
