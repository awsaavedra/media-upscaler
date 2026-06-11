---
name: code-review
description: Explicit code review process. Audit existing code against Clean Code and Architecture rules. Output: actionable diffs, imperative feedback, or PASS. Triggers: /review · "review this" · "audit this code" · "what's wrong with this"
when_to_use: Explicitly invoked on existing code. Evaluative — not always-on. Distinct from writing or generating code.
---

# Code Review

Evaluative process. Criteria defined in software-engineering skill; this skill defines process and output format.

## Process

1. **Design audit.** Naming · function shape · SRP/DIP · DRY · KISS/YAGNI · fail-fast · smells.
2. **Architecture audit.** Seams · interface boundaries · injection · infrastructure imports at logic layer · component independence.
3. **CLI/DevEx audit** (if applicable). POSIX compliance · output terseness · no interactive prompts.
4. **Documentation currency.** Docs reflect actual implementation and exact file paths.

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

## Gates

```
[ ] no infrastructure imports at logic layer
[ ] all external dependencies injected
[ ] no magic numbers · no dead code
[ ] SRP: one reason to change per module
[ ] routing/shim layers remain thin
[ ] docs match committed implementation
```
