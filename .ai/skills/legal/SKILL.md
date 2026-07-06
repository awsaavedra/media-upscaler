---
name: legal
description: Open-source protective boilerplate + inbound-license compliance — warranty disclaimers, limitation of liability, "AS IS" language, NOTICE / attribution, **dependency & AI-model-weight license compliance (permits use + redistribution)**, trademark & endorsement reservation, export / high-risk / dual-use disclaimers. Drafts standard clauses; never bespoke legal advice. Triggers: /legal · "as is" · "no warranty" · "disclaimer" · "not responsible for your use" · "use at your own risk" · "limitation of liability" · "NOTICE file" · "trademark" · "can I bundle this model" · "what license do the weights use". Pairs with `governance` (which picks the license).
when_to_use: Adding the protective language around a public release, and confirming every third-party dependency **and bundled / auto-downloaded AI model weight** permits the intended use + redistribution — disclaimers, liability caps, attribution, reservations. Distinct from `governance` (license *selection* + community-health files) and `software-engineering` §Documentation (README accuracy). Owns the `ship` gate's legal stage. NOT legal advice — see the hard boundary below.
---

# Legal

The disclaimer / liability / attribution / reservation language that ships *around* a license. Selecting *which* license → `governance`.

## Hard boundary — not legal advice
Reproduces **conventional, public boilerplate**; does **not** practice law. Anything **bespoke, adversarial, or money-on-the-line** → surface the flag, recommend counsel, do **not** improvise: a received legal notice / cease-and-desist / takedown · contracts / commercial licenses / EULAs · patent or trademark filings & disputes · indemnification you *grant* others · privacy policies / ToS / data collection (GDPR / CCPA) · employer or third-party IP ownership · relicensing or copyleft↔permissive incompatibility · a CLA that transfers ownership · "make it legally binding for customers." **When unsure, say "this needs counsel" — wrong boilerplate is worse than none.**

## Warranty disclaimer & limitation of liability ("AS IS")
The two core protections: **disclaim warranties** (no promise it works / fits / is non-infringing) and **cap liability** (you owe nothing for damages from its use). Standard MIT-style text:

> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Two non-obvious rules: **keep the all-caps** — warranty disclaimers must be *conspicuous* to be enforceable (UCC §2-316) · **don't write your own** — every OSI-approved license already contains this (MIT ¶2; Apache-2.0 §§7–8; GPL §§15–16), so a present `LICENSE` already covers you; don't bolt on a second, weaker one that could contradict it.

## When a standalone disclaimer *is* needed
Only for material the license **doesn't reach** — then add a short notice, don't restate the whole license:

| Situation | Add |
|---|---|
| Snippet / gist / doc with no `LICENSE` | One-line license + AS-IS pointer |
| README "results" / benchmark / security claims | "Provided for reference; no warranty of accuracy" |
| Demo, sample config, or generated/AI output | "Example only — review before production use" |
| Dual-use / security tooling | "For authorized testing & education only; you are responsible for lawful use" (pairs with `security`) |
| Fork / vendored copy | Preserve upstream `LICENSE` + `NOTICE`; add your own changes' notice separately |

Reusable README block:

```markdown
## Disclaimer
This software is provided "as is", without warranty of any kind. The authors are
not liable for any damages or for any use of this software. Use at your own risk.
See [LICENSE](LICENSE) for the full terms.
```

## Attribution & NOTICE
**Inbound license terms survive** — copying code obligates you to its attribution, even into a permissive project.
- Preserve every upstream `LICENSE` / copyright header in vendored or copied code.
- `NOTICE` (Apache-2.0 requires it if present upstream) and/or `THIRD_PARTY_LICENSES` — aggregate dependency notices.
- Source headers: `SPDX-License-Identifier: MIT` + `Copyright (c) <year> <holder>` (machine-readable; see `governance`).
- Generate, don't hand-maintain, the dependency list (`pip-licenses`, `cargo about`, `license-checker`, `go-licenses`).

## Third-party license obligations (inbound)
Attribution (above) is necessary but not sufficient — every dependency's license must actually **permit this project's use and redistribution**, and its conditions must be satisfied. Copyleft is viral (see `governance` §License selection for compatibility).
- **Inventory** — enumerate direct + transitive deps with each license (SPDX id). Flag GPL / AGPL / "source-available" / "non-commercial" / "research-only" terms — they constrain bundling and commercial use.
- **Permission, not just notice** — confirm each license allows *this* distribution model; a preserved `NOTICE` does not cure an incompatible obligation (e.g. GPL code inside a permissively-licensed distribution).
- **No relicensing** — never strip, edit, or relabel an upstream license.

## AI model weights — licensed separately from code
Model weights are **not** covered by the wrapping code's license; they carry their own terms, often stricter than the inference code — treat each checkpoint as its own dependency.
- Record every bundled / auto-downloaded weight's source, version, and license; confirm it permits the intended (esp. commercial) use **and redistribution**.
- Watch for research-only, acceptable-use, or output-ownership clauses before bundling weights or shipping their outputs commercially.
- If weights download at setup rather than being committed, state their license + origin in the docs so users inherit the obligation knowingly.

## Trademark & endorsement reservation
A code license is **not** a trademark or publicity grant — state it so forks can't imply you back them:
> "<Name>" and its logo are marks of <holder>; the <license> covers the code, not the marks. This project does not endorse, and is not endorsed by, derivative works.

(Apache-2.0 §6 already reserves trademarks; MIT does not — add the line if the name matters.)

## Other protective clauses (add only if they apply)
- **High-risk use** — disclaim fitness for safety-critical contexts (medical / aviation / nuclear / weapons): "not designed or intended for use in hazardous or life-critical systems."
- **Export control** — for crypto / security tools: "may be subject to export laws (e.g. U.S. EAR); compliance is the user's responsibility."
- **Contributor representation** — `CONTRIBUTING` line: contributors warrant they have the right to submit and license their contribution (DCO `Signed-off-by` captures this — see `governance`).

## Output
```
## Legal review: <project>
Disclaimer        PASS | FAIL — AS-IS / no-liability notice present & not weakened
Dependency terms  PASS | FAIL — every inbound license permits use + redistribution
Model weights     PASS | FAIL — each checkpoint's license recorded & compatible
Attribution       PASS | FAIL — NOTICE / THIRD_PARTY_NOTICES complete
Trademark/content PASS | FAIL — no implied endorsement; user owns outputs
VERDICT: CLEAR | BLOCKED (<obligation unmet>) — counsel review: <items, if any>
```
