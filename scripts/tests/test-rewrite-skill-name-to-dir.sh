#!/usr/bin/env bash
# Regression test for scripts/rewrite-skill-name-to-dir.py and its wiring into the
# OpenCode export/install pipeline.
#
# Motivating bug: `opencode` validates skill frontmatter strictly —
#   1. `name` must match [a-z0-9-]+
#   2. `name` must equal the skill's directory name
# Four exported skills failed at launch: `UnoCSS`/`Lightning CSS` (rule 1) and
# `refocus`/`ground-response` in plugin-prefixed dirs (rule 2). The fix rewrites
# each staged skill's `name` to its directory basename during export.
#
# Guards:
#   A. an invalid display-style name (UnoCSS) is rewritten to the dir basename
#   B. an unprefixed name (refocus) in a prefixed dir is rewritten to the dir
#   C. a name already equal to the dir is left untouched (idempotent)
#   D. --check exits 1 when a rewrite is needed, 0 when clean
#   E. the rewritten frontmatter is valid YAML and opencode-name-valid
#   F. export-opencode.sh still invokes the rewrite step (wiring not dropped)
#   G. install-opencode.sh still carries the cross-scope duplicate guard
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
rewriter="$repo_root/scripts/rewrite-skill-name-to-dir.py"

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
name_of() { grep -m1 '^name:' "$1" | sed 's/^name:[[:space:]]*//'; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Fixtures: (dir, original-name)
mk_skill() {
  mkdir -p "$tmp/$1"
  printf -- '---\nname: %s\ndescription: x. Use when y.\nallowed-tools: Read\n---\n\n# body\n' \
    "$2" > "$tmp/$1/SKILL.md"
}
mk_skill unocss "UnoCSS"
mk_skill project-refocus "refocus"
mk_skill git-push "git-push"

echo "=== TEST D: --check exits 1 on needed rewrite ==="
check_rc=0
python3 "$rewriter" --check "$tmp"/*/SKILL.md >/dev/null 2>&1 || check_rc=$?
assert "--check should exit 1 when rewrites are pending" \
  "$([ "$check_rc" -eq 1 ] && echo true || echo false)"

echo "=== apply rewrite ==="
python3 "$rewriter" "$tmp"/*/SKILL.md >/dev/null 2>&1

echo "=== TEST A: invalid display name -> dir basename ==="
assert "unocss name rewritten to 'unocss'" \
  "$([ "$(name_of "$tmp/unocss/SKILL.md")" = "unocss" ] && echo true || echo false)"

echo "=== TEST B: unprefixed name -> prefixed dir basename ==="
assert "project-refocus name rewritten to 'project-refocus'" \
  "$([ "$(name_of "$tmp/project-refocus/SKILL.md")" = "project-refocus" ] && echo true || echo false)"

echo "=== TEST C: matching name left untouched ==="
assert "git-push name unchanged" \
  "$([ "$(name_of "$tmp/git-push/SKILL.md")" = "git-push" ] && echo true || echo false)"

echo "=== TEST D2: --check exits 0 after rewrite (idempotent) ==="
check_rc=0
python3 "$rewriter" --check "$tmp"/*/SKILL.md >/dev/null 2>&1 || check_rc=$?
assert "--check should exit 0 when clean" \
  "$([ "$check_rc" -eq 0 ] && echo true || echo false)"

echo "=== TEST E: rewritten frontmatter is valid + opencode-name-valid ==="
e_ok="true"
for f in "$tmp"/*/SKILL.md; do
  d="$(basename "$(dirname "$f")")"
  python3 - "$f" "$d" <<'PY' || e_ok="false"
import re, sys, yaml
f, d = sys.argv[1], sys.argv[2]
fm = re.match(r"^---\n(.*?)\n---", open(f).read(), re.S).group(1)
data = yaml.safe_load(fm)
name = data["name"]
assert re.fullmatch(r"[a-z0-9-]+", name), f"invalid name {name!r}"
assert name == d, f"name {name!r} != dir {d!r}"
PY
done
assert "all rewritten skills are valid YAML and opencode-name-valid" "$e_ok"

echo "=== TEST F: export-opencode.sh invokes the rewrite step ==="
assert "export wiring present" \
  "$(grep -q 'rewrite-skill-name-to-dir.py' "$repo_root/scripts/export-opencode.sh" && echo true || echo false)"

echo "=== TEST G: install-opencode.sh carries the cross-scope duplicate guard ==="
assert "install cross-scope guard present" \
  "$(grep -q 'DUPLICATE_SCOPE_DETECTED' "$repo_root/scripts/install-opencode.sh" && echo true || echo false)"

echo "=== RESULTS: $pass_count passed, $fail_count failed ==="
[ "$fail_count" -eq 0 ]
