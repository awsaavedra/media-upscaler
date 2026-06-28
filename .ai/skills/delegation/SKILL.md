---
name: delegation-ladder
description: Route work by scope before acting — Architecture > Pattern > Code. Triggers: /delegate · "what level is this" · "who should own this" · "is this an architecture or a code change" · before picking up an ambiguously-scoped task.
when_to_use: Before starting a task whose scope is unclear, or when a change feels bigger or smaller than the level it's being handled at. Routes work to the right level; pairs with planning (which produces the breakdown this routes) and software-engineering §Architecture (seams define the A/P boundary).
---

# Delegation Ladder

Levels — **A > P > C**:
- **A — Architecture:** boundaries, data flow, components, constraints.
- **P — Pattern:** modules, APIs, abstractions, reuse.
- **C — Code:** implementation, tests, config.

Ownership:
- human = direct A · guide P · review C
- agent = assist A · standardize P · execute C

Route / escalate:
- system-wide change -> A
- shared convention -> P
- local testable change -> C
- C ambiguity -> P
- P conflict -> A

Rule: route up until the level owns the change's blast radius, then act there. Strategic decisions must not leak into implementation, nor implementation choices silently set strategy.

Example: "add a retry to the payment call" reads as **C** — but a retry is a shared convention for every outbound call (**P**), and if it implies a new resilience layer across services it's **A**. Settle the level first; a retry decided at C becomes an inconsistent pattern later.
