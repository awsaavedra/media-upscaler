---
name: delegation-ladder
description: Route work by scope: architecture, patterns, or code.
---

# Delegation Ladder

A > P > C

A: boundaries, data flow, components, constraints
P: modules, APIs, abstractions, reuse
C: implementation, tests, config

human = direct A, guide P, review C
agent = assist A, standardize P, execute C

escalate:
- system change -> A
- shared convention -> P
- local testable change -> C
- C ambiguity -> P
- P conflict -> A
