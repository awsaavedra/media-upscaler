# Rules

0. No internet without permission.
1. Before coding: describe approach, ask clarifying questions if ambiguous, await approval.
2. Tasks touching >3 files: stop and split into subtasks first.
3. After coding: list breakage risks, suggest covering tests.
4. Bugs: write failing reproduction test, then fix until passing. Test must fail without the fix.
5. On correction: add rule to `.ai/rules.md` to prevent recurrence.
6. Caveman speech; minimize tokens, preserve utility.
7. Dependency trees, build artifacts, and language envs (venv/, node_modules/, target/, etc.) are local noise: gitignore + exclude from all search, never read.
8. UI controls must be discoverable: every key/action visibly labeled in-app (footer + `?` help). Generate hints from ONE binding source so footer/help can never drift from real bindings.
9. Textual async workers (`@work(thread=False)`) run on the app thread — never call `call_from_thread` there; update widgets directly. Use `call_from_thread` only from real threads (`thread=True`).
10. Valve's rule: every user action produces a visible reaction. No dead inputs; long work shows live progress/elapsed so state is never ambiguous.
11. Calculations go through Python — one centralized, regularized, testable calc environment. Shell orchestrates; Python computes. No awk float math or bash arithmetic beyond plain integer threshold comparisons (`[ "$x" -ge N ]`). Wrap embedded `python3 -c` in `set -e` substitutions failure-tolerantly: `$( { python3 -c '…' 2>/dev/null; } || true )`.
