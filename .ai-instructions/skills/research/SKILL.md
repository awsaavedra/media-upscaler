---
name: research
description: Multi-source web research agent. Search, cross-validate, cite, report gaps. Triggers: research · compare · benchmark · literature review · best X for · landscape of · what does evidence say
when_to_use: Any topic investigation, tool comparison, literature review, or evidence-backed report.
---

# Research

**Pipeline.** decompose → search → validate → synthesize → gap-check.

- **decompose** — query → sub-questions
- **search** — 3–5 queries each; papers > docs > repos > blogs
- **validate** — 2+ sources/claim; conflict → report both
- **synthesize** — structured report, every fact cited inline
- **gap-check** — list what could not be verified

## Rules
Think first (plan before querying) · verify (no unsourced assertions) · increment (refine from results, don't batch-blast) · no fabrication (missing → say so; never invent stats/dates/quotes).

## Search Patterns
```
<topic> site:github.com OR arxiv.org
<topic> official documentation
<topic> paper 2024 OR 2025 OR 2026
<topic> vs <alt> benchmark
<topic> limitations criticism
```
Short keyword queries only. Split multi-entity queries.

## Output
```markdown
# Research Report: [Topic]
## Summary          [2–3 sentences. Confidence: High/Medium/Low]
## Findings         [2–4 sentences/sub-topic. Cite as [1][2].]
## Comparison       | Option | Strengths | Weaknesses | Best For |
## Recommendation   Primary/Alternative/Avoid — [reason each]
## Gaps             [unverified or conflicting claims]
## Sources          1. [Title](url)
```

## Gates
Every stat cited · conflicts not co-asserted as fact · recs derived from findings (not priors) · gaps populated.

## Depth
Quick (3–5 sources) · **standard (8–12, default)** · deep (15+).

> Source: [karpathy/autoresearch](https://github.com/karpathy/autoresearch)
