#!/usr/bin/env bash
# Functional check: does block-unreviewed-merge.sh fire on the AzDO shapes?
# Payloads are assembled here (not in the invoking command line) so the
# caller's own command text is not itself merge-shaped — otherwise the gate
# false-positives on the test invocation. That false positive is a known
# text-matching limitation (AgDR-0111), not something this test is measuring.
HOOK="${1:-$(cd "$(dirname "$0")/.." && pwd)/block-unreviewed-merge.sh}"
pass=0; fail=0

run() {
  local label="$1" payload="$2" expect="$3"
  local rc
  printf '%s\n' "$payload" | bash "$HOOK" >/dev/null 2>&1
  rc=$?
  local verdict
  case "$rc" in
    2) verdict=BLOCKED ;;
    0) verdict=allowed ;;
    *) verdict="rc=$rc" ;;
  esac
  if [ "$verdict" = "$expect" ]; then
    printf '  %-48s %-8s ✓\n' "$label" "$verdict"; pass=$((pass+1))
  else
    printf '  %-48s %-8s ✗ (expected %s)\n' "$label" "$verdict" "$expect"; fail=$((fail+1))
  fi
}

# Build the forbidden substrings at runtime so this file's own text stays inert
# to any text-matching scanner reading it.
GH="gh"; PR="pr"; MG="me""rge"

echo "=== no approval markers for PR 999 → every merge shape must BLOCK ==="
run "$GH $PR $MG (upstream control)" \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$GH $PR $MG 999 --repo o/r --squash\"}}" BLOCKED
run "az repos pr update --status completed" \
    '{"tool_name":"Bash","tool_input":{"command":"az repos pr update --id 999 --status completed"}}' BLOCKED
run "AzDO MCP repo_update_pull_request" \
    '{"tool_name":"mcp__azure-devops__repo_update_pull_request","tool_input":{"pullRequestId":999,"status":"completed"}}' BLOCKED

echo "=== non-merges must pass through untouched ==="
run "ls -la" \
    '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' allowed
run "az repos pr update (status=active)" \
    '{"tool_name":"Bash","tool_input":{"command":"az repos pr update --id 999 --status active"}}' allowed
run "AzDO MCP status=active" \
    '{"tool_name":"mcp__azure-devops__repo_update_pull_request","tool_input":{"pullRequestId":999,"status":"active"}}' allowed
run "unrelated AzDO MCP tool" \
    '{"tool_name":"mcp__azure-devops__repo_get_pull_request_by_id","tool_input":{"pullRequestId":999}}' allowed
run "empty command" \
    '{"tool_name":"Bash","tool_input":{"command":""}}' allowed

echo
echo "  passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
