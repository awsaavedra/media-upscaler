---
name: release-engineering
description: Versioning and release skill — Semantic Versioning, Keep a Changelog, Conventional Commits, tagging, deprecation policy, backward-compatibility / API stability. Triggers: /release · "cut a release" · "version bump" · "is this a breaking change" · "write the changelog" · "deprecate this". Owns the `ship` gate's release stage.
when_to_use: Preparing or cutting a release, choosing a version bump, writing release notes, or planning a deprecation. Pairs with `ship` (release stage), `software-engineering` §Documentation (commit convention) and §Architecture (stable, replaceable interfaces).
---

# Release Engineering

## Semantic Versioning
`MAJOR.MINOR.PATCH` — MAJOR = incompatible API change · MINOR = backward-compatible feature · PATCH = backward-compatible fix. Pre-release `-rc.1` / `-beta`; build `+meta`. **`0.y.z`** = unstable: anything may break, `y` acts as the breaking axis. Reaching `1.0.0` is a stability commitment, not a maturity badge.

## Breaking change = MAJOR
Any change to the public contract: removed / renamed exported symbol · changed signature or required args · changed default that alters behavior · narrowed accepted input or widened output type · changed error / exit-code contract · removed config key. Additive-only = MINOR. When unsure whether a surface is public, treat it as public.

## Conventional Commits → bump
`fix:` → PATCH · `feat:` → MINOR · `feat!:` / `fix!:` or a `BREAKING CHANGE:` footer → MAJOR. `docs` / `refactor` / `test` / `chore` → no release. (A repo's own commit convention may differ — map intent, don't assume the prefix.)

## Changelog — Keep a Changelog
Human-curated `CHANGELOG.md`, newest first. `## [Unreleased]` accrues during dev; cut to `## [X.Y.Z] - YYYY-MM-DD` on release. Group entries: **Added · Changed · Deprecated · Removed · Fixed · Security**. Write for the consumer (what changed + how to migrate), not a raw `git log`. Link each version to its compare/diff URL.

## Tagging
Annotated, signed where possible: `git tag -s vX.Y.Z`. Tag == released commit == changelog entry. Prefix `v`. Never move or delete a published tag.

## Deprecation policy
Announce → deprecate (still works, emits a documented warning, changelog `Deprecated`) → remove (next MAJOR only). State the removal version and a migration path at announcement. Never remove a public surface without a prior deprecated release.

## Release gate
```
[ ] version chosen from the change (breaking? → MAJOR)
[ ] CHANGELOG Unreleased → versioned + dated
[ ] tag annotated / signed, matches the changelog
[ ] artifacts built, checksummed, signed
[ ] migration notes for any deprecation / removal
```
