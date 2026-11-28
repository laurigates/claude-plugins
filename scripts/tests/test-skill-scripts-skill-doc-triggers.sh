#!/usr/bin/env bash
# Regression test for issue #3833: `Test: Skill scripts`
# (.github/workflows/test-skill-scripts.yml) must run for a PR that touches only
# a skill's markdown — SKILL.md, REFERENCE.md or references/**.
#
# Plugin-level suites under <plugin>/scripts/tests/ pin SKILL.md content (size
# caps, required phrases). #3804 changed only
# git-plugin/skills/release-please-configuration/SKILL.md, matched none of the
# workflow's `paths:` entries, skipped the suite, merged green, and left main red
# on test-skill-guidance-pins.sh. Splitting text out into REFERENCE.md or
# references/ moves the same size pins, so those paths are required too
# (decision on #3833, option 3).
#
# The check is semantic: each sample path must MATCH some pattern under GitHub's
# glob rules in both the pull_request and the push `paths:` lists, so a broader
# pattern that still covers it passes, and a dropped or narrowed one fails.
# CASE B replays the pre-fix trigger list and must go red, so CASE A's green is
# not the result of a matcher that accepts everything.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
workflow="$repo_root/.github/workflows/test-skill-scripts.yml"

pass_count=0
fail_count=0

assert() {
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}

if ! python3 -c 'import yaml' 2>/dev/null; then
  echo "FAIL: python3 with PyYAML is required" >&2
  exit 1
fi

fx="$(mktemp -d)"
[ -n "$fx" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$fx"' EXIT

# Prints one `<event> <path> MATCHED|UNMATCHED` line per (event, sample) pair.
# Exits 2 when the workflow has no paths: list for an event, so a restructured
# trigger block reads as a failure, not as "nothing to check".
check_workflow() {
  python3 - "$1" <<'PY'
import re
import sys

import yaml

SAMPLES = [
    "git-plugin/skills/release-please-configuration/SKILL.md",
    "git-plugin/skills/release-please-configuration/REFERENCE.md",
    "git-plugin/skills/release-please-configuration/references/monorepo.md",
    "testing-plugin/skills/test-tripwire/references/nested/deep.md",
]


def path_matches(pattern, path):
    """GitHub `paths:` glob: `**` crosses `/`, `*` and `?` do not."""
    out, i = [], 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out.append("(?:.*/)?")
            i += 3
        elif pattern.startswith("**", i):
            out.append(".*")
            i += 2
        elif pattern[i] == "*":
            out.append("[^/]*")
            i += 1
        elif pattern[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(pattern[i]))
            i += 1
    return re.fullmatch("".join(out), path) is not None


with open(sys.argv[1], encoding="utf-8") as fh:
    doc = yaml.safe_load(fh)
triggers = doc.get("on", doc.get(True)) or {}
rc = 0
for event in ("pull_request", "push"):
    paths = (triggers.get(event) or {}).get("paths") or []
    if not paths:
        print(f"{event} NO_PATHS")
        rc = 2
        continue
    for sample in SAMPLES:
        hit = any(path_matches(p, sample) for p in paths)
        print(f"{event} {sample} {'MATCHED' if hit else 'UNMATCHED'}")
sys.exit(rc)
PY
}

# --- CASE A: the real workflow covers skill markdown on both events ----------
echo "=== CASE A: test-skill-scripts.yml triggers on SKILL.md, REFERENCE.md, references/** ==="
out="$(check_workflow "$workflow")"; rc=$?
assert "A1: real workflow parses with a paths: list per event (rc=$rc)" "$([ $rc -eq 0 ] && echo true || echo false)"
assert "A2: eight (event, sample) rows were evaluated" "$([ "$(grep -c ' MATCHED$\| UNMATCHED$' <<<"$out")" = 8 ] && echo true || echo false)"
while read -r event sample verdict; do
  assert "A3: $event paths: matches $sample" "$([ "$verdict" = MATCHED ] && echo true || echo false)"
done < <(grep ' UNMATCHED$' <<<"$out")
assert "A4: no sample is left unmatched" "$(grep -q ' UNMATCHED$' <<<"$out" && echo false || echo true)"

# --- CASE B: the pre-#3833 trigger shape is caught ---------------------------
# Only the per-skill entries #3804 slipped past: SKILL.md generally is unmatched.
echo "=== CASE B: pre-fix paths: list leaves a SKILL.md-only PR untriggered ==="
cat > "$fx/pre-fix.yml" <<'EOF'
on:
  pull_request:
    paths:
      - '**/skills/**/scripts/**'
      - '**/skills/**/workflows/**'
      - '*-plugin/scripts/**'
      - 'comfyui-plugin/skills/comfy-registry-lifecycle/SKILL.md'
      - 'testing-plugin/skills/test-tripwire/SKILL.md'
      - 'health-plugin/skills/**/*.md'
  push:
    paths:
      - '**/skills/**/scripts/**'
      - '*-plugin/scripts/**'
EOF
out="$(check_workflow "$fx/pre-fix.yml")"
assert "B1: pre-fix pull_request list misses the #3804 SKILL.md" \
  "$(grep -qx 'pull_request git-plugin/skills/release-please-configuration/SKILL.md UNMATCHED' <<<"$out" && echo true || echo false)"
assert "B2: pre-fix list misses REFERENCE.md" \
  "$(grep -qx 'pull_request git-plugin/skills/release-please-configuration/REFERENCE.md UNMATCHED' <<<"$out" && echo true || echo false)"
assert "B3: pre-fix list misses references/**" \
  "$(grep -qx 'pull_request git-plugin/skills/release-please-configuration/references/monorepo.md UNMATCHED' <<<"$out" && echo true || echo false)"

# --- CASE C: coverage on pull_request alone is not enough --------------------
echo "=== CASE C: a push list without the entries is reported ==="
cat > "$fx/pr-only.yml" <<'EOF'
on:
  pull_request:
    paths:
      - '*-plugin/skills/**/SKILL.md'
      - '*-plugin/skills/**/REFERENCE.md'
      - '*-plugin/skills/**/references/**'
  push:
    paths:
      - '*-plugin/scripts/**'
EOF
out="$(check_workflow "$fx/pr-only.yml")"
assert "C1: pull_request rows all match" \
  "$(grep -qE '^pull_request .* UNMATCHED$' <<<"$out" && echo false || echo true)"
assert "C2: push rows are reported unmatched" \
  "$([ "$(grep -c '^push .* UNMATCHED$' <<<"$out")" = 4 ] && echo true || echo false)"

# --- CASE D: a missing paths: list is a failure, not a pass ------------------
echo "=== CASE D: no push paths: list exits 2 ==="
printf 'on:\n  pull_request:\n    paths:\n      - "**"\n' > "$fx/no-push.yml"
out="$(check_workflow "$fx/no-push.yml")"; rc=$?
assert "D1: missing push paths: exits 2" "$([ $rc -eq 2 ] && echo true || echo false)"
assert "D2: missing push paths: is named" "$(grep -qx 'push NO_PATHS' <<<"$out" && echo true || echo false)"

echo ""
echo "Passed: $pass_count  Failed: $fail_count"
[ "$fail_count" -eq 0 ]
