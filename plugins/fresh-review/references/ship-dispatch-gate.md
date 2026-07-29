# Ship-side dispatch gate

**Apply this before `/ship` Step 9 and before `/land-and-deploy`'s ship phase.**

`/ship` Step 9 has no "already reviewed?" gate on dispatch. Its only filters are a `DIFF_LINES < 50` floor, scope detection, and an adaptive gate that needs 10+ dispatches at zero findings before it fires. So when a `fresh-review` run just covered the same tree, ship re-pays for the parts that overlap. This file decides which parts, and only those.

It lives here, in the `fresh-review` plugin, rather than in `~/.claude/skills/gstack/**` — `gstack-upgrade` regenerates that tree and would erase it.

## Step 1 — resolve the tier

`/ship` runs in the gstack skill context, where `${CLAUDE_PLUGIN_ROOT}` is unset or points elsewhere, so the script is located explicitly. The first hit wins:

```bash
for c in "${CLAUDE_PLUGIN_ROOT:-/nonexistent}/scripts" \
         "$HOME/ShuratCode-skills/plugins/fresh-review/scripts" \
         "$HOME/.claude/plugins/marketplaces/ShuratCode-skills/plugins/fresh-review/scripts"; do
  [ -f "$c/fr-ship-gate.sh" ] && { bash "$c/fr-ship-gate.sh"; break; }
done
```

The versioned plugin cache (`~/.claude/plugins/cache/ShuratCode-skills/fresh-review/<version>/`) is deliberately **not** in that list — its path changes on every release, so anything pinned to it breaks silently at the next bump. If none of the three resolve, print `FRESH-REVIEW GATE: unavailable (script not found)` and dispatch normally.

Run it from inside the repo. It reads the newest `fresh-review` entry in the branch's gstack review log and prints:

```
FR_GATE: none | tier1 | tier2
FR_REASON / FR_AGE_H / FR_DRIFT / FR_COMMIT / FR_PASSES
CUT_TESTING / CUT_MAINTAINABILITY / CUT_CODEX_REVIEW / CUT_CODEX_ADVERSARIAL: yes | no
```

Act on the four `CUT_*` lines. They already fold in both the tier and which passes actually succeeded, so no further reasoning is needed — and no cut is ever implied by a tier alone.

| Tier | Condition | Cuts |
|---|---|---|
| `none` | no `fresh-review` entry within 24h, or the entry has no `passes` field | nothing |
| `tier1` | entry ≤24h, but the tree drifted or the checkpoint commit is gone | `testing`, `maintainability`, Codex structured review |
| `tier2` | entry ≤24h, checkpoint commit alive, zero drift | tier1 + Codex adversarial |

**`tier1` is the common case, and that is correct.** Ship merges the base branch before Step 9, so HEAD usually differs from the fresh-review checkpoint. Do not tune around it: a drifted tree means the reviewed artifact is not the artifact about to land, and the deeper cuts stop being sound.

## Step 2 — the cuts, and why each is safe

| ship dispatch | what already covered it | cut at |
|---|---|---|
| `testing` specialist (always-on ≥50 lines) | fresh-review Pass A — lattice `test-quality` atom | tier1 |
| `maintainability` specialist (always-on) | fresh-review Pass A — lattice `clean-code` atom | tier1 |
| Codex structured review (`sections/adversarial.md`, 200+ lines) | fresh-review Pass C — literally the same `codex review` at `model_reasoning_effort="high"`. Cutting it also removes a 5-minute blocking call and an `AskUserQuestion` P1 gate from the ship path. | tier1 |
| Codex adversarial `codex exec` (Step 11) | fresh-review Pass C, different framing — adversarial prose vs structured findings. Genuinely a second angle, so it only goes when the tree is provably identical. | tier2 |

Everything else runs. In particular:

| ship dispatch | verdict | why |
|---|---|---|
| `security` specialist | **always keep** | fresh-review's `/cso --diff` gates at 8/10 confidence (2/10 comprehensive); ship's specialist is ungated and surfaces what that drops. Only moderately independent, and both are worth running. gstack tags it `[NEVER_GATE]`. |
| `performance`, `data-migration`, `api-contract` | **always keep** | nothing in fresh-review covers these. It runs no gstack `/review`, by design. |
| Red Team (Step 9.1) | **always keep** | same — no fresh-review pass covers second-order, cross-cutting failures. |
| Step 11 Claude adversarial subagent | **always keep** | not covered by any fresh-review pass. |
| Step 9 checklist critical pass | **always keep** | cheap, and not a subagent. Overlaps lattice `secure-coding` and `/cso` only partially. |
| design-lite / `design` specialist / Codex design voice | **always keep** | fresh-review has no design lens at all. |
| Greptile, Step 7 coverage audit, Step 9.3 finding dedup | **always keep** | no overlap. Step 9.3 is the findings-level half of the handoff and is what suppresses already-triaged findings. |

## Step 3 — announce every cut

Print the cuts in the same output that would have listed the dispatch, next to ship's own "Dispatching N specialists…" line. Never trim silently.

```
FRESH-REVIEW GATE: tier1 (tree drifted 3 paths, review 0.4h old)
  cut: testing, maintainability (covered by fresh-review lattice pass)
  cut: codex structured review (covered by fresh-review codex pass)
  keeping: security, performance, data-migration, api-contract, red-team, codex adversarial
```

On `FR_GATE: none`, print one line naming the reason and dispatch normally.

## Invariants

These are not tuning knobs. Each exists because loosening it converts a duplicated-work saving into a missing lens:

- **Never widen the 24h window.** Older than that and the codebase, the dependencies, or the reviewer's calibration have all moved.
- **Never accept nonzero drift for `tier2`.** Drift counts committed changes *and* uncommitted ones — any dirty file forces `tier1`. The Codex adversarial pass is the only thing that turns on this, and it is worth re-running whenever the tree is not provably identical.
- **Never infer a pass ran.** An entry with no `passes` field resolves to `none`, not to a guessed pass list. Old `schema:2` entries lack the field and expire from the window within a day, so this is self-healing.
- **Verify with git, never with mtimes.** `find -newermt` is unreliable on this machine; `fr-ship-gate.sh` uses `git cat-file`, `git diff --name-only`, and `git status --porcelain` throughout.
- **A cut is never implied by the tier alone.** `CUT_TESTING` is `yes` only if `lattice` is in `FR_PASSES`; the Codex cuts only if `codex` is. A failed fresh-review pass must not remove ship's coverage for it.

## Known intra-ship redundancy (not addressed here)

Red Team (Step 9.1) and the Claude adversarial subagent (Step 11) are the same model with the same adversarial framing in the same run. Both are kept above, because deduplicating them is a change to ship's own design rather than a fresh-review overlap, and this gate deliberately only cuts what fresh-review actually covered.
