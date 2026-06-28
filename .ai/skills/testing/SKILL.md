---
name: testing
description: How to design tests, not just run them. /testing — pyramid, what-to-test, test doubles at seams, property-based testing, characterization tests for legacy code, test smells. Triggers: /testing · "how should I test this" · "what tests do I need" · "is this testable" · "write tests for" · "mock or not" · "test coverage".
when_to_use: Designing a test suite or deciding what and how to test a change. Pairs with software-engineering §Architecture (seams make code testable), debug (the failing-test-first gate), code-review (test currency), and rules.md rule 4. Not for chasing a specific failure — use debug.
---

# Testing

Tests exist to let you change code without fear. Design for that, not for a coverage number.

## Pyramid
Many fast unit · fewer integration · few end-to-end. Push each assertion to the lowest level that can hold it. Inverted (mostly E2E) = slow, flaky, vague failures.

| Level | Scope | Speed | Tests |
|---|---|---|---|
| Unit | one unit, deps faked at seams | ms | logic · branches · edge cases |
| Integration | real adapters (DB, HTTP, fs) | 10–100s ms | wiring · queries · serialization |
| E2E | whole system, user path | s+ | critical happy paths only |

## What to test
- **Behavior, not implementation.** Assert observable output/effect through the public seam. Tests mirroring internals break on every refactor.
- **Edge cases first.** empty · boundary (0/1/n, off-by-one) · null/absent · duplicate · overflow · concurrent · failure of each injected dependency. Lock these per §Architecture before coding.
- **One reason to fail per test.** Name states the behavior. Arrange–Act–Assert; one logical assertion.
- **Skip:** trivial getters · framework/library code · the language itself. Coverage is a floor signal, not a target — 100% of trivial ≠ tested.

## Test doubles (at seams)
Injected dependencies (§Architecture) are where doubles plug in.
- **Stub** canned return (state) · **Fake** working lightweight impl (in-memory store) · **Mock** asserts interaction (behavior) · **Spy** records calls.
- Prefer **real → fake → stub → mock.** Mock only true boundaries: network · clock · randomness · filesystem · external services.
- Don't mock what you own (couples tests to structure), value objects, or the system under test.

## Property-based
For logic with invariants, generate inputs instead of enumerating. Assert properties: round-trip (`decode(encode(x))==x`) · invariant (sorted stays sorted) · oracle (matches a slow reference) · idempotence. Shrinking yields the minimal failing case. Use for parsers, serializers, math, data structures.

## Legacy / untested code
1. **Characterization test** — pin current behavior (even if "wrong") to freeze a baseline.
2. Find a seam; inject the dependency.
3. Refactor under the green characterization tests.
4. Swap pinned tests for intended-behavior tests once the behavior is understood.

No seam yet → add the minimum one (sprout new code in a function/class, or wrap the call site), test the new code, leave the rest pinned.

## Test smells
slow suite (real I/O in unit tests) · flaky (timing/order/shared state — a real bug; see debug §Flaky) · fragile (asserts internals or mocks owned code) · obscure (no clear Act) · conditional logic in a test · order-coupled tests · assertion roulette (many asserts, unclear which failed) · testing the mock instead of the code.

## Gates
- New behavior ships with a test that fails without it (rules.md rule 4 · debug Phase 4).
- Bug fix ships with a regression test that reproduces it first.
- Tests read as spec: a reader learns what the unit does from the names.
- Suite is deterministic and fast enough to run on every change.
