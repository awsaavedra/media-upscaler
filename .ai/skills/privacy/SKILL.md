---
name: privacy
description: Personal-data & identity hygiene for anything published, collected, or committed — data minimization, contact/identity choices, consent, PII hiding in repos & metadata. Preventive counterpart to `security` (which *detects/protects* PII); privacy decides whether personal data should be published at all, and by whom. Triggers: /privacy · "contact for the project" · "who do we list" · "is this PII" · "should this be public" · "data minimization" · "author / maintainer field" · a personal email / name / handle about to be committed. Owns the `ship` gate's Privacy stage.
when_to_use: Authoring or auditing anything public — READMEs, community-health files, package metadata, examples / fixtures, logs, telemetry — where a person's identity or data could be exposed. NEVER auto-fill a personal identifier from git config / session context / env. Pairs with `ship` (Privacy stage), `security` (PII detection), `governance` (contacts in community files), `legal` (privacy *policy* → counsel).
---

# Privacy

Decides *whether* personal data should be published, collected, or retained — and by whom. Not *whether it leaked* (that's `security`).

## Boundary — privacy vs security
| | Owns | Nature |
|---|---|---|
| `security` | Is sensitive data protected · did it leak · is it a vuln / compliance gap | Detective, treats PII as a finding to scan for |
| `privacy` (here) | *Should* this personal data exist here · is it minimal · did the person consent · is a **personal** identifier used where a **role** one belongs | Preventive, at authoring time |

A personal email in a public README is not a *secret* (nothing to rotate) and not a code vuln — `security` won't flag it HIGH, yet it's a real privacy harm. Detection / scanning → `security` §Secrets. Privacy *policy* / GDPR / CCPA obligations → `legal` + counsel.

## Iron law — never auto-fill personal identity
The failure this skill exists to stop. Never write a **person's personal identifier** into a published or committed artifact *by default*. The most **available** value is the most **wrong**:
- `git config user.email` / `user.name` — personal by default (this repo's own history carries a personal Gmail + a home hostname).
- Harness / session context (the user's email, name) — background context, **not** a publish authorization.
- `$USER` · `whoami` · env · hostname — leaks a person and often a network / device.

A contact or author field needs an **explicit, purpose-appropriate** value. None available → **STOP and ask the human**. Do not reach for their personal address to fill the blank.

## Contact & identity ladder (take the highest available)
1. Role / project address — `security@…`, `maintainers@…`, a mailing list.
2. Platform channel — GitHub org, issue tracker, Security Advisory, Discussions.
3. A dedicated alias / forwarding address the human chose for the project.
4. *Last resort, explicit consent only* — a named individual, and even then a role alias over a personal inbox.

Never default to: personal Gmail · phone · home address · personal social handle · personal domain.

## What counts as PII (recognize it)
- **Direct** — full legal name · personal email · phone · postal address · gov ID · personal handle / domain · face / voice.
- **Quasi** (re-identify in combination) — title + employer · city + role · precise timestamps · device / hostname · IP · rare attributes. Correlation across public data re-identifies.
- **Sensitive** (extra care, some legally special) — health · biometrics · race / ethnicity · religion · sexual orientation · politics · precise geolocation · financial · children's data.

A personal email **is** PII. So is a commit-author email.

## Data minimization
Publish / collect / log / retain the **least** that serves the stated purpose — applies to what you author *and* what the software does.
- Don't list a contact you don't need · don't add an AUTHORS file of personal emails "for completeness."
- Software: telemetry **off by default / opt-in** · don't log request bodies, IPs, tokens, full user records · set retention limits · purpose-limit collected fields.
- Examples / fixtures / seed data: synthetic only — RFC 2606 domains (`example.com`), `jane@example.com`, `555-0100` numbers. Never a real person's data.

## Publication is permanent and wide
Public + indexed + forked + cached = unrecallable — same reach logic `security` uses for secrets, but personal data has **no rotate**: you can re-issue a leaked key, not someone's identity. So the bar to *author* PII onto a public surface is *higher* than for a secret, and later deletion never reaches existing forks, clones, search indexes, or archives (Wayback).

## Consent & purpose
Publishing a person's identity is the human's decision, not an agent default. Before attributing or listing a contact: is the person aware it will be public · is it the minimal identifier · is there a purpose or is it decoration. Attribution ≠ exposing a personal email — an SPDX `Copyright (c) <year> <holder>` names a holder without a contact address.

## Where PII hides in a repo (sweep these)
- **git commit author** name / email — lives in *history*, survives file edits → `security` §Secrets *Pre-publish* for the scan; a rewrite needs `git-filter-repo` and never reaches existing clones.
- Package metadata `author` / `maintainer` / `email` — `package.json` · `pyproject.toml` · `Cargo.toml` · `*.gemspec` · `composer.json`.
- Community files — `SECURITY.md` reporting contact · `CODE_OF_CONDUCT.md` enforcement contact · `CODEOWNERS` · `AUTHORS` · `.mailmap`.
- Examples / fixtures / seed data / test snapshots / `.env.example` with real values.
- Logs · screenshots · GIFs · sample payloads — tokens, emails, faces, internal URLs / hostnames.
- Issue / PR templates that prompt users to paste personal data.

## Privacy-by-design (software that processes personal data)
Minimize · purpose-limit · retention limits · secure defaults (opt-**in**, not opt-out) · access on need · support erasure / export (DSAR) · surface a **DPIA** trigger for high-risk processing (large-scale sensitive data, tracking, profiling). Detection / protection controls → `security` (GDPR row, §Compliance). This is design hygiene, not a compliance sign-off.

## Boundary — not legal / DPO advice
Engineering hygiene, not a privacy-law opinion. **Privacy-policy / ToS drafting · GDPR / CCPA / DSAR obligations · lawful basis · DPA · cross-border transfer · breach-notification duties · anything with regulatory or contractual exposure → route to counsel / DPO** (see `legal`, which already sends privacy *policies* to counsel). When unsure whether data is publishable, treat it as PII and ask.
