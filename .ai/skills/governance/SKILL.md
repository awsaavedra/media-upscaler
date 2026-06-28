---
name: governance
description: Open-source governance and community-health skill — license selection, CONTRIBUTING / CODE_OF_CONDUCT / SECURITY.md, coordinated disclosure, issue & PR templates, contribution licensing (DCO / CLA), triage. Triggers: /governance · "what license" · "add a license" · "CONTRIBUTING" · "code of conduct" · "security policy" · "how do I take vuln reports". Owns the `ship` gate's governance stage.
when_to_use: Taking a project public or standing up its community infrastructure — choosing a license, authoring community-health files, setting a disclosure process. Pairs with `ship` (governance stage), `security` (disclosure handling), `software-engineering` §Documentation. Not legal advice.
---

# Governance

## License selection
Pick one; put `LICENSE` at the repo root; add SPDX headers (`SPDX-License-Identifier: …`) to sources.

| Goal | License |
|---|---|
| Max adoption, minimal terms | MIT / BSD-2/3 |
| Permissive + explicit patent grant | Apache-2.0 |
| Library copyleft (link freely) | LGPL / MPL-2.0 (file-level) |
| Share-alike for distributed binaries | GPL-3.0 |
| Share-alike incl. network / SaaS use | AGPL-3.0 |

Rules: the license must be **compatible with every dependency's** license — copyleft is viral, pulling GPL into a permissive project relicenses the combination · one canonical license · don't invent or edit license terms · **not legal advice — route licensing / patent / trademark questions to counsel.**

## Community-health files
- `README` — what / why, install, quickstart, license, links (see `software-engineering` §Documentation).
- `CONTRIBUTING.md` — build, test, branch / PR flow, commit convention, definition of done.
- `CODE_OF_CONDUCT.md` — adopt Contributor Covenant; name an enforcement contact.
- `SECURITY.md` — supported versions + the **private** reporting channel (see disclosure below).
- `.github/` — issue + PR templates, `CODEOWNERS` for review routing.

## Contribution licensing
Inbound = outbound by default (contributions under the project license). For provenance pick one and state it in `CONTRIBUTING`: **DCO** (`Signed-off-by`, lightweight) or **CLA** (explicit grant, higher friction).

## Coordinated disclosure
Cross-links `security`. Never accept vulnerabilities in public issues. Flow: private intake (security@ / GitHub Security Advisory) → acknowledge within a stated SLA → triage + reproduce → fix under embargo → coordinated release + advisory (credit reporter, assign CVE) → public disclosure. Document the channel and response time in `SECURITY.md`.

## Triage
Labels (type / priority / `good-first-issue`) · stated response expectations · stale policy · a decision model (BDFL vs. maintainer team) once the project outgrows a single owner.
