#!/usr/bin/env bash
# Link the private portfolio repo's Rex learned data into .claude/.
#
# The checklists, finding index, and review journal name people, repos, and
# internal review patterns, so they live in the PRIVATE portfolio repo and are
# gitignored here. This script re-creates the symlinks after a fresh clone.
# Idempotent.
#
# PREREQUISITE: `.claude/project-config.json` must already exist with a
# `portfolio.registry` entry. On a fresh clone that file is NOT present (it is
# gitignored, by design — see me2resh/apexyard#1031), so restore or write it
# before running this.
#
# TARGETS ARE ABSOLUTE, DELIBERATELY. `portfolio.registry` is stored relative to
# the FORK ROOT (e.g. "../<private-portfolio>/apexyard.projects.yaml"), but a
# relative symlink target resolves against the LINK's own directory — here
# `.claude/`, one level down. Using the config string verbatim produced five
# dangling links that `readlink` still matched, so the idempotence check happily
# reported "ok" over a set of broken links. Resolve to an absolute path, and
# assert the link actually resolves before claiming success.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
cd "$root"

if [ ! -f .claude/project-config.json ]; then
  echo "ERROR: .claude/project-config.json not found in $root." >&2
  echo "       It is gitignored, so a fresh clone will not have it. Restore it first." >&2
  exit 1
fi

rex_dir=$(python3 - <<'PY'
import json, os, sys
try:
    cfg = json.load(open('.claude/project-config.json'))
except (OSError, ValueError) as exc:
    sys.exit('ERROR: could not read .claude/project-config.json: %s' % exc)
try:
    reg = cfg['portfolio']['registry']
except (KeyError, TypeError):
    sys.exit('ERROR: .claude/project-config.json has no portfolio.registry — is split-portfolio configured?')
# Absolute, so the target is correct no matter which directory the link sits in.
print(os.path.abspath(os.path.join(os.path.dirname(reg), 'rex')))
PY
)

[ -d "$rex_dir" ] || { echo "ERROR: $rex_dir does not exist" >&2; exit 1; }

failed=0
for f in rex-checklist-index.json rex-checklist-tier2.md rex-checklist-CONTRIBUTING.md \
         rex-review-journal.md pr-docs-index.json; do
  target="$rex_dir/$f"
  link=".claude/$f"

  if [ ! -e "$target" ]; then
    # If a link to the now-missing target is still sitting here, clear it.
    # Leaving it would exit 0 with a dangling link in place — no "ok" is
    # printed, so the never-report-success-over-a-broken-link property holds,
    # but rc=0 would still imply a consistency that isn't there.
    if [ -L "$link" ]; then
      rm -f "$link"
      echo "prune $f (target gone from $rex_dir; removed stale link)"
    else
      echo "skip  $f (not present in $rex_dir)"
    fi
    continue
  fi

  if [ -e "$link" ] && [ ! -L "$link" ]; then
    echo "ERROR: $link exists and is not a symlink — move it aside first" >&2
    exit 1
  fi

  if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ] && [ -e "$link" ]; then
    echo "ok    $f"
    continue
  fi

  ln -sfn "$target" "$link"

  # Assert the link RESOLVES. `readlink` matching the intended string is not
  # evidence the target exists — that is exactly how the broken version passed.
  if [ -e "$link" ]; then
    echo "link  $f"
  else
    echo "ERROR: $link created but does not resolve (target: $target)" >&2
    failed=1
  fi
done

if [ "$failed" -ne 0 ]; then
  echo "ERROR: one or more links do not resolve — see above." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Keep .git/info/exclude in step with the private custom-skills/ directory.
#
# link-custom-skills.sh creates a symlink at .claude/skills/<name>/ for each
# private skill on every SessionStart. Those names must not be written to a
# TRACKED file in this PUBLIC repo (that would publish exactly what the
# split-portfolio layout protects), and a glob can't target them either —
# they sit among ~70 tracked framework skill dirs in the same parent. So the
# names go in .git/info/exclude, which is per-clone and never committed.
#
# Per-clone means a FRESH CLONE starts with none of them, and the symlinks come
# back untracked and stageable at the next SessionStart. Generating the list
# here — from the private dir, at runtime — closes that window without naming
# anything in the repo, and removes the "adding a 9th skill needs a new line"
# footgun: the list regenerates itself.
# ---------------------------------------------------------------------------
skills_dir="$(dirname "$rex_dir")/custom-skills"
exclude_file=".git/info/exclude"

if [ -d "$skills_dir" ]; then
  mkdir -p "$(dirname "$exclude_file")"
  [ -f "$exclude_file" ] || : > "$exclude_file"

  added=0
  for skill_path in "$skills_dir"/*/; do
    [ -d "$skill_path" ] || continue                      # no match → literal glob
    name=$(basename "$skill_path")
    [ -f "$skill_path/SKILL.md" ] || continue             # only real skills
    entry=".claude/skills/$name"
    grep -qxF "$entry" "$exclude_file" || { printf '%s\n' "$entry" >> "$exclude_file"; added=$((added + 1)); }
  done

  if [ "$added" -gt 0 ]; then
    echo "excl  added $added custom-skill entr$([ "$added" -eq 1 ] && echo y || echo ies) to $exclude_file"
  else
    echo "excl  $exclude_file already covers every custom skill"
  fi
fi
