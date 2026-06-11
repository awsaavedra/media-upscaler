---
name: diagnostic
description: Four diagnostic skills. /pre-mortem ("what could go wrong", "imagine this fails") — assume failure; reverse-engineer modes before commitment. /five-whys ("what's the root cause", "why did this happen") — drill surface to actionable root with evidence. /feynman-test ("do I understand this?", "explain X simply") — audit comprehension via jargon-free explanation; jargon points = gaps. /decision-journal ("log this decision", "track this prediction") — log decisions + predictions + confidence for calibration. Tool-agnostic.
---

# Diagnostic Skills

---

## Pre-Mortem

Assume failure already happened 6 months out; reverse-engineer why. Assuming failure surfaces specific modes better than "what could go wrong?" Distinct from Steelyman (idea right?) and Five-Whys (post-failure).

**Triggers:** `/pre-mortem` · "what could go wrong" · "before we commit" · "imagine this fails" · before major irreversible commitments.
**Skip:** small reversible decisions · post-hoc analysis (use Five-Whys) · no concrete plan yet.

### Flow
1. **State plan + success criteria + confidence.** Bet-grade. Can't name failure without naming success.
2. **Set failure scene.** "It's [6 months out], the plan failed badly." Shape: catastrophic / slow / partial?
3. **5–7 distinct failure modes.** Specific, not generic ("ran out of time" → "migration broke on unicode names we didn't anticipate"). Categories: technical · org · market · comms · scope · dependency. Pass: someone could write a specific check.
4. **Each: warning signal + preventive check.** Warning = first-4-week alert. Preventive = cheapest action now.
5. **Rank by likelihood × severity.** Focus revision on top 2–3.
6. **Revise plan.** Warnings → metrics; preventives → upfront work. Top failure too large for cheap revision → reconsider.

**Prompt seed:** Don't ask "what could go wrong?" — assume it failed and ask "why?" Specific failures suggest specific preventives.

---

## Five-Whys

Drill iterative "why?" — each level grounded in evidence — to actionable root cause. Mirror of Pre-Mortem. "Five" is approximate: too shallow = surface fix won't prevent recurrence; too deep = true but not actionable. Right level: 3–7 whys for most engineering incidents.

**Triggers:** `/five-whys` · "what's the root cause" · "why did this happen" · after incidents / recurring bugs / missed deadlines · when an earlier fix didn't stick.
**Skip:** one-offs where surface fix is complete · speculative scenarios · blame conversations (finds causes, not people).

### Flow
1. **Surface problem concretely.** What / when / who affected / how noticed — specifics anchor every subsequent level.
2. **Why? Immediate cause with evidence.** Cite log line, commit, metric, test result. Speculation → stories, not causes.
3. **Repeat, evidence at each level.** Continue until actionable: process change · new test · monitoring · structural fix.
4. **Stop at right level.** Deepest changeable cause. Verify backward: does fixing root prevent the surface failure?

**Cause vs. story:** every event has many plausible narratives. Guards: every why cites evidence; beware compound causes ("X and Y") — often papering over uncertainty; "human error" is almost always a symptom, not a root.

**Prompt seed:** Drill surface to actionable root, evidence at each level. Stop when you reach something you can actually change.

---

## Feynman Test

Comprehension audit: explain in plain language to a smart 12-year-old. Points where you reach for jargon = your gaps. Iterative: identify gaps → research → re-explain → repeat until complete *and* accurate.

**Triggers:** `/feynman-test` · "do I actually understand this?" · "explain X simply" · before relying on a concept for a decision · before teaching · when cargo-culted understanding is suspected.
**Skip:** tacit skills (riding a bike) · precision-required contexts (legal, proofs) · public performance.

### Flow
1. **State concept specifically.** "How Raft achieves leader election under partition" — not "distributed consensus."
2. **Explain without jargon.** Define every term before use. No "basically"/"essentially" — these signal a skip. No authority appeals instead of explanation.
3. **Identify gaps.** Mark every hand-wave, jargon-reach, source-appeal, or "but why?" failure. These are real gaps.
4. **Research gaps.** Read the source; run the example. Don't paper over.
5. **Re-explain end-to-end.** Full second pass — patches don't integrate.
6. **Repeat.** Pass: a 12-year-old could explain it back in their own words.

**Simple-and-correct check:** after simplifying, verify it still produces correct predictions. If not, restore what was lost.

**Prompt seed:** If you can't explain it without jargon to a smart 12-year-old, you have gaps where you reach for technical terms.

---

## Decision Journal

Log decisions + predictions + confidence; check back; surface calibration patterns over time. Closes the prediction→outcome loop most people never close. Practice across time — not an in-conversation flow.

**Triggers:** `/decision-journal` · "log this decision" · "track this prediction" · "check back in N weeks" · before any decision with an evaluable expectation.
**Skip:** trivial decisions · inherently unevaluable outcomes · decisions you don't want to scrutinize.

### Entry Format
**Date / Situation / Options considered / Decision (what + why) / Expected outcome** (specific + falsifiable: "ship in 3 weeks with <2 critical bugs in first month") **/ Confidence** (bet-grade %) **/ Check-in date** (far enough out for outcome to be observable).

### Check-In
Did it pan out? Was confidence calibrated (90% confident → right ~9/10)? What pattern is emerging? Grade on aggregate — individual outcomes have noise.

**Patterns to watch:** chronic overconfidence (technical scoping, projections) · chronic underconfidence (new initiatives) · misweighted considerations · high-surprise outcomes (highest-information entries).

**Sustainable:** entries ≤2 min · set actual calendar reminders · backfill from emails/messages.

**Prompt seed:** Log decisions with predictions and confidence. The gap between predicted and observed reveals where your judgment is reliable and where it isn't.
