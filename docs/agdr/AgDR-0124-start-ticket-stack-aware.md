---
id: AgDR-0124
timestamp: 2026-05-19T00:00:00Z
agent: Claude (Opus 4.7)
model: claude-opus-4-7
session: distributed-tickling-wirth
trigger: user-prompt
status: executed
---

# `/start-ticket` becomes stack-aware (Azure DevOps support)

> In the context of an apexyard adopter tracking work in Azure DevOps Boards rather than GitHub Issues, facing the last GitHub-only piece of the SDLC enforcement chain after andrewa28/apexyard#3 made the merge gates stack-aware, I decided to extend `/start-ticket` to accept Azure DevOps work-item URLs and write `repo=azuredevops:<org>/<project>` markers to achieve mechanical parity for the active-ticket gate on both stacks, accepting that the registry now needs an optional `azuredevops:` field to distinguish the Boards project from the git repo.

## Context

`/start-ticket` writes the marker that `require-active-ticket.sh` reads to permit code edits. The framework documented `/start-ticket` as "GitHub-only" both in `CLAUDE.md`'s coverage table and in `workflow-gates.md`'s Azure DevOps appendix; AzDO adopters had to hand-write the marker, which defeats the auditability the skill exists to provide. After andrewa28/apexyard#3 extended `_lib-resolve-ticket.sh` to dispatch on `ticket_stack` for the verify hooks, `/start-ticket` is the last remaining gap.

Two subtle constraints surfaced during planning:

1. **MCP not callable from a bash block.** Skill steps execute shell; the Azure DevOps MCP tools live outside that sandbox. So the title fetch has to use `az boards work-item show`, with graceful degradation when `az` isn't installed.
2. **AzDO Boards project ≠ git repo.** A work-item URL exposes `<org>/<project>`, but the registry's `repo:` field captures `<org>/<git-repo-name>`. For a typical organisation the Boards project name and the git repo name differ (e.g. a `Platform` Boards project holding a `Platform.Auth` repo). A plain string match against `repo:` would miss; that drove the optional `azuredevops:` registry field.

## Options Considered

| Option | Pros | Cons |
|--------|------|------|
| **A — Extend skill via `_lib-resolve-ticket.sh` + add `azuredevops:` registry field** | Mirrors the apexyard#3 pattern (`ticket_state` already there; sibling `ticket_title` is small). Backward-compatible: GitHub adopters see no schema change. Per-project marker isolation works for both stacks. | Two slightly different lookup paths in step 4b — adds ~10 lines of awk/yq. New optional registry field to document. |
| B — Skill-level `az`-only fork, no registry change | Smallest diff. | Per-project marker isolation breaks for AzDO adopters (always falls back to `current-ticket`). Loses the apexyard#41 benefit on AzDO. |
| C — MCP-first title fetch with `az` fallback | Decouples skill from the `az` CLI install. | Bash blocks can't call MCP — would require restructuring the skill to do title fetch in model prose, not shell. Conflicts with the established pattern in every other skill. Higher complexity, lower payoff. |
| D — Treat AzDO work-item URLs as opaque strings, no verification | Trivial. | Reintroduces the fabricated-`#N` failure mode `_lib-resolve-ticket.sh` exists to prevent. Loses parity with the GitHub verify path. |

## Decision

Chosen: **Option A**, because it extends the pattern apexyard#3 already established for the merge / verify hooks (stack dispatch via `_lib-resolve-ticket.sh`), keeps the bash-only shape of the existing skills, and the new `azuredevops:` registry field is opt-in — GitHub adopters' registries are untouched.

Sub-decisions made during implementation:

- **Input form for AzDO**: full URL only (`https://dev.azure.com/<org>/<project>/_workitems/edit/<n>`). Shorthand (`AB#311`, `<org>/<project>#<n>`) deferred to a follow-up — the URL is what users naturally paste from the AzDO UI and avoids needing a per-session "current AzDO project" notion.
- **`az` missing → write marker + warn**, not block. Mirrors `resolve_pr_head`'s graceful-degradation principle: a soft warn the user sees, but the skill still does its job. `title=<unverified>` makes the unverified state explicit downstream.
- **Branch ID format**: `#<num>` for both stacks (was `GH-<num>` for GitHub). Aligns with `.claude/rules/git-conventions.md` which already specifies `#58` shape for both forms in branches, PR titles, and commit footers.
- **Branch-type default for AzDO `Task` work-items**: stay on `feature/` (current default when no `[Feat]`-style prefix is detected). Mapping work-item-type → branch-type deferred; users can rename `feature/` → `chore/` manually.

## Consequences

- `_lib-resolve-ticket.sh` gains a `ticket_title()` function paralleling `ticket_state()`. Two callers today (`/start-ticket`); other skills can adopt it as they become stack-aware.
- `apexyard.projects.yaml` schema gains an optional `azuredevops:` field. `.example` is updated; `/handover` will need a follow-up to prompt for the field when assessing an Azure DevOps-tracked project.
- `workflow-gates.md` Azure DevOps appendix loses the "marker written manually" note and the appendix table row gains the new `azuredevops:` form. `CLAUDE.md`'s mechanical-enforcement table tracks hooks not skills, so it's untouched.
- AzDO adopters whose registry hasn't been updated with `azuredevops:` will silently fall through to the ops-fork fallback marker. Not a regression (matches today's behaviour), but the per-project isolation benefit only kicks in once the field is added.
- Three follow-up issues worth filing upstream: (1) AzDO shorthand URL forms, (2) work-item-type → branch-type mapping, (3) `/handover` schema update for AzDO adopters.

## Artifacts

- Local branch: `feature/start-ticket-stack-aware` (not yet pushed)
- Files modified: `.claude/hooks/_lib-resolve-ticket.sh`, `.claude/skills/start-ticket/SKILL.md`, `apexyard.projects.yaml.example`, `.claude/rules/workflow-gates.md`
- Smoke tests: AzDO/GitHub registry-lookup awk verified against synthetic registry (all 4 cases); `ticket_title` returns empty + rc=1 when `az` is absent (graceful fallback confirmed)

---

*Renumbered from **AgDR-0014** when this fork moved to framework v5.4.0. Upstream
now ships its own AgDR-0014, so the original number collided. Numbering for
fork-owned records starts above upstream's highest (0122) — see
[`docs/upstream-sync-playbook.md`](../upstream-sync-playbook.md) § 5.*
