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
#   G. transitive-pin gap (#2175): a SHA-pinned installer action whose own
#      `version:` input is absent or floating is flagged ERROR, while the same
#      step with an explicit tag is not — the pin must cover the BINARY, not
#      just the wrapper
#   H. the gitignored dist/ rulesync build output is pruned, not scanned
#      (#2214) — with a guard-integrity half proving the same defective pin at
#      a real path is still reported
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

echo "=== TEST F: .claude/worktrees/ copies are pruned, not scanned (#1492) ==="
# A sibling agent's worktree checkout is a full repo copy under
# .claude/worktrees/. Adding a skill file there must NOT change FILES_SCANNED
# (the guard audits only the real tree) and must NOT re-flag its uncovered pin.
before_scanned="$(field "$fx_out" FILES_SCANNED)"
before_errors="$(printf '%s\n' "$fx_out" | grep -c 'SEVERITY=ERROR' || true)"
mkdir -p "$fixture/.claude/worktrees/agent-deadbeef/demo-plugin/skills/demo"
cp "$fixture/demo-plugin/skills/demo/SKILL.md" \
   "$fixture/.claude/worktrees/agent-deadbeef/demo-plugin/skills/demo/SKILL.md"
wt_out="$(bash "$checker" --project-dir "$fixture")"
assert "FILES_SCANNED unchanged after adding a worktree copy" \
  "$([ "$(field "$wt_out" FILES_SCANNED)" -eq "$before_scanned" ] && echo true || echo false)"
assert "no extra ERROR from the worktree copy's uncovered pin" \
  "$([ "$(printf '%s\n' "$wt_out" | grep -c 'SEVERITY=ERROR' || true)" -eq "$before_errors" ] && echo true || echo false)"
assert "no WARN/ERROR issue references a .claude/worktrees/ path" \
  "$([ "$(contains "$wt_out" '.claude/worktrees/')" = "false" ] && echo true || echo false)"

echo "=== TEST G: transitive binary pin — version: input (#2175) ==="
# A SHA-pinned `uses:` pins the composite action, NOT the binary its installer
# downloads. Connorrmcd6/surface's action.yml declares `version:` with
# `default: latest`, so a step that omits the input (or sets a floating value)
# ships a workflow that reads as fully pinned while installing a fresh binary on
# every run. Kept in its own fixture so TEST D's exact-ERROR-count and TEST F's
# worktree-prune assertions stay independent of these cases.
fixture_bad="$(mktemp -d)"
[ -n "$fixture_bad" ] || { echo "FAIL: mktemp -d returned empty" >&2; exit 1; }
fixture_good="$(mktemp -d)"
[ -n "$fixture_good" ] || { echo "FAIL: mktemp -d returned empty" >&2; exit 1; }
trap 'rm -rf "$fixture" "$fixture_bad" "$fixture_good"' EXIT

mkdir -p "$fixture_bad/demo-plugin/skills/demo"
cat > "$fixture_bad/demo-plugin/skills/demo/SKILL.md" <<'EOF'
# Demo

Absent version input — the defect shape reported in #2175:

```yaml
- uses: Connorrmcd6/surface@091b937ae34ac81a02386604fed977dd24f1f0cf # v0.8.0
  with:
    args: check
```

Present but floating — same outcome, stated out loud:

```yaml
- uses: Connorrmcd6/surface@091b937ae34ac81a02386604fed977dd24f1f0cf # v0.8.0
  with:
    version: latest
    args: check
```
EOF

mkdir -p "$fixture_good/demo-plugin/skills/demo"
cat > "$fixture_good/demo-plugin/skills/demo/SKILL.md" <<'EOF'
# Demo

Both pins present — the corrected shape:

```yaml
- uses: Connorrmcd6/surface@091b937ae34ac81a02386604fed977dd24f1f0cf # v0.8.0
  with:
    version: v0.8.0
    args: check
```

A non-installer action needs no version input (guard integrity — this must not
become "every pinned action must declare a version"):

```yaml
- uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v5.0.0
  with:
    fetch-depth: 1
```

An action outside the curated installer list keeps its floating `version:` — a
toolchain setup action tracking the latest release is a deliberate choice, not a
gate-stability hazard, and flagging it would make the guard opine on files a
reporting PR never touched:

```yaml
- uses: astral-sh/setup-uv@e92bafb6253dcd438e0484186d7669ea7a8ca1cc # v6.4.3
  with:
    version: "latest"
```
EOF

bad_out="$(bash "$checker" --project-dir "$fixture_bad")"
assert "absent version: input is flagged version_input_missing" \
  "$(contains "$bad_out" "version_input_missing")"
assert "version: latest is flagged version_input_floating" \
  "$(contains "$bad_out" "version_input_floating")"
assert "bad fixture STATUS should be ERROR" \
  "$([ "$(field "$bad_out" STATUS)" = "ERROR" ] && echo true || echo false)"
assert "exactly two ERRORs in the bad fixture (one per defect shape)" \
  "$([ "$(printf '%s\n' "$bad_out" | grep -c 'SEVERITY=ERROR' || true)" -eq 2 ] && echo true || echo false)"
bad_rc=0
bash "$checker" --project-dir "$fixture_bad" --strict >/dev/null || bad_rc=$?
assert "--strict should exit 1 on an unpinned binary version" \
  "$([ "$bad_rc" -eq 1 ] && echo true || echo false)"

good_out="$(bash "$checker" --project-dir "$fixture_good")"
assert "explicit version: tag, bare checkout, and off-list floating are all unflagged" \
  "$([ "$(contains "$good_out" "version_input")" = "false" ] && echo true || echo false)"
assert "good fixture STATUS should not be ERROR" \
  "$([ "$(field "$good_out" STATUS)" != "ERROR" ] && echo true || echo false)"
assert "explicit version: tag counts toward VERSION_INPUT_COVERED" \
  "$([ "$(field "$good_out" VERSION_INPUT_COVERED)" -ge 1 ] && echo true || echo false)"
good_rc=0
bash "$checker" --project-dir "$fixture_good" --strict >/dev/null || good_rc=$?
assert "--strict should exit 0 when both pins are present" \
  "$([ "$good_rc" -eq 0 ] && echo true || echo false)"

echo "=== TEST H: dist/ build output is pruned, not scanned (#2214) ==="
# dist/ is the GITIGNORED rulesync export — a generated copy of the same skill
# tree. A finding there is unactionable by construction (the fix site is always
# the source skill, and the next `just export-opencode` overwrites it), and a
# stale local dist/ hard-ERRORs every local commit while CI — which never has a
# dist/ — stays green. Same class as TEST F's worktree prune (#1492): a walk
# descending into a copy of the repo.
before_scanned_h="$(field "$wt_out" FILES_SCANNED)"
before_errors_h="$(printf '%s\n' "$wt_out" | grep -c 'SEVERITY=ERROR' || true)"
mkdir -p "$fixture/dist/opencode/skills/demo"
cp "$fixture/demo-plugin/skills/demo/SKILL.md" \
   "$fixture/dist/opencode/skills/demo/SKILL.md"
dist_out="$(bash "$checker" --project-dir "$fixture")"
assert "FILES_SCANNED unchanged after adding a dist/ export copy" \
  "$([ "$(field "$dist_out" FILES_SCANNED)" -eq "$before_scanned_h" ] && echo true || echo false)"
assert "no extra ERROR from the dist/ copy's uncovered pin" \
  "$([ "$(printf '%s\n' "$dist_out" | grep -c 'SEVERITY=ERROR' || true)" -eq "$before_errors_h" ] && echo true || echo false)"
assert "no issue references a dist/ path" \
  "$([ "$(contains "$dist_out" 'dist/')" = "false" ] && echo true || echo false)"

# Guard integrity: without this half the three assertions above would ALSO pass
# with the whole check disabled. Plant one distinct defective pin at BOTH a real
# path and a dist/ path — the real one must still be flagged, exactly once.
mkdir -p "$fixture/real-plugin/skills/real"
cat > "$fixture/real-plugin/skills/real/SKILL.md" <<'EOF'
# Real source skill

```yaml
- uses: guard/integrity@7
```
EOF
mkdir -p "$fixture/dist/opencode/skills/real"
cp "$fixture/real-plugin/skills/real/SKILL.md" \
   "$fixture/dist/opencode/skills/real/SKILL.md"
guard_out="$(bash "$checker" --project-dir "$fixture")"
assert "the same defective pin at a REAL path is still flagged" \
  "$(contains "$guard_out" 'real-plugin/skills/real/SKILL.md')"
assert "the defective pin is reported exactly once (dist/ twin not counted)" \
  "$([ "$(printf '%s\n' "$guard_out" | grep -c 'guard/integrity' || true)" -eq 1 ] && echo true || echo false)"
assert "FILES_SCANNED grew by exactly 1 (only the real source file)" \
  "$([ "$(field "$guard_out" FILES_SCANNED)" -eq "$((before_scanned_h + 1))" ] && echo true || echo false)"
assert "still no issue references a dist/ path" \
  "$([ "$(contains "$guard_out" 'dist/')" = "false" ] && echo true || echo false)"

echo ""
echo "=== SUMMARY ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then echo "STATUS=FAIL"; exit 1; fi
echo "STATUS=OK"
