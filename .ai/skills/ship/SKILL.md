---
name: ship
description: Release-readiness gate — the ordered, delegating filter that decides whether a whole project is ready to go public (open-source / first release). Meta-skill: runs other skills as stages and emits GO | NO-GO. Triggers: /ship · "ready for prime time" · "is this ready to open-source" · "ship-to-public check" · "run the release-readiness gate".
when_to_use: Taking a whole project public or cutting a first release — not a single-diff review (that's `code-review`). Deterministic entry point: type `/ship`. Delegates to the skills it names per stage (`testing`, `debug`, `code-review`, `security`, `software-engineering`, `governance`, `legal`, `release-engineering`); port those alongside it.
---

# Ship

Release-readiness gate. Orchestrates other skills as ordered stages — owns no review rules of its own.

## Run
Stages in order. Each is blocking: **STOP at the first FAIL**, emit the report, do not run later stages — don't polish a later stage on a project that fails an earlier one. Invoke the owning skill per stage; gather its evidence before marking PASS.

1. **Functional** — builds · tests pass · runs from a clean clone → `testing` · `debug`.
2. **Quality** — codebase passes the review audit → `code-review`.
3. **Security** — full git-history secret/PII scan (`security` §Secrets *Pre-publish*) + dependency CVE / lockfile audit (§Dependencies) → `security full`.
4. **Docs** — README / install / usage reflect actual state; quickstart works from the clean clone → `software-engineering` §Documentation.
5. **Governance** — LICENSE · CONTRIBUTING · CODE_OF_CONDUCT · SECURITY.md + disclosure · issue / PR templates present and accurate → `governance`.
6. **Legal** — AS-IS warranty / liability disclaimer present & not weakened · every dependency and **AI model weight** license permits use + redistribution · attribution / NOTICE complete → `legal`.
7. **Release** — semver · changelog · tag plan · deprecation policy → `release-engineering`.
8. **Publish** — manual + irreversible (once public + indexed, a leaked secret is burned). Only when 1–7 are GO: tag the release · push to the registry · flip the repo public. Stop at this boundary and hand the irreversible action to the human.

## Output
```
## Release-readiness: <project>
1 Functional   PASS | FAIL — <evidence>
2 Quality      PASS | FAIL — <evidence>
3 Security     PASS | FAIL — <evidence>
4 Docs         PASS | FAIL — <evidence>
5 Governance   PASS | FAIL — <evidence>
6 Legal        PASS | FAIL — <evidence>
7 Release      PASS | FAIL — <evidence>
GATE: GO | NO-GO (blocked at stage N — <reason>)
Next: <manual publish steps from stage 8, only when GO>
```
