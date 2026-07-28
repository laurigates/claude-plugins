#!/usr/bin/env bash
# Regression test for scripts/audit-skill-descriptions.py skill discovery (#2119).
#
# THE BUG: find_skills() collected `rglob("SKILL.md")` and `rglob("skill.md")`
# into one list, deduplicating only by Path equality. On macOS's
# case-INSENSITIVE APFS both globs return the same files under two different
# spellings, so every skill was audited TWICE and every count the script
# reported was 2x ("Audited 814 skills" against 407 real files).
#
# WHY THIS TEST IS SEMANTIC, NOT SYNTACTIC: grepping the source for `st_ino`
# would pass on a partial fix. This test plants a fixture skill tree, forces
# the duplicate-path condition, EXECUTES the real script against it, and
# asserts the audited count equals the number of distinct FILES.
#
# WHY IT IS NON-VACUOUS ON BOTH FILESYSTEM KINDS: on a case-sensitive
# filesystem the double-count cannot arise naturally, so a naive test passes
# there even against the broken script. The fixture therefore creates the
# duplicate-path condition directly instead of relying on the host's case
# behaviour:
#   - case-sensitive FS  -> `ln SKILL.md skill.md` succeeds, giving two
#                           distinct paths sharing one inode (the same shape
#                           the case-insensitive lookup produces).
#   - case-insensitive FS -> that `ln` fails with EEXIST because the name
#                           already resolves; the duplication is already there.
# A fixture-validity guard asserts the condition actually holds (naive count ==
# 2x distinct count) so the test cannot silently degrade into a no-op.
#
# The script hardcodes REPO_ROOT = <its own parent>/.., so the fixture gets a
# copy of the real file under <fixture>/scripts/ — the byte-for-byte production
# script is what runs, with no --root flag added to its CLI just for testing.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
audit_script="$repo_root/scripts/audit-skill-descriptions.py"

pass_count=0
fail_count=0

assert() {
  # assert <description> <"true"/"false">
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}

if ! python3 -c 'import yaml' >/dev/null 2>&1; then
  echo "SKIP: PyYAML unavailable"
  exit 0
fi

# An explicit template so BSD/macOS `mktemp` honours TMPDIR — the bare
# `mktemp -d` form ignores it, which silently pins the fixture to the default
# (case-insensitive) volume and makes a "case-sensitive" run a false positive.
fixture="$(mktemp -d "${TMPDIR:-/tmp}/audit-dedup-XXXXXX")"
if [ -z "$fixture" ] || [ ! -d "$fixture" ]; then
  echo "FAIL: could not create fixture directory" >&2
  exit 1
fi
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/scripts"
cp "$audit_script" "$fixture/scripts/audit-skill-descriptions.py"

# Three skills stored under the canonical SKILL.md name...
for slug in alpha beta gamma; do
  mkdir -p "$fixture/fixture-plugin/skills/$slug"
  cat >"$fixture/fixture-plugin/skills/$slug/SKILL.md" <<EOF
---
name: $slug
description: Fixture skill $slug. Use when exercising the discovery dedup guard.
---

# $slug

Body.
EOF
done

# ...and one stored under a genuinely LOWERCASE skill.md, with NO uppercase
# counterpart. The fix must keep finding this on a case-sensitive filesystem,
# where only the second glob sees it (see scripts/check-skill-filename-case.sh
# — 45 skills once carried this name). It is deliberately left un-linked below
# so the case-sensitive run really does exercise the lowercase-only path.
mkdir -p "$fixture/fixture-plugin/skills/delta"
cat >"$fixture/fixture-plugin/skills/delta/skill.md" <<'EOF'
---
name: delta
description: Fixture skill delta stored lowercase. Use when checking case-sensitive discovery.
---

# delta

Body.
EOF

DISTINCT_SKILLS=4
DUPLICATED_SKILLS=3   # alpha, beta, gamma — delta stays lowercase-only

# Force the duplicate-path condition on a case-sensitive filesystem. On a
# case-insensitive one these links fail (EEXIST) and the duplication already
# exists — either way the condition below holds.
for slug in alpha beta gamma; do
  ln "$fixture/fixture-plugin/skills/$slug/SKILL.md" \
     "$fixture/fixture-plugin/skills/$slug/skill.md" 2>/dev/null || true
done

# --- Fixture validity guard -------------------------------------------------
# Naive (pre-fix) collection must see at least DUPLICATED_SKILLS extra entries
# over the real file count. (The exact naive total is filesystem-dependent:
# case-insensitive doubles delta too, case-sensitive does not.) If this fails,
# the fixture is not exercising the bug and the assertions below would pass
# vacuously.
read -r naive_count inode_count <<EOF
$(python3 - "$fixture" <<'PY'
import os, sys
from pathlib import Path

root = Path(sys.argv[1])
naive = []
inodes = set()
for plugin_dir in sorted(root.glob("*-plugin")):
    skills_dir = plugin_dir / "skills"
    for pattern in ("SKILL.md", "skill.md"):
        for p in sorted(skills_dir.rglob(pattern)):
            # Pre-fix dedup: Path equality only.
            if p not in naive:
                naive.append(p)
            st = p.stat()
            inodes.add((st.st_dev, st.st_ino))
print(len(naive), len(inodes))
PY
)
EOF

echo "=== fixture validity ==="
echo "  naive_path_dedup_count=$naive_count distinct_inode_count=$inode_count"
assert "fixture has $DISTINCT_SKILLS distinct skill files" \
  "$([ "$inode_count" -eq "$DISTINCT_SKILLS" ] && echo true || echo false)"
assert "fixture reproduces the double-count (naive path dedup over-counts by >=$DUPLICATED_SKILLS)" \
  "$([ $((naive_count - inode_count)) -ge "$DUPLICATED_SKILLS" ] && echo true || echo false)"

# --- The regression assertions ----------------------------------------------
out="$(python3 "$fixture/scripts/audit-skill-descriptions.py" 2>&1)"
audited="$(printf '%s\n' "$out" | sed -n 's/^Audited \([0-9][0-9]*\) skills.*/\1/p')"

echo "=== audit run ==="
echo "  audited=$audited (expected $DISTINCT_SKILLS)"
assert "audited count equals the number of distinct files, not 2x" \
  "$([ "$audited" = "$DISTINCT_SKILLS" ] && echo true || echo false)"
assert "audited count is not the naive over-count ($naive_count)" \
  "$([ "$audited" != "$naive_count" ] && echo true || echo false)"

# The lowercase-only skill must still be discovered (case-sensitive FS path).
json="$(python3 "$fixture/scripts/audit-skill-descriptions.py" --json 2>&1)"
json_len="$(printf '%s' "$json" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo -1)"
slugs="$(printf '%s' "$json" | python3 -c 'import json,sys; print(",".join(sorted(r["skill"] for r in json.load(sys.stdin))))' 2>/dev/null || echo "")"

echo "=== discovery coverage ==="
echo "  json_rows=$json_len slugs=$slugs"
assert "--json emits one row per distinct file" \
  "$([ "$json_len" = "$DISTINCT_SKILLS" ] && echo true || echo false)"
assert "every fixture skill is discovered exactly once (incl. lowercase-only)" \
  "$([ "$slugs" = "alpha,beta,delta,gamma" ] && echo true || echo false)"

echo ""
echo "Passed: $pass_count, Failed: $fail_count"
[ "$fail_count" -eq 0 ]
