# Upstream Sync Playbook — merging `me2resh/apexyard` into this fork without losing local work

**Fork-local doc** (not from upstream). Written after the v1.2.0 → v4.3.0 sync
(PR #5, 2026-07-07), which merged 80 upstream commits across three major
releases while preserving 11 local commits plus uncommitted work. This is the
repeatable procedure for every future `/update`, plus the traps that sync hit.

The `/update` skill (`.claude/skills/update/SKILL.md`) is the frame; this doc
is the fork-specific overlay: what diverges on purpose, how to resolve
conflicts without losing either side, and how to green the CI afterwards.

---

## 0. Why our syncs conflict (and why the next one is easier)

This fork carries **deliberate divergences** (§ 5). Every sync will conflict on
those files — that is expected and fine. The v4.3.0 sync was uniquely painful
because the v1.2.0 sync had been merged through a fork PR with **rewritten
SHAs**, so git's merge-base was near the repo root and 108 files conflicted.
The v4.3.0 sync merged `upstream/main` directly, so **future merge-bases are
recent** and conflicts should be limited to the divergence register in § 5.

## 1. Pre-flight — make loss impossible before touching anything

Work is only safe once it is a git object on a ref. In order:

```bash
git fetch upstream --quiet
git rev-list --left-right --count main...upstream/main   # how far behind?

# 1. Bootstrap marker so the ticket-first hook exempts the sync work
mkdir -p .claude/session && echo "update" > .claude/session/active-bootstrap

# 2. Snapshot committed state
git branch backup/pre-sync-main main

# 3. Tracking issue in the fork (Chore template: Driver/Scope/Acceptance Criteria)
gh issue create --repo andrewa28/apexyard --title "Chore: sync ops fork with upstream apexyard vX.Y.Z" --body "..."

# 4. Sync branch — NEVER commit on main (block-main-push.sh blocks it)
git checkout -b "chore/#<N>-sync-upstream-apexyard"

# 5. Commit ALL uncommitted work as WIP commits on the sync branch
#    (git add specific paths — never -A; git commit -F <file> for multi-line)
# 6. Snapshot again, now including the WIP
git branch backup/pre-merge
git status --porcelain   # MUST be empty before the merge
```

Rollback at any later point: `git merge --abort`, or reset the sync branch to
`backup/pre-merge`. Keep both backup refs until the PR is merged and verified.

**Traps at this stage:**

- `check-secrets.sh` false-positives on checklist prose containing
  `apiKey="..."`-shaped text. It inspects the *staged* diff at PreToolUse time,
  so `git add fix && git commit` in ONE command still sees the old staging —
  stage the fix in its own command first. Reword the offending text
  (e.g. `"apiKey" + "="`) rather than bypassing the hook.
- `.gitignore` has a bare `projects` entry, so staging files under
  `projects/**` (all tracked) needs `git add -f`.

## 2. Read upstream's breaking changes BEFORE merging

```bash
git show upstream/main:CHANGELOG.md | grep -n -A 8 '### Breaking'
```

Check each against the divergence register (§ 5). Also scan for structural
moves (files deleted/renamed upstream that we track — `onboarding.yaml` and
`site/` both moved/vanished in v3–v4).

## 3. Merge and classify — don't resolve 100 files by hand

```bash
git merge upstream/main --no-edit    # merge, NEVER rebase
```

Then classify every conflicted file by one question: **did WE actually change
it since the last sync?** Compare our conflict stage against the last-sync
content:

```bash
LAST_SYNC=<merge commit of the previous sync>   # v4.3.0 sync: 61b42cf
git ls-files -u                                  # stage 2 = ours, stage 3 = theirs
# ours blob == LAST_SYNC blob  →  we never touched it  →  take upstream:
git checkout --theirs -- <file> && git add -f -- <file>
```

That resolved 79/108 files mechanically in the v4.3.0 sync. For files we DID
change, re-merge with the **correct base** (the last-sync content, not git's
merge-base) — this auto-resolves everything non-overlapping:

```bash
git show "$LAST_SYNC:$f" > /tmp/base; git show ":2:$f" > /tmp/ours; git show ":3:$f" > /tmp/theirs
git merge-file -p /tmp/ours /tmp/base /tmp/theirs > "$f"   # rc>0 = real overlap
```

What's left after that is the genuine overlap set — hand-merge per § 4.

## 4. Resolution bias per file class

| Class | Files (typical) | Resolution |
|---|---|---|
| **Fork-owned** | `onboarding.yaml`, `apexyard.projects.yaml`, `projects/**`, `.gitignore` fork entries, CLAUDE.md fork sections | **Local wins.** Graft upstream structure only where useful. |
| **Policy-divergent framework files** | merge gate, approve-merge/design skills, code-reviewer agent (§ 5) | **Upstream's new structure + re-graft our policy.** Do NOT keep-ours wholesale: sibling hooks/skills evolve together upstream (e.g. marker paths), and keep-ours breaks cross-file consistency. |
| **AzDO-customized hooks** | `_lib-extract-pr.sh`, gate hooks, `validate-pr-create.sh`, `verify-commit-refs.sh`, `settings.json` | **Not applicable on `main` yet — see § 5b.8.** None of these carry AzDO dispatch today, so there is nothing to re-insert and nothing to grep for. Once the re-graft lands, the blocks are comment-marked; grep for `Azure DevOps` in `.claude/hooks/`. Until then, treat this row as a forward-looking note, not an instruction. |
| **Docs with AzDO appendices** | rules/*.md, workflows/*.md | Union: our appendix + upstream's additions/footer. |
| **Untouched by us** | everything else | Upstream wins. |

After each file: `bash -n` for shell, `jq empty` for JSON, then `git add -f`.
For `settings.json`, prefer a scripted JSON transform (load upstream's version,
insert our matcher entries programmatically) over hand-editing — see the
`az repos pr update` / `mcp__azure-devops__repo_update_pull_request` /
`rex-prepush-advisory` entries that must survive every sync.

## 5. Fork divergence register — re-assert these EVERY sync

Every entry carries a **grep signature**: one command that answers "is this
divergence still in place?" after a merge. Run them all in step 6. A divergence
with no signature is one you will lose silently.

Rewritten 2026-08-19 for the move to a **public fork + private portfolio repo**
on framework v5.4.0. That move **dissolved four of the previous eight entries** —
they are listed at the bottom so nobody helpfully re-adds them.

### 5a. Live — shipped and must survive every sync

1. **`projects/README.md` is untracked.** Per-project docs live in the private
   portfolio repo, so upstream's in-fork placeholder describes a layout this fork
   does not have.
   - Signature: `git ls-files --error-unmatch projects/README.md 2>/dev/null && echo VIOLATED || echo ok`

2. **`workspace/README.md` is KEPT.** Deliberately *not* removed, per
   [AgDR-0021](https://github.com/me2resh/apexyard/blob/main/docs/agdr/AgDR-0021-split-portfolio-v2-path-resolution.md)
   § G, which decided this exact question for the v2 layout and rejected removal.
   Note this contradicts upstream's own `/setup` SKILL.md:159, which instructs
   untracking it — the AgDR and the two assertions in
   `test_split_portfolio_v2_migration.sh` are the stronger authority. **Worth
   reporting upstream rather than patching locally.**
   - Signature: `git ls-files --error-unmatch workspace/README.md >/dev/null && echo ok || echo VIOLATED`

3. **Split-portfolio ignore rules**, anchored to the fork root. `/projects/` and
   `/apexyard.projects.yaml` are anchored deliberately — the unanchored `projects`
   also shadowed the tracked framework skill dir `.claude/skills/projects/`.
   - Signature: `grep -qx '/projects/' .gitignore && grep -qx '/apexyard.projects.yaml' .gitignore && echo ok || echo VIOLATED`

4. **Private skill names live in `.git/info/exclude`, never `.gitignore`.**
   Enumerating them in a tracked file would publish the adopter's private skill
   names in a public repo — the exact thing this layout protects. A glob cannot
   target them either (they sit among ~70 tracked framework skill dirs).
   `bin/link-rex-data.sh` regenerates the list at runtime from the private
   `custom-skills/` dir, so a fresh clone is covered and adding a skill needs no edit.
   - Signature — **derives the names at runtime; do not hardcode them here.**
     An earlier version of this line listed three skill names literally, which
     meant the check for the leak *was* the leak: it put private names in a
     tracked file in a public repo. It also silently rotted, covering only the
     skills that existed the day it was written.

     ```bash
     # Anchor on the fork root via the git COMMON dir, so this works from a
     # subdirectory and from inside a linked worktree (`isolated-builds.md`
     # prescribes worktrees, so "only correct at the fork root" means "wrong
     # exactly where you work"). `portfolio.registry` is fork-root-relative.
     _root=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
     _cfg="$_root/.claude/project-config.json"
     if [ ! -f "$_cfg" ]; then
       echo "CANNOT VERIFY — no project-config.json (untracked by design, AgDR-0122). Restore it and re-run."
     else
       _cs=$(cd "$_root" && cd "$(dirname "$(jq -r '.portfolio.registry' "$_cfg")")" 2>/dev/null && pwd)/custom-skills
       _names=$(ls "$_cs" 2>/dev/null | grep -v '^README' | paste -sd'|' -)
       if [ -z "$_names" ]; then
         echo "CANNOT VERIFY — private custom-skills dir not reachable at $_cs"
       elif git -C "$_root" grep -qE "$_names"; then echo VIOLATED
       else echo ok; fi
     fi
     ```

     **`CANNOT VERIFY` is not a pass.** An earlier version printed `SKIP` on
     both of those branches, which reads like a clean result — so the check
     failed open precisely when it mattered: in a worktree, and on a fresh
     clone or in CI where `project-config.json` is absent. A leak check that
     cannot run in a fresh clone cannot verify the state you actually publish.
     (`git grep` is tracked-only already, so no `-- $(git ls-files)` splice —
     that form also breaks on paths with spaces.)

5. **`bin/link-rex-data.sh` exists and is fork-owned.** Symlinks the private
   repo's Rex learned data into `.claude/` and maintains the exclude list. Not an
   upstream file; a sync will never touch it, but a `git clean` would.
   - Signature: `[ -x bin/link-rex-data.sh ] && echo ok || echo VIOLATED`

6. **`.gitignore` fork entries** — `.DS_Store`, `.claude/tmp/`, and the Rex
   learned-data paths (`.claude/rex-*`, `.claude/pr-docs-index.json`).
   - Signature: `grep -q '\.claude/rex-review-journal\.md' .gitignore && echo ok || echo VIOLATED`

7. **AgDR numbering starts above upstream's highest.** Fork-owned records are
   AgDR-0123+ (upstream v5.4.0 ships up to 0122). Before adding one, check
   `ls docs/agdr/ | sort -V | tail`. The 0014/0015/0082 trio was renumbered to
   0124/0125/0126 during the v5.4.0 move because upstream had since claimed all
   three numbers — the same collision will recur on any sync that adds AgDRs.
   - Signature (scoped to **0123+**, deliberately):
     `ls docs/agdr/ | grep -oE 'AgDR-[0-9]+' | awk -F- '$2+0 >= 123' | sort | uniq -d | grep -q . && echo VIOLATED || echo ok`
   - **Do not widen this to all numbers.** Upstream v5.4.0 already ships a
     duplicate of its own — `AgDR-0095` exists twice
     (`conformance-ci-badge` and `premium-hook-safe-fallback-harness`). An
     unscoped check reports VIOLATED on a clean fork and trains you to ignore it.
     Upstream's numbering is upstream's problem; this entry guards *ours*.
     (Worth reporting upstream; not worth patching locally.)

### 5b. Pending — re-graft NOT yet complete

These shipped in the previous fork (v4.3.0) and are **not yet re-grafted** onto
v5.4.0. Until each lands, the behaviour it provided is simply absent — do not
assume the framework is enforcing it.

8. **Azure DevOps mechanical enforcement — NOTHING of this is on `main`.**
   Be precise about the state, because the failure mode here is a re-grafter
   assuming a foundation exists and building on air:
   - `_lib-extract-pr.sh` on `main` is **upstream-stock, with zero AzDO
     awareness**.
   - `_lib-resolve-ticket.sh` **does not exist in the tree**.
   - `settings.json` carries **no** `az repos` matchers.
   - `git grep -ilE 'az repos|azuredevops|az boards' -- .claude/` returns nothing.

   A detection layer plus the forked resolver are written and reviewed on the
   unmerged `chore/GH-1-azdo-merge-shape-ticket-resolution` branch, along with
   AgDR-0123 (why upstream's `custom` tracker kind cannot replace the resolver).
   Until that branch merges **an Azure DevOps PR completion passes no gate at
   all** — treat the whole capability as absent.
   - Signature: `grep -q 'az repos pr update' .claude/settings.json && echo ok || echo PENDING`
   - Foundation check: `[ -f .claude/hooks/_lib-resolve-ticket.sh ] && grep -qi 'azuredevops' .claude/hooks/_lib-extract-pr.sh && echo "foundation present" || echo "foundation ABSENT"`

9. **Rex writes markdown reviews; the merge gate needs the CEO marker only**
   ([AgDR-0125](agdr/AgDR-0125-rex-md-reviews-and-manual-merge.md)), plus the
   tiered checklist and pre-push advisory (**AgDR-0126, which lives in the
   PRIVATE portfolio repo** at `docs/agdr/` — it documents a decision about
   private skills, so naming them here would defeat 5a.4).
   - Signature: `[ -f .claude/hooks/rex-prepush-advisory.sh ] && echo ok || echo PENDING`
   - When re-grafting, note that the real checklist heading in
     `code-reviewer.md` names a person. Rename it to a role
     ("Learned from Review Feedback") or that file re-introduces the leak.

10. **`/start-ticket` is stack-aware** (AgDR-0124) — AzDO work-item URLs and the
    `repo=azuredevops:<org>/<project>` marker form.
    - Signature: `grep -qi 'azuredevops' .claude/skills/start-ticket/SKILL.md && echo ok || echo PENDING`

### 5c. Dissolved — do NOT re-add

The split-portfolio move removed the *reason* for these, not just the code. Each
was a real divergence under the old single-fork layout and is now actively wrong.

| Was | Why it is gone |
|-----|----------------|
| `onboarding.yaml` stays TRACKED (upstream v3+ gitignores it) | The real config now lives **committed in the private portfolio repo**. Upstream gitignoring it in the public fork is exactly what this layout wants. |
| Fork skills live in `.claude/skills/` + hand-maintained CLAUDE.md rows and skill count | Private skills live in the portfolio repo's `custom-skills/`; upstream's `link-custom-skills.sh` symlinks them in at SessionStart. No CLAUDE.md edits, no count to maintain — and cataloguing them there would leak the names. |
| `.markdownlint-cli2.jsonc` ignores the vendored supplier docs | Those docs moved to the private repo, which has its own lint config. |
| Most `.gitignore` fork entries (`projects`, the workspace rules) | Superseded by the anchored split-portfolio block in 5a.3. Only `.DS_Store` and `.claude/tmp/` survive, folded into 5a.6. |

## 6. Verify before finalizing the merge commit

```bash
git grep -l '^<<<<<<< '                       # no leftover markers
jq empty .claude/settings.json
for f in .claude/hooks/*.sh .claude/hooks/tests/*.sh; do bash -n "$f" || echo "FAIL $f"; done
git diff backup/pre-merge --stat -- projects/ onboarding.yaml   # loss-proof: should be empty/intended
# grep spot-checks: one signature string per divergence in § 5
bash bin/run-hook-tests.sh                     # the CI suite, locally
```

Only then `git commit --no-edit`, renumber AgDRs if needed, and
`rm -f .claude/session/active-bootstrap`.

## 7. Greening the CI (the part that bit us on PR #5)

Upstream's CI grows stricter every release and lints **our fork content**.
Run all of these locally before pushing:

| Check | Local command | Known traps |
|---|---|---|
| Hook tests | `bash bin/run-hook-tests.sh` | Upstream test fixtures may omit `.tool_name` — our invocation-dispatch helpers must fall back to Bash when `.tool_input.command` exists (fail closed). Token-efficiency test: skill descriptions ≤ 200 chars, every skill catalogued in CLAUDE.md, count header exact. |
| shellcheck | `shellcheck .claude/hooks/*.sh` (or read CI) | SC2155: never `local x=$(...)` — declare and assign separately. |
| markdownlint | `npx --yes markdownlint-cli2 "**/*.md"` | Only **tracked** files matter (CI lints the checkout). Vendor-pasted docs go in the cli2 ignores, not hand-fixed. `--fix` first, hand-fix the rest (MD045 bare `<img>` in prose → backticks; MD024 `<id>` placeholders strip to identical headings → use `{id}`; MD056 pipes inside table cells). |
| lychee | (re-run in CI) | Exit 101 + `SendError` at startup = action crash, not broken links. Re-run before investigating. |

## 8. Ship

Push the sync branch and open the PR yourself (Claude stops at the ready
branch): `git push -u origin chore/#<N>-sync-upstream-apexyard`, `gh pr create`
with the commit list + conflict summary in the body. After the PR merges:
`git checkout main && git pull --ff-only`, delete the `backup/*` refs, and
**update § 5 of this doc** if the sync introduced or removed a divergence.
