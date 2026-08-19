# Keep a forked AzDO ticket resolver rather than upstream's `custom` tracker kind

> In the context of re-grafting Azure DevOps support onto framework v5.4.0, facing the
> choice between upstream's configurable `custom` tracker kind and the fork's hand-written
> `_lib-resolve-ticket.sh`, I decided to keep the forked resolver to achieve genuine
> fabricated-ticket detection on Azure DevOps, accepting ~200 lines of forked shell that
> must be re-asserted on every upstream sync.

## Context

The previous ops fork (framework v4.3.0) shipped `_lib-resolve-ticket.sh`: a stack-aware
ticket lookup used by `validate-pr-create.sh` and `verify-commit-refs.sh` to verify that a
referenced `#N` is a real ticket. It resolves against GitHub Issues (`gh issue view`) or
Azure DevOps Boards (`az boards work-item show`), and returns a four-state result:
`open` / `closed` / `missing` / `unknown`.

Framework v5.4.0 has since grown its own tracker abstraction (`_lib-tracker.sh`, AgDR-0033)
supporting `gh`, `glab`, `linear`, `jira`, `asana`, `custom`, and `none`. The `custom` kind
takes a `view_command` template with `{id}` and `{owner_repo}` placeholders. On the surface
this looks like it should replace the forked resolver entirely — configuration instead of
code, and therefore nothing to re-assert at sync time.

That option was evaluated properly before writing any code, because "less forked code"
is a real and recurring cost saving for this fork (see `docs/upstream-sync-playbook.md`).

## Options Considered

| Option | Pros | Cons |
|--------|------|------|
| **A. `custom` tracker kind** — set `tracker.kind: custom` with a `view_command` that shells out to `az boards work-item show` and pipes through `jq` to emit upstream's normalised `{state,title,url,labels}` shape | Zero forked shell. Every tracker-aware consumer (`/start-ticket`, `tracker_view`, future skills) works natively. Nothing to re-assert on an upstream sync. | **Cannot distinguish "work item does not exist" from "az is missing / unauthenticated".** Both surface as empty output. |
| **B. Keep the forked `_lib-resolve-ticket.sh`** | Preserves the four-state result, including the `missing` state that actually blocks a fabricated reference. Distinguishes missing from unavailable by matching AzDO's `TF401232` error signature on stderr. | ~200 lines of forked shell in the trust chain, re-asserted on every sync. A second lookup path alongside `_lib-tracker.sh`. |
| C. Extend upstream's `_lib-tracker.sh` with a first-class `azuredevops` kind and contribute it upstream | Best long-term shape — everyone benefits, divergence eventually drops to zero. | Much larger change; upstream review latency; blocks this migration on someone else's schedule. |

## Decision

Chosen: **Option B**, because Option A silently destroys the control this code exists to
provide.

The evidence is in v5.4.0's own `validate-pr-create.sh:415-425`. For any tracker kind other
than `gh`, an empty lookup result is handled like this:

```
# Non-gh tracker (Linear / Jira / Asana / custom) returned nothing — the
# tracker CLI is absent, unauthenticated, or not queryable from this
# environment (#501). Do NOT block: the title already passed the shape
# check against tracker_id_pattern ...
```

That is a deliberate upstream decision (#501) and correct for its purpose — it stops the
hook making it impossible to open a PR against a tracker the CI box cannot reach. But it
means that under Option A, a **fabricated** work-item reference produces exactly the same
observable signal as an unreachable CLI, so it is accepted on shape alone. `#99999` would
pass. Catching precisely that fabrication is the entire reason
`.claude/rules/ticket-vocabulary.md` names these two hooks as its mechanical backstops.

So Option A does not merely trade code for config — it downgrades a real existence check to
a regex. The ~200 forked lines buy back a control, which is a different bargain from the one
"configuration over code" usually offers.

Option C is the right destination and is **not** ruled out; it is deferred because it makes
this migration depend on upstream review. If it lands later, Option B is deleted wholesale.

## Consequences

- `_lib-resolve-ticket.sh` is carried into this fork and joins the divergence register in
  `docs/upstream-sync-playbook.md` § 5, with a grep signature so it is re-asserted after
  every sync.
- Two lookup paths coexist: `_lib-tracker.sh` (upstream, used by the ticket-creating skills
  and `/start-ticket`) and `_lib-resolve-ticket.sh` (fork, used by the two verification
  hooks). This is a real maintenance smell and is accepted knowingly — the note above records
  why, so a future maintainer does not "simplify" it back to Option A without re-reading this.
- The `missing` state blocks; `unknown` (az absent, auth expired, network down) only warns.
  A developer without the `az` CLI is never hard-blocked — same graceful-degrade principle as
  upstream's `resolve_pr_head` fallback.
- If upstream ever adds a first-class `azuredevops` kind that preserves a missing-vs-unknown
  distinction, this AgDR should be superseded and the forked lib deleted.

## Artifacts

- Ticket: `andrewa28/apexyardv2-portfolio#1`
- Branch: `chore/GH-1-azdo-merge-shape-ticket-resolution`
- Evidence: `.claude/hooks/validate-pr-create.sh:415-425` (v5.4.0), `.claude/hooks/_lib-tracker.sh` § `custom` adapter (pass-through normalisation)
- Supersedes the fork's original AgDR-0014 rationale, carried over as AgDR-0124.
