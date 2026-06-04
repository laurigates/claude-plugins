#!/usr/bin/env bash
# Regression test for scripts/check-version-pin-coverage.sh
# (.claude/rules/version-pinning.md — the trivy SHA-mismatch class).
#
# Guards:
#   A. the real repo stays ERROR-free — every executable pin is in a
#      Renovate-managed shape, so --strict exits 0
#   B. a version-shaped 'uses:' ref in an unmanaged shape is flagged ERROR and
#      --strict exits 1 (the silent-drift case the guard exists to catch)
#   C. managed shapes (tag form + SHA-with-version-comment) are NOT flagged
#   D. version numbers in prose (outside code fences) are ignored by design
#   E. floating refs (@main) are intentionally not flagged
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/check-version-pin-coverage.sh"

pass_count=0
fail_count=0

assert() {
  # assert <description> <condition-result-string "true"/"false">
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}

field() { printf '%s\n' "$1" | grep -m1 "^$2=" | cut -d= -f2; }
contains() { printf '%s' "$1" | grep -q "$2" && echo true || echo false; }

echo "=== TEST A: real repo is ERROR-free ==="
real_out="$(bash "$checker" --project-dir "$repo_root")"
assert "real repo STATUS should not be ERROR" \
  "$([ "$(field "$real_out" STATUS)" != "ERROR" ] && echo true || echo false)"
clean_rc=0
bash "$checker" --project-dir "$repo_root" --strict >/dev/null || clean_rc=$?
assert "--strict should exit 0 on the real repo" \
  "$([ "$clean_rc" -eq 0 ] && echo true || echo false)"

# --- Build a synthetic fixture with one uncovered pin -------------------------
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/demo-plugin/skills/demo"

cat > "$fixture/demo-plugin/skills/demo/SKILL.md" <<'EOF'
# Demo

Managed tag form:

```yaml
- uses: actions/checkout@v5
```

Managed SHA + version comment:

```yaml
- uses: actions/setup-node@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v5.0.0
```

Floating ref (intentionally unpinned):

```yaml
- uses: trufflesecurity/trufflehog@main
```

Unmanaged version-shaped ref (should be flagged):

```yaml
- uses: foo/bar@1
```

A version in a prose table is illustrative, not executable:

| Tool | Version |
|------|---------|
| widget | uses: foo/bar@1 |
EOF

echo "=== TEST B: uncovered uses: ref flagged + --strict exit ==="
fx_out="$(bash "$checker" --project-dir "$fixture")"
assert "foo/bar@1 inside a fence should be flagged uses_uncovered" \
  "$(contains "$fx_out" "uses_uncovered")"
assert "fixture STATUS should be ERROR" \
  "$([ "$(field "$fx_out" STATUS)" = "ERROR" ] && echo true || echo false)"
strict_rc=0
bash "$checker" --project-dir "$fixture" --strict >/dev/null || strict_rc=$?
assert "--strict should exit 1 on uncovered pin" \
  "$([ "$strict_rc" -eq 1 ] && echo true || echo false)"

echo "=== TEST C: managed shapes counted, not flagged ==="
assert "tag form counts toward USES_COVERED (>=2 covered)" \
  "$([ "$(field "$fx_out" USES_COVERED)" -ge 2 ] && echo true || echo false)"

echo "=== TEST D: exactly one ERROR (prose copy is ignored) ==="
err_lines="$(printf '%s\n' "$fx_out" | grep -c 'SEVERITY=ERROR' || true)"
assert "only the fenced foo/bar@1 is flagged, not the prose-table copy" \
  "$([ "$err_lines" -eq 1 ] && echo true || echo false)"

echo "=== TEST E: floating @main not flagged ==="
assert "trufflehog@main produces no issue" \
  "$([ "$(contains "$fx_out" "trufflehog")" = "false" ] && echo true || echo false)"

# --- TEST F: .claude/worktrees/ copies are pruned from the walk (issue #1492) -
# Worktree copies are full repo clones; without the prune every skill file is
# scanned once per active worktree (499 real files became 12,768 with worktrees
# present). Adding a skill under .claude/worktrees/<x>/ must NOT change the
# files-scanned count, nor leak its uncovered pin into the report.
echo "=== TEST F: .claude/worktrees/ copies are not scanned ==="
files_before="$(field "$fx_out" FILES_SCANNED)"
mkdir -p "$fixture/.claude/worktrees/agent-deadbeef/demo-plugin/skills/demo"
cat > "$fixture/.claude/worktrees/agent-deadbeef/demo-plugin/skills/demo/SKILL.md" <<'EOF'
# Leaked worktree copy

```yaml
- uses: leaked/from-worktree@1
```
EOF
fx_out_wt="$(bash "$checker" --project-dir "$fixture")"
files_after="$(field "$fx_out_wt" FILES_SCANNED)"
assert "FILES_SCANNED unchanged when a worktree copy is added ($files_before == $files_after)" \
  "$([ "$files_before" = "$files_after" ] && echo true || echo false)"
assert "worktree-copy pin does not leak into the report" \
  "$([ "$(contains "$fx_out_wt" "from-worktree")" = "false" ] && echo true || echo false)"

echo ""
echo "=== SUMMARY ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then echo "STATUS=FAIL"; exit 1; fi
echo "STATUS=OK"
