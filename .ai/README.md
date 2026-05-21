# AI Tooling Project Structure

Tool-agnostic layout for AI assistant context. Maps onto Claude Code, Cursor, Aider, Codex CLI, Continue, Copilot, etc.

```
project/
├── AGENTS.md              # Session context: stack, commands, constraints
├── AGENTS.local.md        # Personal overrides (gitignored)
├── .mcp.json              # MCP servers (external integrations)
└── .ai/
    ├── settings.json      # Permissions, tool access, model defaults
    ├── settings.local.json
    ├── rules/             # Modular guidance by topic
    ├── commands/          # Reusable prompts / slash commands
    ├── skills/            # Capability bundles, on-demand
    ├── agents/            # Specialized sub-agents
    └── hooks/             # Lifecycle scripts (pre/post tool, commit)
```

## Tool mapping

| Concept  | Claude Code             | Cursor                  | Codex / generic     | Copilot                           |
|----------|-------------------------|-------------------------|---------------------|-----------------------------------|
| Context  | `CLAUDE.md`             | `.cursor/rules/*.mdc`   | `AGENTS.md`         | `.github/copilot-instructions.md` |
| Settings | `.claude/settings.json` | `.cursor/settings.json` | `.ai/settings.json` | `.vscode/settings.json`           |
| MCP      | `.mcp.json`             | `.cursor/mcp.json`      | `.mcp.json`         | (preview)                         |
| Commands | `.claude/commands/`     | Composer presets        | `.ai/commands/`     | Chat participants                 |
| Skills   | `.claude/skills/`       | —                       | `.ai/skills/`       | —                                 |
| Agents   | `.claude/agents/`       | Custom modes            | `.ai/agents/`       | —                                 |
| Hooks    | `.claude/hooks/`        | —                       | `.ai/hooks/`        | —                                 |

Where a tool lacks native support, keep the file in `.ai/` anyway — documents intent, ready when the tool catches up.

## Adopt incrementally

1. `AGENTS.md` — symlink your tool's expected file to it.
2. `.ai/rules/` — when one rules file gets too long.
3. `.ai/commands/` — first time you copy-paste the same prompt twice.
4. `.mcp.json` — when the assistant needs external systems.
5. `.ai/hooks/` — when the harness should catch something deterministically.
6. `.ai/agents/` + `.ai/skills/` — when the main context gets crowded.

## In this repo

[`rules.md`](rules.md) holds cross-cutting AI rules for every project. [`skills/`](skills/) implements the six reusable skill clusters below — drop them into any project's `.ai/skills/` or symlink into `.claude/skills/` per the tool mapping above. The directory layout above is a **template** — apply per-project as needed.

## Skills

**Rule:** All rules must be dual-readable (human + agent) and losslessly compressed to minimum tokens.

Reusable Socratic / argumentation / diagnostic skills any AI assistant can invoke. Tool-agnostic — drop into `.ai/skills/` or symlink into `.claude/skills/` per the tool mapping above. Organized into two cluster files.

**[Argumentation cluster](skills/argumentation/SKILL.md)** — `/argumentation-hygiene`, `/you-sure`, `/steelyman`, `/double-crux`
- `argumentation-hygiene` — Umbrella rulebook: good-faith principles, bad-faith taxonomy (motte-and-bailey, sealioning, gish gallop, etc.), self-audit checks.
- `you-sure` — AI self-audits a confident claim. ITT the strongest opposing views, surface assumptions, revise. Triggered by `/you-sure` or pushback ("you sure?", "really?").
- `steelyman` — Consensual adversarial collaborator for the user's writing/code/plan/design. ITT first, then challenge; hold under pushback. Triggered by `/steelyman` or "tear this apart."
- `double-crux` — Symmetric productive disagreement. Each side names what evidence would flip their position; locate whether disagreement is shared crux, crux-mismatch, values-level, or empty.

**[Diagnostic cluster](skills/diagnostic/SKILL.md)** — `/pre-mortem`, `/five-whys`, `/feynman-test`, `/decision-journal`
- `pre-mortem` — Assume failure and reverse-engineer why, before committing. Surface failure modes and early-warning signals.
- `five-whys` — Root-cause drilling after a real incident. Evidence at each level; stop at the deepest actionable cause.
- `feynman-test` — Comprehension audit by jargon-free explanation. Points where you reach for technical terms are your gaps.
- `decision-journal` — Log decisions + predictions + confidence for later calibration audit. Practice across time, not in-conversation.

**[Delegation ladder](skills/delegation/SKILL.md)** — routes work by scope
- `delegation-ladder` — Decides whether a task belongs at the architecture, pattern, or code level, then hands it to the right agent or handles it inline. Keeps strategic decisions from leaking into implementation and vice versa.

**[Software engineering](skills/software-engineering/SKILL.md)** — coding principles cluster
- `design` — Clean code rules applied automatically: naming, function shape, class design (SRP/DIP), DRY, KISS/YAGNI, fail-fast, smell detection, and the Boy Scout Rule.
- `architecture` — Seam-first design: depend on interfaces, inject all external dependencies, keep infrastructure out of the logic layer. Lock edge cases before implementation; verify component independence.
- `cli-devex` — POSIX-compliant, pipeline-friendly CLI rules: stdin/stdout, no interactive prompts, terse/machine-readable output, composable commands, exit codes as contracts.
- `documentation` — Docs reflect actual implemented state; update atomically with code; exact paths and decisions; no lagging or historical archaeology.

**[Code review](skills/code-review/SKILL.md)** — explicit review workflow
- `code-review` — Evaluative process distinct from code generation. Audits Design, Architecture, CLI, and Documentation rules; outputs `[FILE:LINE] RULE — fix: action` or `PASS` per item. Prioritized by correctness → seams → DRY/naming → style.

**[Debug](skills/debug/SKILL.md)** — five-phase bug investigation
- `debug` — Phased process for bugs, test failures, build failures, performance regressions, memory issues, and concurrency problems. Reproduce → pattern analysis → hypothesize/eliminate → fix at root → verify with fresh evidence. Enforces: no fix without confirmed root cause, no completion claim without verification, eliminate hypotheses rather than confirm them.

**[Security](skills/security/SKILL.md)** — scoped security review
- `security` — Evaluative, read-only by default. Scopes: `code` · `agent` · `infra` · `threat-model` · `full`. Outputs tiered findings (HIGH / MEDIUM / LOW / CLEAN) classified against OWASP Top 10:2025, CWE, CVSS v4. Covers language flaw matrices, ASI agent controls (14), STRIDE threat modeling, secrets handling, and compliance mapping (PCI / HIPAA / GDPR / SOC 2 / NIST / ISO).

**[Research](skills/research/SKILL.md)** — multi-source investigation with citations
- `research` — Decomposes a question into sub-queries, searches across papers/docs/repos, cross-validates claims (2+ sources each), and produces a structured report with inline citations and an explicit gaps section. Inspired by [karpathy/autoresearch](https://github.com/karpathy/autoresearch).

### Roadmap

Candidate skills identified as gaps in the current suite. Listed in rough priority order; none drafted yet. Software-engineering and writing-paper workflows are considered covered by the implemented skills above.

1. **Estimation / forecasting** — Heuristics for time / cost / effort estimates: reference class forecasting, anchor-and-adjust, planning fallacy, range vs. point estimates, "the question is wrong" detection. Closes the loop with `decision-journal` — predictions logged there are the kind an estimation skill would help make well.
2. **Planning / decomposition** — Turn ambiguous goals into structured plans: hierarchical breakdown, dependency mapping, definition-of-done, milestone selection, MoSCoW. Distinct from `delegation-ladder` (which routes existing work).
3. **Data analysis hygiene** — Sanity checks, base rates, distribution awareness, outlier handling, confounders, Simpson's paradox, signal-vs-noise tests. `research` covers literature; this covers numbers.
4. **Communication for action** — PRs, RFCs, async status updates with audience-awareness and action-oriented framing. Distinct from `documentation` (which syncs docs with code).
5. **Prioritization** — ICE / RICE scoring, opportunity cost, "what to NOT do." Could fold into a planning skill or stand alone.
