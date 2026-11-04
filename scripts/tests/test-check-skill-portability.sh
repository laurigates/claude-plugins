#!/usr/bin/env bash
# shellcheck disable=SC2088
# SC2088: the literal `~/repos/` is the identifier text the fixtures write and
# the checker matches; it must not expand.
# Regression test for scripts/check-skill-portability.sh (#3308).
#
# Shipped skills, agents and hooks named the maintainer's own repositories and
# checkout layout (`laurigates/gitops`, `~/repos/`) as things to act on; an
# agent in someone else's session reads those as instructions. The guard lists
# the identifiers in scripts/skill-portability.conf, holds today's hits in a
# per-(file, match) baseline that may only go down, and fails on any hit
# outside the baseline or the config's allowlist.
#
# Guards:
#   A. the real repo: no new hits, baseline hits reported as WARN, exit 0
#   B. a new hit (no baseline entry) is ERROR, with its path:line
#   C. a hit held by the baseline is WARN, exit 0
#   D. an allowlisted hit is OK and counted as allowed
#   E. a file above its baseline count is ERROR
#   F. a file below its baseline count is ERROR (stale_baseline);
#      --update-baseline lowers it and never raises one
#   G. an allowlist entry that matches nothing is ERROR (stale_allowlist)
#   H. an empty scope fails loudly (nothing_scanned), never a silent OK
#   I. out of scope: files outside skills/agents/hooks, and untracked files
#   J. agents/ and hooks/ are scanned, not only skills/
#   K. a fork's config replaces the identifier list
#   L. a mixed WARN + ERROR run names the ERROR row in REASON=
#   M. an invalid identifier regex or missing config is a usage error (exit 2)
set -uo pipefail

# An inherited GIT_DIR (pre-commit sets it) overrides `git -C` and would point
# every fixture at the real repo (#1745).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/check-skill-portability.sh"

pass_count=0
fail_count=0

assert() {
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    printf '    | %s\n' "${OUT//$'\n'/$'\n'    | }" >&2
    fail_count=$((fail_count + 1))
  fi
}

contains() { grep -q -- "$2" <<<"$1" && echo true || echo false; }
lacks() { grep -q -- "$2" <<<"$1" && echo false || echo true; }
rc_is() { [ "$RC" -eq "$1" ] && echo true || echo false; }
validates() {
  printf '%s\n' "$1" | bash "$repo_root/scripts/check-structured-output-contract.sh" --validate >/dev/null 2>&1 \
    && echo true || echo false
}

tmp_root="$(mktemp -d)" || { echo "mktemp failed" >&2; exit 1; }
if [ -z "$tmp_root" ] || [ ! -d "$tmp_root" ]; then
  echo "mktemp failed" >&2
  exit 1
fi
trap 'rm -rf "$tmp_root"' EXIT

# new_tree <name> -- a git fixture with one clean, tracked SKILL.md, a config
# listing two identifiers and an empty allowlist, and an empty baseline.
new_tree() {
  local root="$tmp_root/$1"
  mkdir -p "$root/demo-plugin/skills/demo"
  printf -- '---\nname: demo\ndescription: Fixture.\n---\n\n# Demo\n\nNothing specific here.\n' \
    >"$root/demo-plugin/skills/demo/SKILL.md"
  printf '%s\n' '# fixture identifiers' '[identifiers]' 'example-owner/infra' '~/repos/' '' '[allow]' \
    >"$root/portability.conf"
  : >"$root/baseline.txt"
  git -C "$root" init -q
  git -C "$root" add -- demo-plugin
  echo "$root"
}

# track <root> <relative path> <content> -- write a file and stage it.
track() {
  mkdir -p "$(dirname "$1/$2")"
  printf '%s\n' "$3" >"$1/$2"
  git -C "$1" add -- "$2"
}

run() {
  OUT="$(bash "$checker" --project-dir "$1" --config "$1/portability.conf" --baseline "$1/baseline.txt" "${@:2}" 2>&1)"
  RC=$?
}

tab=$'\t'

echo "=== TEST A: real repo has no new hits ==="
OUT="$(bash "$checker" 2>&1)"
RC=$?
assert "A: real repo exits 0" "$(rc_is 0)"
assert "A: real repo reports NEW_HITS=0" "$(contains "$OUT" '^NEW_HITS=0$')"
assert "A: real repo reports its baseline hits as WARN" "$(contains "$OUT" '^STATUS=WARN$')"
assert "A: real repo scanned files" "$(lacks "$OUT" '^FILES_SCANNED=0$')"
assert "A: real repo output satisfies the contract" "$(validates "$OUT")"

echo "=== TEST B: a new hit is ERROR ==="
t="$(new_tree b)"
track "$t" demo-plugin/skills/demo/references/setup.md 'Clone example-owner/infra and run the apply.'
run "$t"
assert "B: exits 1" "$(rc_is 1)"
assert "B: STATUS=ERROR" "$(contains "$OUT" '^STATUS=ERROR$')"
assert "B: TYPE=new_hit" "$(contains "$OUT" 'TYPE=new_hit')"
assert "B: HIT names path:line" "$(contains "$OUT" '^HIT=demo-plugin/skills/demo/references/setup.md:1:')"
assert "B: NEW_HITS=1" "$(contains "$OUT" '^NEW_HITS=1$')"
assert "B: output satisfies the contract" "$(validates "$OUT")"

echo "=== TEST C: a baseline hit warns ==="
t="$(new_tree c)"
track "$t" demo-plugin/skills/demo/SKILL.md 'See ~/repos/ for the checkout.'
printf 'demo-plugin/skills/demo/SKILL.md%s~/repos/%s1\n' "$tab" "$tab" >"$t/baseline.txt"
run "$t"
assert "C: exits 0" "$(rc_is 0)"
assert "C: STATUS=WARN" "$(contains "$OUT" '^STATUS=WARN$')"
assert "C: TYPE=baseline_hit" "$(contains "$OUT" 'TYPE=baseline_hit')"
assert "C: BASELINE_HITS=1" "$(contains "$OUT" '^BASELINE_HITS=1$')"
assert "C: output satisfies the contract" "$(validates "$OUT")"

echo "=== TEST D: an allowlisted hit passes ==="
t="$(new_tree d)"
track "$t" demo-plugin/skills/demo/SKILL.md 'Found while fixing example-owner/infra (provenance).'
printf 'demo-plugin/skills/demo/SKILL.md%sexample-owner/infra%sprovenance line, not an instruction\n' "$tab" "$tab" \
  >>"$t/portability.conf"
run "$t"
assert "D: exits 0" "$(rc_is 0)"
assert "D: STATUS=OK" "$(contains "$OUT" '^STATUS=OK$')"
assert "D: ALLOWED_HITS=1" "$(contains "$OUT" '^ALLOWED_HITS=1$')"
assert "D: no REASON on OK" "$(lacks "$OUT" '^REASON=')"
assert "D: output satisfies the contract" "$(validates "$OUT")"

echo "=== TEST E: above the baseline count is ERROR ==="
t="$(new_tree e)"
track "$t" demo-plugin/skills/demo/SKILL.md "$(printf 'cd ~/repos/a\ncd ~/repos/b')"
printf 'demo-plugin/skills/demo/SKILL.md%s~/repos/%s1\n' "$tab" "$tab" >"$t/baseline.txt"
run "$t"
assert "E: exits 1" "$(rc_is 1)"
assert "E: TYPE=new_hit" "$(contains "$OUT" 'TYPE=new_hit')"
assert "E: NEW_HITS=1" "$(contains "$OUT" '^NEW_HITS=1$')"

echo "=== TEST F: below the baseline count is ERROR; --update-baseline only lowers ==="
t="$(new_tree f)"
track "$t" demo-plugin/skills/demo/SKILL.md 'cd ~/repos/a'
printf 'demo-plugin/skills/demo/SKILL.md%s~/repos/%s3\n' "$tab" "$tab" >"$t/baseline.txt"
run "$t"
assert "F: stale baseline exits 1" "$(rc_is 1)"
assert "F: TYPE=stale_baseline" "$(contains "$OUT" 'TYPE=stale_baseline')"
assert "F: output satisfies the contract" "$(validates "$OUT")"
run "$t" --update-baseline
assert "F: --update-baseline then reports WARN" "$(contains "$OUT" '^STATUS=WARN$')"
assert "F: baseline lowered to 1" "$(contains "$(cat "$t/baseline.txt")" "^demo-plugin/skills/demo/SKILL.md${tab}~/repos/${tab}1$")"
track "$t" demo-plugin/skills/demo/SKILL.md "$(printf 'cd ~/repos/a\ncd ~/repos/b')"
run "$t" --update-baseline
assert "F: --update-baseline never raises (still ERROR)" "$(rc_is 1)"
assert "F: baseline still 1" "$(contains "$(cat "$t/baseline.txt")" "^demo-plugin/skills/demo/SKILL.md${tab}~/repos/${tab}1$")"

echo "=== TEST G: a stale allowlist entry is ERROR ==="
t="$(new_tree g)"
printf 'demo-plugin/skills/demo/SKILL.md%sexample-owner/infra%sgone\n' "$tab" "$tab" >>"$t/portability.conf"
run "$t"
assert "G: exits 1" "$(rc_is 1)"
assert "G: TYPE=stale_allowlist" "$(contains "$OUT" 'TYPE=stale_allowlist')"

echo "=== TEST H: an empty scope fails loudly ==="
t="$tmp_root/h"
mkdir -p "$t/docs"
printf '%s\n' '[identifiers]' '~/repos/' >"$t/portability.conf"
: >"$t/baseline.txt"
printf 'nothing\n' >"$t/docs/x.md"
git -C "$t" init -q
git -C "$t" add -- docs
run "$t"
assert "H: exits 1" "$(rc_is 1)"
assert "H: TYPE=nothing_scanned" "$(contains "$OUT" 'TYPE=nothing_scanned')"

echo "=== TEST I: out-of-scope and untracked files are not scanned ==="
t="$(new_tree i)"
track "$t" demo-plugin/README.md 'cd ~/repos/x'
track "$t" scripts/tool.sh 'cd ~/repos/x'
printf 'cd ~/repos/x\n' >"$t/demo-plugin/skills/demo/untracked.md"
run "$t"
assert "I: exits 0" "$(rc_is 0)"
assert "I: STATUS=OK" "$(contains "$OUT" '^STATUS=OK$')"
assert "I: HITS_TOTAL=0" "$(contains "$OUT" '^HITS_TOTAL=0$')"

echo "=== TEST J: agents/ and hooks/ are scanned ==="
t="$(new_tree j)"
track "$t" demo-plugin/agents/runner.md 'Push to example-owner/infra.'
track "$t" demo-plugin/hooks/guard.sh 'cd ~/repos/infra'
run "$t"
assert "J: exits 1" "$(rc_is 1)"
assert "J: agent hit reported" "$(contains "$OUT" '^HIT=demo-plugin/agents/runner.md:1:')"
assert "J: hook hit reported" "$(contains "$OUT" '^HIT=demo-plugin/hooks/guard.sh:1:')"
assert "J: NEW_HITS=2" "$(contains "$OUT" '^NEW_HITS=2$')"

echo "=== TEST K: a fork's config replaces the identifier list ==="
t="$(new_tree k)"
track "$t" demo-plugin/skills/demo/SKILL.md "$(printf 'Run in acme/platform.\nSee laurigates/gitops.')"
printf '%s\n' '[identifiers]' 'acme/platform' >"$t/portability.conf"
run "$t"
assert "K: the fork's identifier is flagged" "$(contains "$OUT" '^HIT=demo-plugin/skills/demo/SKILL.md:1:')"
assert "K: identifiers not in the config are not flagged" "$(lacks "$OUT" '^HIT=demo-plugin/skills/demo/SKILL.md:2:')"
assert "K: IDENTIFIER_PATTERNS=1" "$(contains "$OUT" '^IDENTIFIER_PATTERNS=1$')"

echo "=== TEST L: mixed WARN + ERROR names the ERROR row ==="
t="$(new_tree l)"
track "$t" demo-plugin/skills/demo/SKILL.md 'See ~/repos/ for the checkout.'
track "$t" demo-plugin/skills/demo/zz.md 'Clone example-owner/infra.'
printf 'demo-plugin/skills/demo/SKILL.md%s~/repos/%s1\n' "$tab" "$tab" >"$t/baseline.txt"
run "$t"
assert "L: exits 1" "$(rc_is 1)"
assert "L: REASON names the new hit" "$(contains "$OUT" '^REASON=new_hit:')"
assert "L: output satisfies the contract" "$(validates "$OUT")"

echo "=== TEST M: usage errors exit 2 ==="
t="$(new_tree m)"
printf '%s\n' '[identifiers]' 'broken(' >"$t/portability.conf"
run "$t"
assert "M: invalid regex exits 2" "$(rc_is 2)"
OUT="$(bash "$checker" --project-dir "$t" --config "$t/missing.conf" --baseline "$t/baseline.txt" 2>&1)"
RC=$?
assert "M: missing config exits 2" "$(rc_is 2)"

echo
echo "passed: $pass_count  failed: $fail_count"
[ "$fail_count" -eq 0 ]
