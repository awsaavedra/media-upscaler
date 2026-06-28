---
name: legal
description: Liability, warranty, and third-party-license compliance skill — "AS IS" / no-warranty / limitation-of-liability notices, dependency & AI-model-weight license obligations, attribution / NOTICE files, export & trademark hygiene. Triggers: /legal · "as is" · "disclaimer" · "not liable" · "warranty" · "can I bundle this model" · "what license do the weights use" · "attribution". Owns the `ship` gate's legal stage. Pairs with `governance` (project license) — governance picks the outbound license, legal verifies inbound obligations and disclaims liability.
when_to_use: Taking a project public or distributing binaries / bundled models — disclaiming warranty & liability, and confirming every third-party dependency and model weight permits the intended use & redistribution. Not legal advice — route real questions to counsel.
---

# Legal

Distribution-liability gate. Confirms the project disclaims warranty / liability and honors every inbound license before it ships. **Not legal advice — escalate anything non-obvious to counsel.**

## Warranty & liability disclaimer
Ship with an explicit, conspicuous notice — the standard OSI licenses already carry it (MIT / BSD / Apache-2.0 §7–8 include "AS IS", no warranty, and limitation of liability). If the project license provides it, do **not** restate or weaken it; if a README/usage doc makes claims, add a short pointer back to the license.

- **No warranty** — "Provided **AS IS**, without warranty of any kind, express or implied (merchantability, fitness for a particular purpose, non-infringement)."
- **No liability** — "In no event shall the authors be liable for any claim, damages, or other liability arising from the use of the software."
- **Use at your own risk** — for tools that modify user data, drive GPUs/hardware, or call external services, state the operational risk plainly (e.g. "may overwrite files in the output directory", "runs your GPU under sustained load").

## Third-party license obligations (inbound)
Every dependency's license must permit the intended **use and redistribution**, and its conditions must be satisfied. Copyleft is viral (see `governance` §License selection for compatibility).

- **Inventory** — enumerate direct + transitive deps and each license (SPDX id). Flag GPL/AGPL/“source-available”/“non-commercial”/“research-only” terms — they constrain bundling and commercial use.
- **Attribution** — permissive licenses (MIT/BSD/Apache) require retaining copyright + license text. Collect them into a `THIRD_PARTY_NOTICES` / `NOTICE` file. Apache-2.0 requires propagating any upstream `NOTICE`.
- **No relicensing** — never strip, edit, or relabel an upstream license.

## AI model weights — licensed separately from code
Model weights are **not** covered by the wrapping code's license; they carry their own terms, often stricter than the inference code.

- Treat each bundled / auto-downloaded checkpoint as a dependency: record its source, version, and license, and confirm it allows the intended (esp. commercial) use and redistribution.
- Some weights are research-only or carry acceptable-use / output-ownership clauses — check before bundling or shipping outputs commercially.
- If weights are downloaded at setup rather than committed, state their license and origin in the docs so users inherit the obligation knowingly.

## Export, trademark & content
- **Trademark** — a code license is not a trademark license; don't imply endorsement or reuse upstream marks/logos without permission.
- **Export / crypto** — flag strong-crypto or controlled-tech for export review (rare for media tooling, but check).
- **Generated content** — if the tool produces or transforms user content, don't assert ownership over the user's outputs.

## Output
```
## Legal review: <project>
Disclaimer        PASS | FAIL — AS-IS / no-liability notice present & not weakened
Dependency terms  PASS | FAIL — all inbound licenses permit use + redistribution
Attribution       PASS | FAIL — NOTICE / THIRD_PARTY_NOTICES complete
Model weights      PASS | FAIL — each checkpoint's license recorded & compatible
Trademark/content PASS | FAIL — no implied endorsement; user owns outputs
VERDICT: CLEAR | BLOCKED (<obligation unmet>) — counsel review: <items, if any>
```
