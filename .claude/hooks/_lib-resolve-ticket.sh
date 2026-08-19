#!/bin/bash
# Stack-aware ticket existence/state lookup. Sourced by:
#   - validate-pr-create.sh  (checks the ticket referenced in a PR title)
#   - verify-commit-refs.sh  (checks every Closes/Fixes/Refs/Resolves in a
#                             commit message)
#
# Not a hook itself (prefixed with `_lib-` so it's never wired as one).
# Sourced via `. "$(dirname "$0")/_lib-resolve-ticket.sh"`.
#
# WHY THIS EXISTS (andrewa28/apexyard#3)
# --------------------------------------
# The two hooks above used to call `gh issue view` directly. That meant tracker
# verification was GitHub-only — adopters tracking work in Azure DevOps Boards
# got past the "this #N actually exists" backstop on convention alone. This
# helper abstracts the lookup so both stacks get the same mechanical check.
#
# RESOLVES AGAINST
# ----------------
#   - GitHub Issues       (via `gh issue view <num> --repo <o>/<r>`)
#   - Azure DevOps Boards (via `az boards work-item show --id <num>`)
#
# Stack is encoded in the `tracker_spec` argument:
#   - `<owner>/<repo>`              → GitHub
#   - `azuredevops:<org>/<project>` → Azure DevOps
#
# RETURN VALUES (echoed to stdout)
# --------------------------------
#   "open"    — issue / work item exists and is not in a terminal state
#   "closed"  — exists but is closed / done / removed
#   "missing" — does not exist (fabricated #N — the failure mode the
#               ticket-vocabulary rule targets)
#   "unknown" — lookup failed for non-existence reasons (CLI not installed,
#               auth expired, network down). Caller should treat as soft
#               warn, NOT a block — same principle as the GitHub fallback
#               that already exists for resolve_pr_head failures.
#
# USAGE
# -----
#   . "$(dirname "$0")/_lib-resolve-ticket.sh"
#   spec=$(resolve_tracker_spec)              # reads config + origin
#   case $(ticket_state "$NUM" "$spec") in
#     missing) ...block ;;
#     closed)  ...warn-or-block-depending-on-context ;;
#     open|unknown) ...allow ;;
#   esac

# Directory this lib lives in, so it can source its siblings (_lib-ops-root.sh)
# regardless of the caller's cwd. Uses BASH_SOURCE, not $0 — $0 is the *hook*
# when this file is sourced, not this file.
_RESOLVE_TICKET_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Echoes "github" | "azuredevops" | "" based on a tracker_spec string.
ticket_stack() {
  local spec="$1"
  case "$spec" in
    azuredevops:*) echo "azuredevops" ;;
    */*) echo "github" ;;
    *) echo "" ;;
  esac
}

# Echoes one of: open | closed | missing | unknown.
ticket_state() {
  local num="$1"
  local spec="$2"
  local stack
  stack=$(ticket_stack "$spec")

  if [ -z "$num" ] || [ -z "$spec" ]; then
    echo "unknown"
    return
  fi

  case "$stack" in
    github)
      if ! command -v gh >/dev/null 2>&1; then
        echo "unknown"
        return
      fi
      local json
      json=$(gh issue view "$num" --repo "$spec" --json number,state 2>/dev/null)
      if [ -z "$json" ]; then
        echo "missing"
        return
      fi
      local state
      state=$(echo "$json" | jq -r '.state // empty' 2>/dev/null)
      if [ "$state" = "CLOSED" ]; then echo "closed"; else echo "open"; fi
      ;;
    azuredevops)
      if ! command -v az >/dev/null 2>&1; then
        echo "unknown"
        return
      fi
      # az boards work-item show outputs nothing on stdout and an error on stderr
      # if the item is missing or the caller isn't authenticated. Distinguish
      # missing-vs-auth via stderr content.
      local tmp_err
      tmp_err=$(mktemp 2>/dev/null) || tmp_err="/tmp/_lib-resolve-ticket.$$"
      local state
      state=$(az boards work-item show --id "$num" --query 'fields."System.State"' -o tsv 2>"$tmp_err")
      local rc=$?
      local err
      err=$(cat "$tmp_err" 2>/dev/null)
      rm -f "$tmp_err"

      if [ "$rc" -eq 0 ] && [ -n "$state" ]; then
        case "$state" in
          Closed|Removed|Done) echo "closed" ;;
          *) echo "open" ;;
        esac
        return
      fi

      # Failure path — try to distinguish "missing" from "auth/network".
      # TF401232 = "Work item N does not exist, or you do not have permissions to read it."
      if echo "$err" | grep -qiE 'does not exist|TF401232|TF401019|not found'; then
        echo "missing"
      else
        echo "unknown"
      fi
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

# Echo the work item / issue title, or empty string on lookup failure.
# Used by /start-ticket to populate the marker's `title=` field. Failure is
# non-fatal — the skill writes `title=<unverified>` and warns rather than
# blocking. Mirrors ticket_state's stack dispatch.
#
# Returns 0 on success (title echoed), 1 on any failure (empty echo).
ticket_title() {
  local num="$1"
  local spec="$2"
  local stack
  stack=$(ticket_stack "$spec")

  if [ -z "$num" ] || [ -z "$spec" ]; then
    echo ""
    return 1
  fi

  case "$stack" in
    github)
      if ! command -v gh >/dev/null 2>&1; then
        echo ""
        return 1
      fi
      local title
      title=$(gh issue view "$num" --repo "$spec" --json title -q .title 2>/dev/null)
      if [ -z "$title" ]; then
        echo ""
        return 1
      fi
      echo "$title"
      ;;
    azuredevops)
      if ! command -v az >/dev/null 2>&1; then
        echo ""
        return 1
      fi
      local title
      title=$(az boards work-item show --id "$num" --query 'fields."System.Title"' -o tsv 2>/dev/null)
      if [ -z "$title" ]; then
        echo ""
        return 1
      fi
      echo "$title"
      ;;
    *)
      echo ""
      return 1
      ;;
  esac
}

# Resolve the tracker spec from project-config.json + origin remote.
# Returns a string suitable for `ticket_state ... <spec>`:
#   - `<owner>/<repo>`              for GitHub
#   - `azuredevops:<org>/<project>` for Azure DevOps
#
# Resolution order:
#   1. `.tracker.azuredevops`  → `azuredevops:<value>`   (v5.4.0 nested shape)
#   2. `.tracker_azuredevops`  → `azuredevops:<value>`   (legacy flat key, pre-v5)
#   3. `.tracker.repo` / `.tracker_repo` → value as-is   (explicit GitHub repo)
#   4. origin remote → `<owner>/<repo>` (GitHub)
#
# SCOPE NOTE (re-graft, split-portfolio v2): the spec must stay **per-repo**, not
# global. This fork's own framework work is tracked on GitHub, while every
# MANAGED project is tracked in Azure DevOps — so a single ops-fork-wide spec
# would mislabel one or the other. Resolution therefore starts at the CURRENT
# repo and only falls back to the ops fork:
#
#   current repo's .claude/project-config.json  (a managed project may pin its own)
#     → ops fork's .claude/project-config.json  (the framework's own tracker)
#       → origin remote                          (GitHub shape)
#
# KNOWN GAP: v5.4.0's registry supports a per-project `tracker:` block in
# apexyard.projects.yaml, which is the better source of truth for a managed
# project's tracker than a config file inside a clone that carries no `.claude/`
# tree. Wiring that in is deliberately deferred — see andrewa28/apexyardv2-portfolio#1.
resolve_tracker_spec() {
  local cfg="" repo_root="" ops_root=""

  repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$repo_root" ] && [ -f "$repo_root/.claude/project-config.json" ]; then
    cfg="$repo_root/.claude/project-config.json"
  else
    if [ -f "${_RESOLVE_TICKET_LIB_DIR:-}/_lib-ops-root.sh" ]; then
      # shellcheck source=/dev/null
      . "${_RESOLVE_TICKET_LIB_DIR}/_lib-ops-root.sh"
      ops_root=$(resolve_ops_root 2>/dev/null)
    fi
    if [ -z "$ops_root" ]; then
      local r="$PWD"
      while [ -n "$r" ] && [ "$r" != / ]; do
        if [ -f "$r/.apexyard-fork" ] || \
           { [ -f "$r/onboarding.yaml" ] && [ -f "$r/apexyard.projects.yaml" ]; }; then
          ops_root="$r"; break
        fi
        r="${r%/*}"
      done
    fi
    [ -n "$ops_root" ] && [ -f "$ops_root/.claude/project-config.json" ] && \
      cfg="$ops_root/.claude/project-config.json"
  fi

  if [ -n "$cfg" ]; then
    local azdo gh_repo
    azdo=$(jq -r '.tracker.azuredevops // .tracker_azuredevops // empty' "$cfg" 2>/dev/null)
    if [ -n "$azdo" ] && [ "$azdo" != "null" ]; then
      echo "azuredevops:$azdo"
      return
    fi
    gh_repo=$(jq -r '.tracker.repo // .tracker_repo // empty' "$cfg" 2>/dev/null)
    if [ -n "$gh_repo" ] && [ "$gh_repo" != "null" ]; then
      echo "$gh_repo"
      return
    fi
  fi

  local origin_url
  origin_url=$(git remote get-url origin 2>/dev/null)
  echo "$origin_url" | sed -nE 's|.*[:/]([^/:]+/[^/]+)\.git$|\1|p; s|.*[:/]([^/:]+/[^/]+)$|\1|p' | head -1
}
