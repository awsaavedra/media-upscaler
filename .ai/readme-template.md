# Repo README template

Skeleton for a project README — fill the bracketed placeholders, drop sections that don't apply. Pairs with [`rules.md`](rules.md) (the 0–7 behavioral rules); the `## Rules` section below is where project-specific rules go, seeded by the high-impact examples at the bottom.

## Project
[One line: what this does, who uses it]

## Design Principles
[Key constraints and tradeoffs this project optimizes for, e.g. composable; non-destructive; local-first]

One line per principle here; full design choices — constraints, tradeoffs, rejected alternatives — live in [`docs/design.md`].

## Quickstart
[One line per step to get running, e.g. install deps, set env vars, run dev server]

## Stack
[Framework, language, database, deployment]

## Commands
- Dev: `[cmd]`
- Build: `[cmd]`
- Test single: `[cmd] -- [path]`
- Test all: `[cmd]`
- Lint: `[cmd]`
- Type check: `[cmd]`
## Architecture
- [folder] → [what lives here]   (one line per folder)
- [file] → [what this file does]
## Rules
- [Rule preventing a specific mistake]   (3-5 entries)
- IMPORTANT: [The one rule ai-tool keeps breaking]
## Workflow
- [Task approach]
- [Commit conventions]
- [Testing expectations]
- [Ask vs act]

## Roadmap
| Version | Status | Theme |
|---|---|---|
| **v0** | ✅ shipped | [one-line capability theme] |
| **v1** | 🟡 in progress | [theme] |
| **v2** | 🔵 planned | [theme] |

Status key: ✅ shipped · 🟡 in progress · 🔵 planned · ⏸ paused · ❌ dropped. Tag shipped versions (e.g. `v1.0.0`). One line per version here; full item lists, rationale, and rejected alternatives live in [`docs/roadmap.md`]. Link each milestone to what substantiates it — specs/tests (e.g. `tests/…`), design notes / ADRs (e.g. `docs/design-notes.md`). No volatile per-item lists in the README.
## Out of scope
- [Don't-touch areas]
- [Manually-maintained files]
- [Off-limits integrations]

---

# High-impact rule examples
- IMPORTANT: type check after every code change (prevents shipping broken types)
- Minimal changes; no unrelated refactoring (prevents whole-file rewrites)
- Separate commit per logical change (prevents 47-file monster commits)
- When unsure, present alternatives; I choose (prevents unilateral architecture decisions)
- Static export only, no SSR (prevents server-side code in static sites)
