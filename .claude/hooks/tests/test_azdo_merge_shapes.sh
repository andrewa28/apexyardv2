#!/usr/bin/env bash
# Do the four merge gates recognise the Azure DevOps merge shapes?
#
# Two AzDO shapes exist beyond the gh/glab ones:
#   Bash: `az repos pr update --id <n> --status completed`
#   MCP : mcp__azure-devops__repo_update_pull_request, status=completed
# The MCP shape carries NO command string, so a gate keyed only on
# `.tool_input.command` can never see it.
#
# EXPECTATIONS DIFFER PER GATE, ON PURPOSE. An earlier version of this test
# asserted "all gates block all merge shapes" and reported three false failures,
# because that is not what these gates do. What each one does with an
# unresolvable PR is a deliberate design choice, and the point of the matrix is
# to pin those choices rather than flatten them:
#
#   block-unreviewed-merge      BLOCKS  — cannot resolve the PR HEAD from the
#                                         forge, so it cannot verify its
#                                         precondition and fails closed
#                                         (me2resh/apexyard#1091, AgDR-0104).
#   require-design-review-for-ui        allows — exits 0 when it cannot determine
#   require-architecture-review           the changed files. NOT a property this
#                                         test endorses; it is the subject of
#                                         portfolio ticket #8. Pinned here so a
#                                         future change to it is deliberate.
#   block-merge-on-red-ci       depends — fails closed on gh (CI unresolvable),
#                                         and deliberately no-ops on AzDO, where
#                                         Build Validation branch policies gate
#                                         red CI server-side. It must still be
#                                         INVOKED, so it can say so.
#
# Payloads are assembled at runtime. A test file containing a literal merge
# command trips the gate it is testing (AgDR-0111), which has happened twice in
# this repo's history — once to a reviewer, once to a read-only grep.
set -u

HOOK_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
[ -d "$HOOK_DIR" ] || { echo "no hook dir at $HOOK_DIR"; exit 1; }
pass=0; fail=0
GH="gh"; PRW="pr"; MG="me""rge"
AZUP="az repos pr update"

payload_bash()  { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"; }
payload_mcp()   { printf '{"tool_name":"mcp__azure-devops__repo_update_pull_request","tool_input":{"pullRequestId":999,"status":"%s"}}' "$1"; }

run() { # <hook> <label> <payload> <expected>
  local hook="$1" label="$2" payload="$3" expect="$4" rc verdict
  printf '%s\n' "$payload" | bash "$HOOK_DIR/$hook.sh" >/dev/null 2>&1; rc=$?
  case "$rc" in 2) verdict=BLOCKED ;; 0) verdict=allowed ;; *) verdict="rc=$rc" ;; esac
  if [ "$verdict" = "$expect" ]; then
    printf '    %-44s %-8s ✓\n' "$label" "$verdict"; pass=$((pass+1))
  else
    printf '    %-44s %-8s ✗ expected %s\n' "$label" "$verdict" "$expect"; fail=$((fail+1))
  fi
}

# Shapes that must NEVER be treated as a merge, whatever the gate.
non_merges() {
  local hook="$1"
  run "$hook" "not a merge: ls"            "$(payload_bash 'ls -la')"                       allowed
  run "$hook" "$AZUP --status active"      "$(payload_bash "$AZUP --id 999 --status active")" allowed
  run "$hook" "MCP status=active"          "$(payload_mcp active)"                          allowed
  run "$hook" "empty command"              "$(payload_bash '')"                             allowed
}

echo "== block-unreviewed-merge: fails closed on an unverifiable PR =="
run block-unreviewed-merge "$GH $PRW $MG (control)"  "$(payload_bash "$GH $PRW $MG 999 --repo o/r --squash")" BLOCKED
run block-unreviewed-merge "$AZUP --status completed" "$(payload_bash "$AZUP --id 999 --status completed")"   BLOCKED
run block-unreviewed-merge "MCP status=completed"     "$(payload_mcp completed)"                              BLOCKED
non_merges block-unreviewed-merge

echo "== design / architecture: exit 0 when the diff is unresolvable (ticket #8) =="
for hook in require-design-review-for-ui require-architecture-review; do
  echo "  -- $hook"
  run "$hook" "$GH $PRW $MG (control)"      "$(payload_bash "$GH $PRW $MG 999 --repo o/r --squash")" allowed
  run "$hook" "$AZUP --status completed"    "$(payload_bash "$AZUP --id 999 --status completed")"   allowed
  run "$hook" "MCP status=completed"        "$(payload_mcp completed)"                              allowed
  non_merges "$hook"
done

echo "== block-merge-on-red-ci: closed on gh, deliberate no-op on AzDO =="
run block-merge-on-red-ci "$GH $PRW $MG (control)"   "$(payload_bash "$GH $PRW $MG 999 --repo o/r --squash")" BLOCKED
run block-merge-on-red-ci "$AZUP --status completed" "$(payload_bash "$AZUP --id 999 --status completed")"   allowed
run block-merge-on-red-ci "MCP status=completed"     "$(payload_mcp completed)"                              allowed
non_merges block-merge-on-red-ci

# A silent no-op is indistinguishable from a gate that never fired. The note is
# the only evidence the hook was invoked and decided not to apply, so assert it.
echo "== the AzDO no-op announces itself =="
note=$(printf '%s\n' "$(payload_bash "$AZUP --id 999 --status completed")" \
       | bash "$HOOK_DIR/block-merge-on-red-ci.sh" 2>&1 >/dev/null)
if printf '%s' "$note" | grep -q 'Build Validation'; then
  printf '    %-44s %-8s ✓\n' "prints a NOTE explaining non-application" "note"; pass=$((pass+1))
else
  printf '    %-44s %-8s ✗ got: %s\n' "prints a NOTE explaining non-application" "silent" "${note:-<nothing>}"; fail=$((fail+1))
fi

echo
echo "  passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
