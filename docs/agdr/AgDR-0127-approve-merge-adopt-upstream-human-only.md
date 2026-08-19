---
id: AgDR-0127
timestamp: 2026-08-19T00:00:00Z
agent: Claude (Opus 5)
model: claude-opus-5
trigger: user-prompt
status: executed
supersedes: AgDR-0125 (third leg only — `/approve-merge` record-only)
---

# Adopt upstream's human-only `/approve-merge` instead of the fork's record-only split

> In the context of re-grafting this fork onto framework v5.4.0, facing a fork
> decision (AgDR-0125) that made `/approve-merge` record-only so Claude could
> never execute a merge, I decided to drop that leg and adopt upstream's design —
> `disable-model-invocation: true` plus merge-in-the-same-turn — to achieve the
> same guarantee mechanically rather than procedurally, accepting that the merge
> now runs in the same turn as the approval.

## Context

[AgDR-0125](AgDR-0125-rex-md-reviews-and-manual-merge.md) (originally AgDR-0015)
made three changes together. Two remain live and are still being re-grafted:

1. Rex writes markdown reviews to `projects/<name>/code-reviews/` instead of
   posting to the PR.
2. The merge gate requires the CEO marker alone, not a Rex marker.
3. **`/approve-merge` writes the CEO marker but does NOT run `gh pr merge`.**

Leg 3 existed for one reason: *Claude must never be the thing that executes a
merge.* At v4.3.0 the only lever available was to remove the merge call from the
skill, leaving the human to run `gh pr merge` themselves.

Upstream has since solved the same problem differently. As of v5.4.0
(me2resh/apexyard#1042, AgDR-0110), the approval skills carry
`disable-model-invocation: true` — **the model cannot invoke them at all** — and
`/approve-merge` performs the merge in the same turn once a human invokes it.
The mirror half matters too: the *review* skills were unlocked, so the
orchestrator can start a review, which is what makes the review a separate
sub-agent pass rather than the author grading their own work.

## Options Considered

| Option | Pros | Cons |
|--------|------|------|
| **A. Adopt upstream (chosen)** | The guarantee becomes mechanical: the model *cannot* invoke the skill, so it cannot merge — enforced by the harness, not by the absence of a line of code. Zero divergence on a file upstream changes often. Keeps the review/approval invocability pair coupled, which upstream pins with `test_skill_invocability_gates.sh`. | Merge runs in the same turn as approval, so there is no pause between "approved" and "merged". |
| B. Re-graft leg 3 | Preserves the extra beat between recording approval and merging. | Strictly more friction for the same guarantee, and it diverges on a file that upstream revises most releases — meaning a conflict every sync, forever, to re-remove one call. Worse: it would leave the *procedural* protection in place while the mechanical one already exists, which reads as belt-and-braces but is actually just the braces. |
| C. Adopt upstream, then also remove the merge call | Both. | The two are coupled upstream by a test. Unlocking or relocking one side alone is exactly what that test exists to catch. |

## Decision

Chosen: **Option A**, because the fork's stated intent — "Claude never merges" —
is now enforced *more strongly* by upstream than by the fork's own workaround.

Leg 3 was a procedural control: the merge call was absent, so it could not run.
Nothing prevented a future edit from putting it back, and nothing prevented the
model from running `gh pr merge` directly. Upstream's `disable-model-invocation`
is a harness-level control on the *invocation* — the model cannot trigger the
approval path at all, whatever the skill body contains. That is the property leg
3 was reaching for.

The "no pause between approval and merge" cost is real but small, and upstream
argued it directly (see `pr-workflow.md` § "Plan-level 'go' is NOT merge
approval"): by the time the skill runs, a human has explicitly named the PR, both
markers are on disk with matching SHAs, and the mechanical gates will refuse
anything inconsistent. The discrete human moment is the *invocation*, and that
moment is preserved.

**Legs 1 and 2 of AgDR-0125 are NOT superseded** and are still to be re-grafted
(divergence register § 5b.9).

## Consequences

- `/approve-merge` is taken from upstream unmodified. One fewer file to re-assert
  every sync, and one fewer conflict.
- A human must type `/approve-merge <pr>`; saying "approved" in prose is no
  longer sufficient on its own, and the model cannot substitute for it.
- Do **not** unlock the review skills or relock the approval skills
  independently — `test_skill_invocability_gates.sh` pins both, and the pair is
  what prevents a fully autonomous open → review → approve → merge path.
- If upstream ever reverts `disable-model-invocation`, this decision must be
  revisited immediately: the mechanical control disappears and leg 3 becomes the
  only protection again.

## Artifacts

- Ticket: `andrewa28/apexyardv2-portfolio#3`
- Supersedes the third leg of [AgDR-0125](AgDR-0125-rex-md-reviews-and-manual-merge.md)
- Upstream rationale: `.claude/rules/pr-workflow.md` § "The approval skills are human-only (#1042, AgDR-0110)"
