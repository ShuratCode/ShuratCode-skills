# fresh-review — Pass K (risk)

Read this at Step 5 when Pass K is in the batch (`pr` mode). Its prompt is the SKILL.md Step 5 isolation contract, verbatim, with the task below in place of its return-format block.

**Pass K — risk** (pr mode only; no nested skill, this is a direct assessment task)

The critics answer *is this correct* and Pass U answers *what is this*. Pass K answers *how much would it hurt if this is wrong* — a single `low` / `med` / `high` class for the change as a whole, so the human reads the verdict already knowing the stakes. gstack ships no standalone risk framework — its `/review` scores per-finding *confidence*, not change-level *blast radius* — so this pass uses the rubric below, which is fresh-review's own. It runs alongside the critics, under the same isolation contract, and reports **exactly one** risk class plus the factors behind it. It reports no code-quality findings and never enters triage; its output is the risk header, not a bucket.

It is handed one prior: the mechanical `RISK` from `fr-packet.sh` (`normal` or `high`, from pattern counts over the patch). Treat it as a floor to argue up from, not a verdict — a `normal` mechanical class can still be `high` if the *reachability* of the change is severe, and a `high` mechanical class can settle at `med` once you read what the touched auth path actually guards. Append this to the isolation contract, replacing its return-format block:

> Your job is not to find defects and not to describe the change — other passes do those. Your job is to classify **how much damage a latent bug in this change could do**, as one of `low`, `med`, `high`, and to name the factors that set that class. Read `diff.patch`; open a source file from `{{SOURCE_ROOT}}` only to judge how far a change reaches (what calls the touched code, what it guards, whether it is behind a flag). Do not judge whether the code is *correct* — assume it might be wrong and ask *what then*.
>
> Weigh these factors. Each is `low` / `med` / `high` on its own; the overall class is driven by the **worst** that is genuinely in play, not an average — one `high` blast-radius factor makes the change at least `med` even if everything else is `low`.
>
> - **Blast radius** — how much depends on the touched code. A leaf utility used in one place is `low`; a shared library, a base class, or a hot path many callers reach is `high`.
> - **Reversibility** — how cleanly a bad outcome can be undone. A pure code change reverted by a redeploy is `low`; a database migration, a data backfill, or a destructive/irreversible operation is `high`.
> - **Security & data surface** — whether the change touches authentication, authorization, secrets, payment, PII, or a trust boundary. Any of those present is at least `med`, and `high` when the change *weakens* a check rather than merely sitting near one.
> - **Coupling & breadth** — how many distinct modules or public contracts move together. A single self-contained unit is `low`; a change that alters an API/event/schema other teams consume is `high`.
> - **Operational surface** — infra, CI/CD, deploy config, feature flags, rollout. A change that can take the pipeline or environment down is `high`; behind an off-by-default flag pulls the *effective* class down and you must say so.
> - **Test coverage of the touched paths** — whether the changed code has tests exercising it *in this diff or already present*. Well-covered lowers the class; a high-blast change with no test touching it raises it.
>
> Return *only* this block:
>
> ```
> PASS: risk
> STATUS: ok | partial | failed
> RISK_LEVEL: low | med | high
> ---
> FACTORS
> - blast-radius: <low|med|high> — <one line>
> - reversibility: <low|med|high> — <one line>
> - security-data: <low|med|high> — <one line>
> - coupling-breadth: <low|med|high> — <one line>
> - operational: <low|med|high> — <one line>
> - test-coverage: <low|med|high> — <one line>
> ---
> RATIONALE: <one or two sentences — which factor(s) set the overall class, and why it is not a step lower>
> ---
> NOTES: <at most two lines, only if something anomalous happened>
> FILES_READ: <comma-separated paths you opened>
> ```

Two things about this pass:

- **The overall class is the worst live factor, not the mean.** Averaging is how a migration behind five safe factors gets called `low`. A reader glances at one word; that word has to reflect the thing that can actually hurt them, which is the maximum, not the middle.
- **It classifies the change, not the code's quality.** A beautifully-written change to the payment path is still `high`; a sloppy change to a debug log is still `low`. Risk is about consequence-if-wrong, and it is deliberately orthogonal to whether the critics found anything — a `high`-risk change with zero findings is exactly the case worth flagging as "clean, but tread carefully."

## Failure mode

- **Pass K fails or is not returned** → the run is not blocked. Print the header risk as the mechanical class with ` (mechanical — risk pass failed)`, drop the `risk —` rationale and factor lines, keep the `risk` pass in the log with `"status":"failed"`, and continue. Risk is context for the verdict, never a gate on it.
