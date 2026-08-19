#!/usr/bin/env bash
# Regression: the merge gate's marker lookup key must come from the merge
# command itself, never from arbitrary text elsewhere in the same command.
#
# andrewa28/apexyardv2-portfolio#7. Three gates each carried a private, greedy
# `--repo` scrape that ran before the shared library, so a `--repo` inside a
# heredoc body or an unrelated subcommand chose which approval marker the gate
# read. The dangerous direction is not the observed one (points at a missing
# marker -> blocks) but its mirror: point it at a marker that EXISTS with a
# matching SHA and the gate is satisfied by an unrelated approval. No forgery
# required — only naming a different file.
#
# Payload strings are assembled at runtime. A test file containing a literal
# merge command trips the very gate it exercises (AgDR-0111 text matching), so
# writing them out would make this file unrunnable.
set -u

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OPS_ROOT="$(cd "$HOOK_DIR/.." && pwd)"
pass=0; fail=0

GH="gh"; PRW="pr"; MG="me""rge"
VICTIM="victimorg/victimrepo"
OTHER="otherorg/otherrepo"
TEST_PR=88888

# shellcheck source=/dev/null
. "$HOOK_DIR/_lib-extract-pr.sh"
# shellcheck source=/dev/null
. "$HOOK_DIR/_lib-review-markers.sh"

check() {
  local label="$1" got="$2" want="$3"
  if [ "$got" = "$want" ]; then
    printf '  %-62s ✓\n' "$label"; pass=$((pass+1))
  else
    printf '  %-62s ✗ got=%s want=%s\n' "$label" "${got:-<empty>}" "${want:-<empty>}"; fail=$((fail+1))
  fi
}

echo "== resolution: the flag belonging to the merge, not to nearby text =="

# A real merge, preceded in the same command by an unrelated --repo.
cmd_mixed="cat > notes.md <<EOF
Background: $GH issue view 3 --repo $OTHER
EOF
$GH $PRW $MG $TEST_PR --repo $VICTIM --squash"
check "unrelated --repo earlier; merge names the victim repo" \
      "$(extract_repo_flag_in_merge_span "$cmd_mixed")" "$VICTIM"

# Text that only MENTIONS a merge and a --repo; no actual merge command.
cmd_mention="cat > doc.md <<EOF
Run --repo $OTHER first, then squash-$MG it.
EOF"
check "mention-only text resolves to nothing" \
      "$(extract_repo_flag_in_merge_span "$cmd_mention")" ""

# A trailing unrelated -R must not leak in (the #764 case this fencing exists for).
cmd_trailing="$GH $PRW $MG $TEST_PR --repo $VICTIM --squash && grep -R foo ."
check "trailing unrelated -R does not override" \
      "$(extract_repo_flag_in_merge_span "$cmd_trailing")" "$VICTIM"

echo "== the naive form this replaced is demonstrably wrong =="

# Pinned here rather than described, so the reason the helper exists survives
# refactoring. This is the exact expression the three gates carried privately.
naive() { echo "$1" | sed -nE 's/.*--repo[[:space:]]+([^[:space:]]+).*/\1/p' | head -1; }
check "naive greedy form picks the WRONG repo (documents the bug)" \
      "$(naive "$cmd_mixed")" "$OTHER"
check "naive greedy form invents a repo from mention-only text" \
      "$(naive "$cmd_mention")" "$OTHER"

echo "== the gate keys its marker path on the merge's repo =="

# End-to-end allow/deny is NOT asserted here, deliberately. The gate resolves the
# PR's HEAD from the forge before comparing any marker, so a synthetic PR number
# fails closed on HEAD resolution and never reaches the marker comparison — the
# check would pass for the wrong reason. What IS assertable, and what this bug
# was actually about, is which marker path the resolved key produces.
resolved="$(extract_repo_flag_in_merge_span "$cmd_mixed")"
check "resolved key -> victim repo's marker path" \
      "$(basename "$(review_marker_path "$resolved" "$TEST_PR" ceo "$OPS_ROOT")")" \
      "$(basename "$(review_marker_path "$VICTIM" "$TEST_PR" ceo "$OPS_ROOT")")"
check "resolved key is NOT the mentioned repo's marker path" \
      "$([ "$(basename "$(review_marker_path "$resolved" "$TEST_PR" ceo "$OPS_ROOT")")" = \
           "$(basename "$(review_marker_path "$OTHER" "$TEST_PR" ceo "$OPS_ROOT")")" ] && echo same || echo different)" \
      "different"

echo "== ambiguity fails closed, and the = form is handled =="

# THE case the first version of this test missed: a quoted line that is itself
# merge-command-shaped. `grep -oE` matches per line, so this creates a second
# span; taking the first would let quoted documentation choose the key. 17 files
# in this repo contain exactly such a line.
cmd_two_spans="cat > doc.md <<EOF
Release step: $GH $PRW $MG 9 --repo $OTHER --squash
EOF
$GH $PRW $MG $TEST_PR --repo $VICTIM --squash"
check "two merge spans -> empty (fail closed, not first-wins)" \
      "$(extract_repo_flag_in_merge_span "$cmd_two_spans")" ""
# sed is line-based, so `head -1` takes the first MATCHING LINE — the quoted
# documentation line — not the real merge further down. Exactly the observed bug.
check "  ...naive form picks the QUOTED doc line, not the real merge" \
      "$(naive "$cmd_two_spans")" "$OTHER"

# `gh` accepts --repo=owner/repo. The space-only pattern returned empty, which
# fell through to a different resolution path — approval verified against one
# repo while the merge runs on another.
check "--repo=owner/repo (equals form) resolves" \
      "$(extract_repo_flag_in_merge_span "$GH $PRW $MG $TEST_PR --repo=$VICTIM --squash")" "$VICTIM"
check "-R=owner/repo (short equals form) resolves" \
      "$(extract_repo_flag_in_merge_span "$GH $PRW $MG $TEST_PR -R=$VICTIM --squash")" "$VICTIM"

# Quotes must not survive into the marker filename.
check "quoted --repo value is unquoted" \
      "$(extract_repo_flag_in_merge_span "$GH $PRW $MG $TEST_PR --repo \"$VICTIM\" --squash")" "$VICTIM"

check "--repo= with no value does not capture the next flag" \
      "$(extract_repo_flag_in_merge_span "$GH $PRW $MG $TEST_PR --repo= --squash")" ""

echo
echo "  passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
