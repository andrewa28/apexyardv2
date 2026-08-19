# Rex writes markdown reviews; Claude no longer executes merges

> In the context of the apexyard code-review and merge-gate machinery, facing the friction of Rex's reviews living only on GitHub PR pages (lost to managed-project privacy boundaries, not browsable across the portfolio) and the residual risk of Claude auto-executing `gh pr merge` via `/approve-merge`, I decided to (1) replace `gh pr review` posting with markdown files at `projects/<name>/code-reviews/<pr>-<sha>.md` in the apexyard ops repo, (2) drop the Rex approval marker from the merge gate, and (3) make `/approve-merge` record-only (write CEO marker, do not call `gh pr merge`) — accepting that the merge gate now relies on a single mechanical signal (CEO marker) and that Rex's review is no longer visible inside the GitHub PR thread.

## Context

The current Rex flow:

- Rex posts every review as a `gh pr review --comment/--approve/--request-changes --body "..."` on the target PR.
- Rex also writes a bare-SHA marker at `.claude/session/reviews/<pr>-rex.approved`.
- `block-unreviewed-merge.sh` requires BOTH the Rex marker AND the CEO marker to let a merge through.
- `/approve-merge <pr>` writes the CEO marker AND immediately runs `gh pr merge`.

Two problems with this:

1. **Reviews are siloed inside each managed project's GitHub PR thread.** The apexyard portfolio model centralises per-project docs (handover, roadmap, updates) under `projects/<name>/` — but reviews escape that convention. For split-portfolio adopters (public framework + private portfolio), Rex's GitHub comments leak project-internal review content to the managed project's GitHub history rather than the private portfolio repo.

2. **Plan-level "go" can still cascade into a merge.** Even with `.claude/rules/pr-workflow.md` § "Plan-level go is NOT merge approval" + the structured CEO marker (#48), having Claude execute `gh pr merge` keeps merges one tool-call away from any agent loop. The "discrete moment per merge" rule is enforceable but socially fragile.

This AgDR records the decision to fix both at once.

## Options Considered

| Option | Pros | Cons |
|---|---|---|
| (A) Keep current flow | Zero churn. Rex marker + CEO marker is a defence-in-depth gate. | Reviews stay siloed; Claude still merges. |
| (B) Rex writes md only, keep marker | Reviews centralised under `projects/<name>/code-reviews/`. Two-marker gate preserved. | Marker no longer reflects an action Rex took on the PR — it's a side-effect of a file write, not a "this PR was reviewed" signal in any human-visible sense. The marker becomes ceremony. |
| (C) Rex writes md only, drop Rex marker, keep `/approve-merge` auto-merging | Reviews centralised. Gate simplified to one marker. | Claude still executes merges. |
| (D) **Rex writes md only, drop Rex marker, `/approve-merge` record-only** | Reviews centralised. Gate simplified. Claude never merges (manual `gh pr merge` by operator). | Single mechanical gate (CEO marker only). Adopters must manually run `gh pr merge` after approval. |
| (E) Remove the entire merge gate | Maximum simplicity. | Discards #47 (gh api bypass closure) and #48 (structured CEO marker) without a replacement. Plan-level "go" would merge with no backstop. |

## Decision

Chosen: **(D)**, because:

- **Centralised reviews under `projects/<name>/code-reviews/<pr>-<sha>.md`** keep Rex's output inside the apexyard portfolio convention — same place handover and roadmap live. Split-portfolio adopters get private-by-default review storage automatically.
- **Dropping the Rex marker** removes a signal that no longer means what it claimed to mean. Under the new flow, a Rex marker written purely as a side-effect of file creation is ceremony, not safety — strictly worse than not having one.
- **`/approve-merge` becomes record-only** because the value of the discrete-approval moment is the CEO marker artifact (the record of explicit per-PR authorization), not the merge command itself. Decoupling them means an operator who isn't ready to merge can still record the approval, and the operator who runs `gh pr merge` is unambiguously the human.
- **Single CEO marker** is sufficient defence given that `block-unreviewed-merge.sh` covers all four merge shapes (gh pr merge, gh api .../merge, az repos pr update, MCP repo_update_pull_request), the structured-marker format from #48 makes forgery a visible rule violation, and per-PR-naming is enforced at the `/approve-merge` skill entry point.

## Consequences

- `block-unreviewed-merge.sh` Rex-marker check block deleted; CEO-marker block unchanged.
- `.claude/agents/code-reviewer.md` rewritten: `gh pr review` mandate replaced with md-file mandate; marker-writing section deleted.
- `.claude/skills/code-review/SKILL.md` Output section rewritten to describe the md artefact.
- `.claude/skills/approve-merge/SKILL.md` `gh pr merge` invocation deleted; skill prints "marker written, merge manually" on completion.
- `.claude/skills/approve-design/SKILL.md` Rex-marker prereq deleted (design marker stands alone now).
- `.claude/rules/pr-workflow.md` "Mechanical enforcement" section updated: one marker instead of two; CEO marker described as the sole gate input.
- `.claude/agents/pr-manager.md` `gh pr merge` step stripped — consistent with "Claude never merges".
- `golden-paths/pipelines/review-check.yml` left as-is (template for adopters who copy from it — under the new flow it would never pass, so adopters must edit or delete it on copy). Documented in the file's comment.
- Existing `.claude/session/reviews/*-rex.approved` files in flight are harmless — hook no longer reads them.
- **Adopters on managed projects with `gh pr merge` muscle memory unchanged** — they still run the same command; only the CEO marker is required.
- **Rex's review is no longer visible inside the GitHub PR thread.** Operators must browse `projects/<name>/code-reviews/` to read reviews. This is a deliberate trade for centralisation + privacy.
- **#48 structured-marker rationale unchanged** — the CEO marker keeps the same `sha=/approved_by=user/skill_version=` shape; forgery remains a visible rule violation.
- **#47 (gh api bypass) unchanged** — all four merge shapes still gated.

## Artifacts

- Plan: local plan file (per-machine, not published)
- Implementation: this branch
- Related: AgDR-0012 (approve-merge streamline), me2resh/apexyard#47 (gh api bypass), me2resh/apexyard#48 (structured CEO marker)

---

*Renumbered from **AgDR-0015** when this fork moved to framework v5.4.0. Upstream
now ships its own AgDR-0015, so the original number collided. Numbering for
fork-owned records starts above upstream's highest (0122) — see
[`docs/upstream-sync-playbook.md`](../upstream-sync-playbook.md) § 5.*

---

> **Partially superseded — third leg only.**
> [AgDR-0127](AgDR-0127-approve-merge-adopt-upstream-human-only.md) drops the
> "`/approve-merge` is record-only" leg in favour of upstream's
> `disable-model-invocation: true`, which enforces "Claude never merges"
> mechanically rather than by omitting the merge call. **Legs 1 and 2 — Rex
> writes markdown reviews, and the merge gate needs the CEO marker alone — still
> stand and are pending re-graft.**
