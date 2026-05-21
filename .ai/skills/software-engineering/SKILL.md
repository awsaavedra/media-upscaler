---
name: software-engineering
description: Software engineering principles cluster. /design — clean code rules for naming, functions, classes, refactoring. /architecture — seam-first design for replaceable dependencies. /cli-devex — POSIX-compliant, pipeline-friendly CLI rules. /documentation — keep docs in sync with committed code.
when_to_use: Writing, refactoring, or designing code. Apply design automatically; invoke other sections explicitly for a focused audit.
---

# Software Engineering

## Design

Apply clean code principles automatically when writing or reviewing code.

### Rules
- **Names:** Exact. Verbs→functions, nouns→classes. No abbreviations, no magic numbers.
- **Functions:** One thing. ≤3 args (else object). No side effects. No flag args. ≤20 lines.
- **Comments:** Explain *why*, never *what*. No commented-out code. Block needs explaining → extract to named function.
- **Classes:** SRP. DIP. Prefer composition over inheritance.
- **DRY:** One authoritative home per piece of knowledge.
- **KISS/YAGNI:** Simplest solution that works. Don't build for imaginary futures.
- **Fail fast:** Validate at boundary; surface errors early.
- **Smells:** long methods · large classes · duplicates · feature envy · primitive obsession · type-switch chains · dead code
- **Boy Scout Rule:** Leave every file cleaner than found.
- **Refactor continuously.**

---

## Architecture

Build seams — places where behavior can be swapped without editing the caller — so any dependency is replaceable.

### Rules
- **Depend on interfaces, not implementations.** `EmailSender`, `BillingGateway`, `UserStore` — never SendGrid, Stripe, Postgres directly.
- **No infrastructure imports at logic layer.** Domain model imports ORM/framework/HTTP client → seam lost.
- **Inject everything touching the outside world.** HTTP clients, clocks, file systems, random sources — all injected.
- **Treat every hard dependency as a logged decision.** Ask: *what would it cost to replace this?* High cost → add a seam.
- **Lock edge cases and state transitions before implementation.** Undefined boundary behavior is harder to fix after code exists.
- **Verify component independence.** Each component testable and deployable without its neighbors.
- **Seams pay off:** independent testability · vendor swappability · service extraction. Without them, dependencies become load-bearing walls.

---

## CLI / DevEx

Rules for command-line interfaces and developer tooling.

### Rules
- **POSIX-compliant.** Single-char `-v`, long-form `--verbose`. No Windows-only conventions.
- **Pipeline-friendly.** stdin/stdout first. Zero interactive prompts; no graphical dependencies.
- **Terse or machine-readable output.** Default: minimal human-readable. Support `--json`/`--quiet` where appropriate.
- **Composable.** Each command does one thing; complex workflows are shell compositions, not monolithic commands.
- **Exit codes are contracts.** 0 = success, non-zero = failure. Always.

---

## Documentation

### Rules
- **Reflect actual state.** Document what is implemented, not what was planned or is aspirational.
- **Exact paths and decisions.** File paths, architectural choices, removed dependencies — all explicit.
- **Atomic updates.** Docs update in the same commit as the code change. Never lag.
- **No historical archaeology.** Remove outdated content; don't append corrections to stale text.
- **Commit messages:** `#type, what; what; what` — type is the intent (add/fix/doc/refactor/stabilize/edit), clauses are semicolon-separated, no Co-Authored-By.
