#!/usr/bin/env bash
# Regression test for scripts/check-positional-references.sh.
#
# The 2026-10 SKILL.md split sweep moved reference material into
# `references/*.md`, leaving pointers such as "Preview Bridge swallows
# ExecutionBlocker -- see above" aimed at text that no longer exists in the
# file they live in. The guard is a hard error in reference files and a
# per-file ratchet on SKILL.md.
#
# Guards:
#   A. the real repo is clean (strict files at 0, every SKILL.md within baseline)
#   B. detect: a direction pointer in references/*.md / REFERENCE.md is ERROR,
#      including the comfy-debug-preview defect shape and a wrapped "see\nbelow"
#   C. exempt: fenced code, inline code, quoted phrase, blockquote, prepositional
#      uses (below 10,000 chars / above the threshold, also across a line wrap),
#      none of the above, a link that already carries its anchor, time words
#   D. ratchet up: a SKILL.md above its baseline, or new and non-zero, is ERROR
#   E. ratchet down: a SKILL.md below its baseline is ERROR (stale_baseline);
#      --update-baseline lowers it and never raises one
#   F. a baseline entry for a file that is gone is ERROR
#   G. an empty tree fails loudly (nothing_scanned), never a silent OK
#   H. templates/, fixtures/ and .claude/worktrees/ are not scanned
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/check-positional-references.sh"

if ! command -v uv >/dev/null 2>&1; then
  echo "SKIP: uv not on PATH (the checker parses markdown via scripts/lib/extract-md-elements.py)"
  exit 0
fi

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

run() {
  OUT="$(bash "$checker" --project-dir "$1" --baseline "$2" "${@:3}" 2>&1)"
  RC=$?
}

tmp_root="$(mktemp -d)"
if [ -z "$tmp_root" ] || [ ! -d "$tmp_root" ]; then
  echo "mktemp failed" >&2
  exit 1
fi
trap 'rm -rf "$tmp_root"' EXIT

# new_tree <name> -- a fixture repo with one plugin and one clean SKILL.md.
new_tree() {
  local root="$tmp_root/$1"
  mkdir -p "$root/demo-plugin/skills/demo/references"
  printf -- '---\nname: demo\ndescription: Fixture.\n---\n\n# Demo\n\nNothing positional here.\n' \
    >"$root/demo-plugin/skills/demo/SKILL.md"
  : >"$root/baseline.txt"
  echo "$root"
}

echo "=== TEST A: real repo is clean ==="
OUT="$(bash "$checker" 2>&1)"
RC=$?
assert "real repo exits 0" "$(rc_is 0)"
assert "real repo STATUS=OK" "$(contains "$OUT" '^STATUS=OK$')"
assert "real repo has zero strict hits" "$(contains "$OUT" '^STRICT_HITS=0$')"
assert "real repo output satisfies the contract" "$(validates "$OUT")"

echo "=== TEST B: a direction pointer in a reference file is ERROR ==="
root="$(new_tree b)"
cat >"$root/demo-plugin/skills/demo/references/gotchas.md" <<'EOF'
# Gotchas

- **`Preview Bridge` swallows `ExecutionBlocker`** — see above.
- The kill switches that work are in the table
below.
EOF
cat >"$root/demo-plugin/skills/demo/REFERENCE.md" <<'EOF'
# Reference

The table above covers the burst limit.
EOF
run "$root" "$root/baseline.txt"
assert "reference-file hits exit 1" "$(rc_is 1)"
assert "STATUS=ERROR" "$(contains "$OUT" '^STATUS=ERROR$')"
assert "the defect shape is named with its line" \
  "$(contains "$OUT" 'TYPE=positional_reference MSG=demo-plugin/skills/demo/references/gotchas.md:3 ')"
assert "a pointer wrapped onto its own line is caught" \
  "$(contains "$OUT" 'references/gotchas.md:5 ')"
assert "REFERENCE.md is strict too" "$(contains "$OUT" 'skills/demo/REFERENCE.md:3 ')"
assert "three hits counted" "$(contains "$OUT" '^ISSUE_COUNT=3$')"
assert "REASON names the first hit and the rest" "$(contains "$OUT" '^REASON=positional_reference: .* (+2 more)$')"
assert "failing output satisfies the contract" "$(validates "$OUT")"

echo "=== TEST C: exempt shapes stay silent ==="
root="$(new_tree c)"
cat >"$root/demo-plugin/skills/demo/references/clean.md" <<'EOF'
# Clean

```bash
# see above. Fenced code is skipped.
```

Inline `see above` is code, and "the table above" is a quoted phrase.

> A blockquote may say see above.

Keep the body below 10,000 chars and the score above the threshold. A skill
sits below
10,000 chars after the split.

None of the above applies. Same as above.

See [§ Gotchas](#gotchas) below for the details.

Earlier versions did this; later releases fixed it. Run the following steps:

1. One.
EOF
run "$root" "$root/baseline.txt"
assert "exempt shapes exit 0" "$(rc_is 0)"
assert "exempt shapes STATUS=OK" "$(contains "$OUT" '^STATUS=OK$')"
assert "OK carries no REASON" "$(lacks "$OUT" '^REASON=')"
assert "passing output satisfies the contract" "$(validates "$OUT")"

echo "=== TEST D: SKILL.md ratchet holds each file at its baseline ==="
root="$(new_tree d)"
printf -- '---\nname: demo\ndescription: Fixture.\n---\n\nSee the table above. Use the steps below.\n' \
  >"$root/demo-plugin/skills/demo/SKILL.md"
printf 'demo-plugin/skills/demo/SKILL.md\t1\n' >"$root/baseline.txt"
run "$root" "$root/baseline.txt"
assert "2 hits over a baseline of 1 exits 1" "$(rc_is 1)"
assert "ratchet_exceeded is reported" \
  "$(contains "$OUT" 'TYPE=ratchet_exceeded MSG=demo-plugin/skills/demo/SKILL.md has 2 positional reference(s), baseline 1')"
assert "the over-baseline file's hits are listed" "$(contains "$OUT" '^HIT=demo-plugin/skills/demo/SKILL.md:6: ')"
assert "ratchet failure satisfies the contract" "$(validates "$OUT")"
printf 'demo-plugin/skills/demo/SKILL.md\t2\n' >"$root/baseline.txt"
run "$root" "$root/baseline.txt"
assert "at its baseline exits 0" "$(rc_is 0)"
assert "within-baseline hits are not listed without --verbose" "$(lacks "$OUT" '^HIT=')"
mkdir -p "$root/demo-plugin/skills/fresh"
printf -- '---\nname: fresh\ndescription: Fixture.\n---\n\nSee above.\n' >"$root/demo-plugin/skills/fresh/SKILL.md"
run "$root" "$root/baseline.txt"
assert "a new SKILL.md starts at 0" "$(contains "$OUT" 'skills/fresh/SKILL.md has 1 positional reference(s), baseline 0')"

echo "=== TEST E: below-baseline is stale; --update-baseline only lowers ==="
root="$(new_tree e)"
printf -- '---\nname: demo\ndescription: Fixture.\n---\n\nSee the table above.\n' \
  >"$root/demo-plugin/skills/demo/SKILL.md"
printf 'demo-plugin/skills/demo/SKILL.md\t3\n' >"$root/baseline.txt"
run "$root" "$root/baseline.txt"
assert "1 hit under a baseline of 3 exits 1" "$(rc_is 1)"
assert "stale_baseline is reported" \
  "$(contains "$OUT" 'TYPE=stale_baseline MSG=demo-plugin/skills/demo/SKILL.md is at 1, below its baseline 3')"
run "$root" "$root/baseline.txt" --update-baseline
assert "--update-baseline then passes" "$(rc_is 0)"
assert "--update-baseline lowered the entry to 1" \
  "$(grep -qx "$(printf 'demo-plugin/skills/demo/SKILL.md\t1')" "$root/baseline.txt" && echo true || echo false)"
printf -- '---\nname: demo\ndescription: Fixture.\n---\n\nSee above. See below. The table above.\n' \
  >"$root/demo-plugin/skills/demo/SKILL.md"
run "$root" "$root/baseline.txt" --update-baseline
assert "--update-baseline does not raise a breached entry" "$(rc_is 1)"
assert "the entry is still 1 after the attempted raise" \
  "$(grep -qx "$(printf 'demo-plugin/skills/demo/SKILL.md\t1')" "$root/baseline.txt" && echo true || echo false)"

echo "=== TEST F: an entry for a vanished file is stale ==="
root="$(new_tree f)"
printf 'demo-plugin/skills/gone/SKILL.md\t2\n' >"$root/baseline.txt"
run "$root" "$root/baseline.txt"
assert "vanished-file entry exits 1" "$(rc_is 1)"
assert "vanished-file entry is stale_baseline" "$(contains "$OUT" 'skills/gone/SKILL.md is in the baseline but was not scanned')"

echo "=== TEST G: an empty tree fails loudly ==="
root="$tmp_root/g"
mkdir -p "$root/demo-plugin"
: >"$tmp_root/g-baseline.txt"
run "$root" "$tmp_root/g-baseline.txt"
assert "empty tree exits 1" "$(rc_is 1)"
assert "empty tree is nothing_scanned" "$(contains "$OUT" 'TYPE=nothing_scanned')"
assert "empty tree says SCANNED_EMPTY=true" "$(contains "$OUT" '^SCANNED_EMPTY=true$')"
assert "empty-tree output satisfies the contract" "$(validates "$OUT")"

echo "=== TEST H: templates/, fixtures/, .claude/worktrees/ are not scanned ==="
root="$(new_tree h)"
for sub in templates fixtures .claude/worktrees/agent-x; do
  mkdir -p "$root/demo-plugin/skills/demo/$sub"
  printf '# T\n\nSee above.\n' >"$root/demo-plugin/skills/demo/$sub/x.md"
done
run "$root" "$root/baseline.txt"
assert "pruned directories exit 0" "$(rc_is 0)"
assert "only the SKILL.md was scanned" "$(contains "$OUT" '^FILES_SCANNED=1$')"

echo ""
echo "=== SUMMARY: $pass_count passed, $fail_count failed ==="
[ "$fail_count" -eq 0 ]
