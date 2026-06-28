---
name: code-review
description: Explicit code review process. Audit existing code against Clean Code and Architecture rules. Output: actionable diffs, imperative feedback, or PASS. Triggers: /review · "review this" · "audit this code" · "what's wrong with this"
when_to_use: Explicitly invoked on existing code. Evaluative — not always-on. Distinct from writing or generating code.
---

# Code Review

Evaluative process. Criteria defined in software-engineering skill; this skill defines process and output format.

## Process

Apply each rule set against the code; the authoritative rules live in `software-engineering` — this skill orders the passes and formats findings.

1. **Design audit** — `software-engineering` §Design.
2. **Architecture audit** — §Architecture.
3. **CLI / DevEx audit** (if applicable) — §CLI / DevEx.
4. **Documentation currency** — §Documentation.

## Output Format

```
[FILE:LINE] <RULE> — fix: <imperative action>
PASS: <what was checked>
```

- One finding per item.
- No theory. Apply the rule; state the fix.
- No praise for passing unless requested.

## Priority

```
critical   correctness · security · broken contracts
high       missing seams · infrastructure in logic layer · SRP violations
medium     DRY · naming · function shape · smells
low        style · minor verbosity
```

## Hand-offs
- Finding is a live bug (wrong output/state, not just a rule violation) → `debug` — root-cause it, don't patch in review.
- Security-sensitive surface (auth, input handling, secrets, deserialization, SQL, file/exec) → `security` for a data-flow trace.
- Missing, fragile, or absent tests → `testing` for coverage design.
- Taking the whole project public (open-source / first release), not just this diff → `ship` — the release-readiness gate that runs this review as its quality stage.

## Gates

Blocking checks specific to review (the rule-level gates live in `software-engineering`):

```
[ ] routing / shim layers remain thin
[ ] docs match committed implementation
```
