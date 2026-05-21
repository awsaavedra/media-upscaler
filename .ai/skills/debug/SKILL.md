---
name: debug
description: Phased bug investigation. Use before proposing any fix for bugs, errors, unexpected behavior, test/build failures, perf/memory regressions, or concurrency issues. Triggers: `/debug` · "debug this" · "fix this bug" · "why isn't this working" · "value is null" · "not updating" · "investigate this" · "tests failing" · "slow" · "memory leak" · "race condition" · "flaky test" · "broken build".
when_to_use: Any code change responding to a bug or unexpected behavior. Auto-engages on the triggers above.
---

# Debug

## Mode
- `/debug` (auto, default) — invocation IS the approval. Run `/compact`, apply fix, add guard test, modify lint/CI without prompting. Phase 4 attempt 3+ still requires human.
- `/debug ask` — propose mutating actions; user confirms each. Read-only inspection, diagnostic logging, and test runs proceed without prompts in either mode.

## Iron Laws
1. **No fix without confirmed root cause.** Symptom patches = failure.
2. **No "done" without fresh verification.** "Should work" ≠ evidence.
3. **Eliminate, never confirm.** Tests must disprove favorites, not validate them.

## Stop-the-Line
ANY unexpected event → STOP changes (errors compound; bug at step 3 makes 4–10 wrong) · PRESERVE evidence (output, logs, exact repro) · follow phases in order · RESUME only after Phase 5 passes.

## Phase 1 — Reproduce & Evidence
**Read before touching code.** Full error / stack / line numbers / file paths / error codes. State expected vs. actual in one sentence. Check `git diff`, dep bumps, config/env drift, recent deploys.

**Repro reliably?**
- **YES** → Phase 2.
- **NO** → gather context (logs/env/state) · minimize repro · if timing-dependent: instrument, check races · if still non-repro: document what was ruled out, add appropriate handling (retry/timeout/graceful error), add logging for future, classify as **environment/timing** class bug.

**Multi-component** (API→service→DB, CI→build→deploy): boundary-log BEFORE any hypothesis — what ENTERS, what EXITS, config/env at each layer. Run once → find where the invariant breaks → investigate ONLY that layer.

**Secrets / PII — unconditional, both modes.** Never log, print, or diff credential values, tokens, keys, or PII. Compare presence/config only (set/unset, length, source, hash). Redact before any diagnostic output, fixture, or paste. Applies to boundary logging, env diffs, stack traces, and any other output this skill produces.

**Trace backward.** Bad value deep in stack → walk upstream to origin. Fix at source, not symptom layer.

**Minimal repro.** Smallest code/data/env that still triggers — eliminates false hypotheses, confirms scope.

**Long session.** Many tool calls / large reads / multiple failed attempts → run `/compact` (auto) or propose it (ask) before continuing. Context decay causes missed details and repeated mistakes.

## Phase 2 — Pattern Analysis
Contrast before any hypothesis:
1. **Find a working example** in the same codebase.
2. **Read it fully** — no skim.
3. **List every diff** — even trivial. "Can't matter" is wrong.
4. **Identify the gap** — what env / config / state / timing does the working version have that the broken one doesn't?

## Phase 3 — Hypothesize & Eliminate
1. List 3–5 candidate root causes explicitly.
2. **Eliminate, don't confirm.** Smallest test that would DISPROVE each. Test most falsifiable first, not most likely.
3. State one active hypothesis: *"I believe X because Y. This disproves it if Z."*
4. Not disproved → next hypothesis. Never layer fixes on a failed attempt.
5. Stuck → binary search: `git bisect` · comment out half of suspected code · toggle config vars one at a time · narrow to a 10-line failing case.
6. Root cause found → 5 Whys: "why does this condition exist?" up to 5x. Stop at a broken process or systemic gap (not just a code line).
7. Don't understand something → say so. No fabricated confidence.

## Phase 4 — Fix
1. **Failing test first.** Automated preferred; one-off script OK. No test = no fix.
2. ONE change at root cause. No "while I'm here" refactors.
3. One sentence: what the fix does + why it addresses the confirmed root cause.
4. Note edge cases / side effects introduced.
5. Keep diagnostic logs until Phase 5 passes.

**Attempt limit.** 1–2 fail → return to Phase 1 with new info. 3+ → STOP, likely architectural (each fix exposes new coupling · requires massive change · creates new symptoms). Discuss with a human before another attempt.

## Phase 5 — Verify & Guard
**Verification Gate** (mandatory before any "done" claim):
1. **IDENTIFY** the exact command that proves fixed (test suite / build / linter / manual step).
2. **RUN** the full command fresh — no cached, no assumed results.
3. **READ** full output, exit code, failure count.
4. **CONFIRM** — output doesn't show pass → state actual status with evidence, return to Phase 3/4. Pass → state the claim with the pasted output.
5. Only then: declare fixed.

**Regression check.** Full test suite; count failures before/after; zero new failures required. Verify no adjacent functionality broke. Remove diagnostic logs.

**Guard against recurrence.** Permanently add the Phase 4 test if not already in the suite. If the class can recur: add a lint rule / assertion / CI gate. Document: *"Root cause was X. Future protection: Y."*

## Bug Classes

| Class | Signals | Approach |
|---|---|---|
| **Logic** | Wrong output / state / control flow | Standard 5-phase |
| **Perf / Memory** | Memory grows over time · slow under load · CPU spikes | Profile BEFORE hypothesizing; establish baseline first |
| **Concurrency / Race** | Intermittent · order-dependent · "works locally" · corruption under load | Assume shared mutable state; check locks, unawaited async, missing cleanup |
| **Env / Config** | Works locally, fails in CI/stage/prod | Diff env vars · versions · credential presence/config (never values) · network rules · file paths |
| **Flaky Tests** | Non-deterministic pass/fail | Real bugs — do NOT re-run until green. Find the non-determinism (timing, test order, shared state) |

## Red Flags — STOP, back to Phase 1

| Thought | Reality |
|---|---|
| "Quick fix now, investigate later" | You won't |
| "Probably X — let me fix that" | Probability ≠ evidence — disprove it |
| "Multi-change to save time" | Can't isolate what worked; causes new bugs |
| "Test after the fix" | Untested fixes don't stick |
| "Simple, skip the process" | Simple bugs have root causes too |
| "Don't fully get it but might work" | It won't. Phase 1 |
| "One more attempt" after 2+ fails | Architectural — stop |
| "Should work / probably / seems fine" | Not evidence — run the gate |
| "Done! / Fixed!" without pasted output | Gate first |
| "Found root cause" with no 5 Whys | Ask why that condition exists |

## Quick Reference

| Phase | Gate | Done when… |
|---|---|---|
| 1. Repro & Evidence | Must precede Phase 2 | Reliable repro OR classified env/timing; compacted if needed |
| 2. Pattern | Must precede Phase 3 | Know what differs from working code |
| 3. Hypothesize | Must precede Phase 4 | Root cause confirmed by elimination + 5 Whys applied |
| 4. Fix | Failing test first | One change at root level |
| 5. Verify & Guard | Fresh command output required | Target passes (with pasted output) · zero new failures · guard added · logs cleaned |
