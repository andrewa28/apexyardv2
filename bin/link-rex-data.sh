#!/usr/bin/env bash
# Link the private portfolio repo's Rex learned data into .claude/.
#
# The checklists, finding index, and review journal name people, repos, and
# internal review patterns, so they live in the PRIVATE portfolio repo and are
# gitignored here. This script re-creates the symlinks after a fresh clone.
# Idempotent.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
cd "$root"

rex_dir=$(python3 - <<'PY'
import json, os, sys
try:
    cfg = json.load(open('.claude/project-config.json'))
    reg = cfg['portfolio']['registry']
except Exception:
    sys.exit('ERROR: .claude/project-config.json has no portfolio.registry — is split-portfolio configured?')
print(os.path.join(os.path.dirname(reg), 'rex'))
PY
)

[ -d "$rex_dir" ] || { echo "ERROR: $rex_dir does not exist"; exit 1; }

for f in rex-checklist-index.json rex-checklist-tier2.md rex-checklist-CONTRIBUTING.md \
         rex-review-journal.md pr-docs-index.json; do
  target="$rex_dir/$f"
  link=".claude/$f"
  if [ ! -e "$target" ]; then
    echo "skip  $f (not present in $rex_dir)"
    continue
  fi
  if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then
    echo "ok    $f"
    continue
  fi
  [ -e "$link" ] && [ ! -L "$link" ] && { echo "ERROR: $link exists and is not a symlink — move it aside first"; exit 1; }
  ln -sfn "$target" "$link"
  echo "link  $f"
done
