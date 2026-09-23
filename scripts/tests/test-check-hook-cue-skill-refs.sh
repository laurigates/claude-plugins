#!/usr/bin/env bash
# Regression test for scripts/check-hook-cue-skill-refs.sh (issue #2682).
#
# SEMANTIC, not syntactic: every assertion EXECUTES the guard against a planted
# fixture tree and reads its verdict. A grep for the fixed literal would have
# passed against the broken `_get uuid` fix in #1417 too — the lesson recorded
# in docs/regression-ledger.md.
#
# The guard derives its scan root from its own location, so each fixture tree
# gets its own `scripts/` copy of the guard. That doubles as the scan-root
# robustness case: the tree lives under a temp dir, not the repo.
#
# Run: bash scripts/tests/test-check-hook-cue-skill-refs.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GUARD="$REPO_ROOT/scripts/check-hook-cue-skill-refs.sh"

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# Build a fixture tree. $1 = name, $2 = "with-skills" | "no-skills".
# Returns the tree path on stdout.
make_tree() {
  local skills="$2" tree="$TMP_ROOT/$1"
  mkdir -p "$tree/scripts" "$tree/code-quality-plugin/hooks" "$tree/other-plugin/hooks"
  cp "$GUARD" "$tree/scripts/check-hook-cue-skill-refs.sh"
  if [ "$skills" = "with-skills" ]; then
    mkdir -p "$tree/code-quality-plugin/skills/code-lint" \
             "$tree/evaluate-plugin/skills/evaluate-skill"
    echo "# code-lint" > "$tree/code-quality-plugin/skills/code-lint/SKILL.md"
    echo "# evaluate-skill" > "$tree/evaluate-plugin/skills/evaluate-skill/SKILL.md"
  fi
  printf '%s' "$tree"
}

run_guard() { bash "$1/scripts/check-hook-cue-skill-refs.sh" 2>&1; }
field() { printf '%s\n' "$1" | grep -E "^$2=" | head -1 | cut -d= -f2-; }

# --- (a) the verbatim PRE-FIX cue line is reported, with the resolvable fix ---
echo "--- Test (a): pre-fix cue line ERRORs and names the resolvable ID ---"
TREE_A="$(make_tree a with-skills)"
cat > "$TREE_A/code-quality-plugin/hooks/cue.sh" <<'EOF'
#!/usr/bin/env bash
cq_cue="[code-quality] Large/structural edit detected. Run /code-quality:code-lint as a pre-flight, and /evaluate:evaluate-skill since a skill changed, once this edit sequence is complete."
echo "$cq_cue"
EOF
OUT_A="$(run_guard "$TREE_A")"; RC_A=$?
if [ "$RC_A" -ne 0 ]; then
  pass "(a) guard exits non-zero on an unresolvable emitted ID"
else
  fail "(a) guard should exit non-zero; got rc=$RC_A: $OUT_A"
fi
if [ "$(field "$OUT_A" ISSUE_COUNT)" = "2" ] && [ "$(field "$OUT_A" STATUS)" = "ERROR" ]; then
  pass "(a) both unresolvable IDs on the line are counted (ISSUE_COUNT=2, STATUS=ERROR)"
else
  fail "(a) expected ISSUE_COUNT=2 / STATUS=ERROR; got: $OUT_A"
fi
if printf '%s' "$OUT_A" | grep -q 'ID=code-quality:code-lint FIX=code-quality-plugin:code-lint'; then
  pass "(a) names code-quality-plugin:code-lint as the copy-pasteable fix"
else
  fail "(a) expected FIX=code-quality-plugin:code-lint; got: $OUT_A"
fi
if printf '%s' "$OUT_A" | grep -q 'ID=evaluate:evaluate-skill FIX=evaluate-plugin:evaluate-skill'; then
  pass "(a) names evaluate-plugin:evaluate-skill as the copy-pasteable fix"
else
  fail "(a) expected FIX=evaluate-plugin:evaluate-skill; got: $OUT_A"
fi

# --- (b) the FIXED line is clean, and the scan demonstrably ran ---
echo "--- Test (b): plugin-qualified cue passes, with a non-vacuous scan ---"
TREE_B="$(make_tree b with-skills)"
cat > "$TREE_B/code-quality-plugin/hooks/cue.sh" <<'EOF'
#!/usr/bin/env bash
cq_cue="[code-quality] Run /code-quality-plugin:code-lint, and /evaluate-plugin:evaluate-skill since a skill changed."
echo "$cq_cue"
EOF
OUT_B="$(run_guard "$TREE_B")"; RC_B=$?
if [ "$RC_B" -eq 0 ] && [ "$(field "$OUT_B" STATUS)" = "OK" ]; then
  pass "(b) plugin-qualified IDs resolve (rc=0, STATUS=OK)"
else
  fail "(b) expected rc=0 / STATUS=OK; got rc=$RC_B: $OUT_B"
fi
# Guard integrity (#2219/#2290): a collapsed walk must not masquerade as a pass.
if [ "$(field "$OUT_B" FILES_SCANNED)" -ge 1 ] && [ "$(field "$OUT_B" REFS_CHECKED)" -ge 2 ]; then
  pass "(b) scan is non-vacuous (FILES_SCANNED>=1, REFS_CHECKED>=2)"
else
  fail "(b) scan looks collapsed; got: $OUT_B"
fi

# --- (c) comment lines are skipped and counted ---
echo "--- Test (c): a short-form ID inside a comment is skipped, not flagged ---"
TREE_C="$(make_tree c with-skills)"
cat > "$TREE_C/code-quality-plugin/hooks/cue.sh" <<'EOF'
#!/usr/bin/env bash
# The short form /code-quality:code-lint does not resolve; use the qualified ID.
   # Indented comments count too: /evaluate:evaluate-skill is the bad form.
echo "[code-quality] Run /code-quality-plugin:code-lint."
EOF
OUT_C="$(run_guard "$TREE_C")"; RC_C=$?
if [ "$RC_C" -eq 0 ] && [ "$(field "$OUT_C" ISSUE_COUNT)" = "0" ]; then
  pass "(c) comment-only short forms are not flagged"
else
  fail "(c) expected rc=0 / ISSUE_COUNT=0; got rc=$RC_C: $OUT_C"
fi
if [ "$(field "$OUT_C" COMMENTS_SKIPPED)" -ge 2 ]; then
  pass "(c) COMMENTS_SKIPPED reports the exemption it applied (>=2)"
else
  fail "(c) expected COMMENTS_SKIPPED>=2; got: $OUT_C"
fi

# --- (d) hooks/test-*.sh is out of scope ---
echo "--- Test (d): a hook TEST file carrying a bad ID is not scanned ---"
TREE_D="$(make_tree d with-skills)"
cat > "$TREE_D/code-quality-plugin/hooks/cue.sh" <<'EOF'
#!/usr/bin/env bash
echo "[code-quality] Run /code-quality-plugin:code-lint."
EOF
cat > "$TREE_D/code-quality-plugin/hooks/test-cue.sh" <<'EOF'
#!/usr/bin/env bash
expected="Run /code-quality:code-lint as a pre-flight"
echo "$expected"
EOF
OUT_D="$(run_guard "$TREE_D")"; RC_D=$?
if [ "$RC_D" -eq 0 ] && [ "$(field "$OUT_D" ISSUE_COUNT)" = "0" ]; then
  pass "(d) test-*.sh fixtures are excluded from the scan"
else
  fail "(d) expected rc=0 / ISSUE_COUNT=0; got rc=$RC_D: $OUT_D"
fi
if [ "$(field "$OUT_D" FILES_SCANNED)" = "1" ]; then
  pass "(d) exactly the one non-test hook was scanned"
else
  fail "(d) expected FILES_SCANNED=1; got: $OUT_D"
fi

# --- (e) out-of-scope hooks are ADVISORY: reported, never fatal ---
echo "--- Test (e): an unfixed hook outside the enforced scope is advisory only ---"
TREE_E="$(make_tree e with-skills)"
cat > "$TREE_E/code-quality-plugin/hooks/cue.sh" <<'EOF'
#!/usr/bin/env bash
echo "[code-quality] Run /code-quality-plugin:code-lint."
EOF
cat > "$TREE_E/other-plugin/hooks/probe.sh" <<'EOF'
#!/usr/bin/env bash
echo "Run /other:thing to reconcile."
EOF
OUT_E="$(run_guard "$TREE_E")"; RC_E=$?
if [ "$RC_E" -eq 0 ] && [ "$(field "$OUT_E" STATUS)" = "OK" ]; then
  pass "(e) an out-of-scope hook does not fail the build"
else
  fail "(e) expected rc=0 / STATUS=OK; got rc=$RC_E: $OUT_E"
fi
if [ "$(field "$OUT_E" ADVISORY_ISSUE_COUNT)" = "1" ] &&
   printf '%s' "$OUT_E" | grep -q 'FILE=other-plugin/hooks/probe.sh UNRESOLVABLE=1'; then
  pass "(e) the out-of-scope instance is reported under ADVISORY, not hidden"
else
  fail "(e) expected ADVISORY_ISSUE_COUNT=1 naming other-plugin/hooks/probe.sh; got: $OUT_E"
fi
if [ "$(field "$OUT_E" SCOPE_IS_REPO_WIDE)" = "false" ]; then
  pass "(e) the guard declares its scope honestly (SCOPE_IS_REPO_WIDE=false)"
else
  fail "(e) expected SCOPE_IS_REPO_WIDE=false; got: $OUT_E"
fi

# --- (f) an empty ground truth aborts instead of passing vacuously ---
echo "--- Test (f): zero skills on disk is a broken walk, not a clean tree ---"
TREE_F="$(make_tree f no-skills)"
cat > "$TREE_F/code-quality-plugin/hooks/cue.sh" <<'EOF'
#!/usr/bin/env bash
echo "[code-quality] Run /code-quality:code-lint."
EOF
OUT_F="$(run_guard "$TREE_F")"; RC_F=$?
if [ "$RC_F" -ne 0 ] && printf '%s' "$OUT_F" | grep -q 'TYPE=broken_walk'; then
  pass "(f) empty ground truth fails loudly (broken_walk)"
else
  fail "(f) expected non-zero exit with TYPE=broken_walk; got rc=$RC_F: $OUT_F"
fi

# --- (g) a path-like `a/b:c` is not mistaken for a slash command ---
echo "--- Test (g): git refspecs and paths are not read as skill IDs ---"
TREE_G="$(make_tree g with-skills)"
cat > "$TREE_G/code-quality-plugin/hooks/cue.sh" <<'EOF'
#!/usr/bin/env bash
echo "push origin refs/heads/feat/x:refs/heads/feat/x"
echo "[code-quality] Run /code-quality-plugin:code-lint."
EOF
OUT_G="$(run_guard "$TREE_G")"; RC_G=$?
if [ "$RC_G" -eq 0 ] && [ "$(field "$OUT_G" ISSUE_COUNT)" = "0" ]; then
  pass "(g) a refspec does not produce a phantom unresolvable ID"
else
  fail "(g) expected rc=0 / ISSUE_COUNT=0; got rc=$RC_G: $OUT_G"
fi

# --- (i) an INDENTED emitted line containing `#` is checked, not skipped ---
# The comment glob was `[[:space:]]*\#* | \#*`; the first alternative reads as
# "one whitespace char, then ANYTHING, then a `#`", so it swallowed any indented
# line carrying a `#` anywhere. Hook cues in this repo routinely cite issue
# numbers, and the real cue assignments live indented inside a `case` block, so
# the hole sat directly over the line the guard exists to protect.
echo "--- Test (i): an indented cue citing an issue number is still checked ---"
TREE_I="$(make_tree i with-skills)"
cat > "$TREE_I/code-quality-plugin/hooks/cue.sh" <<'EOF'
#!/usr/bin/env bash
case "$f" in
    *) cue="[code-quality] Run /code-quality:code-lint as a pre-flight (issue #2682)." ;;
esac
echo "$cue"
EOF
OUT_I="$(run_guard "$TREE_I")"; RC_I=$?
if [ "$RC_I" -ne 0 ] && [ "$(field "$OUT_I" ISSUE_COUNT)" = "1" ] &&
   [ "$(field "$OUT_I" STATUS)" = "ERROR" ]; then
  pass "(i) an indented emitted line carrying a '#' is still checked"
else
  fail "(i) expected rc!=0 / ISSUE_COUNT=1 / STATUS=ERROR; got rc=$RC_I: $OUT_I"
fi
# Non-vacuity: the reference must have been EXTRACTED, not merely counted. A
# guard that skipped the line reports REFS_CHECKED=0 / COMMENTS_SKIPPED=1.
if [ "$(field "$OUT_I" REFS_CHECKED)" -ge 1 ] && [ "$(field "$OUT_I" COMMENTS_SKIPPED)" = "0" ]; then
  pass "(i) the indented line was scanned, not counted as a comment"
else
  fail "(i) expected REFS_CHECKED>=1 / COMMENTS_SKIPPED=0; got: $OUT_I"
fi
if printf '%s' "$OUT_I" | grep -q 'LINE=3 ID=code-quality:code-lint FIX=code-quality-plugin:code-lint'; then
  pass "(i) reports the indented line by number with the resolvable fix"
else
  fail "(i) expected LINE=3 with FIX=code-quality-plugin:code-lint; got: $OUT_I"
fi

# Guard integrity for (i): the narrowing must not have disabled the exemption.
# A genuinely-indented COMMENT that also cites an issue number must stay exempt,
# or the fix degrades into "flag every line" and test (c) alone cannot tell the
# difference (its comments carry no issue citation).
echo "--- Test (i2): an indented comment citing an issue number is still exempt ---"
TREE_I2="$(make_tree i2 with-skills)"
cat > "$TREE_I2/code-quality-plugin/hooks/cue.sh" <<'EOF'
#!/usr/bin/env bash
case "$f" in
    # The short form /code-quality:code-lint does not resolve (issue #2682).
    *) cue="[code-quality] Run /code-quality-plugin:code-lint." ;;
esac
EOF
OUT_I2="$(run_guard "$TREE_I2")"; RC_I2=$?
if [ "$RC_I2" -eq 0 ] && [ "$(field "$OUT_I2" ISSUE_COUNT)" = "0" ] &&
   [ "$(field "$OUT_I2" COMMENTS_SKIPPED)" = "1" ]; then
  pass "(i2) an indented comment is still exempt and counted"
else
  fail "(i2) expected rc=0 / ISSUE_COUNT=0 / COMMENTS_SKIPPED=1; got rc=$RC_I2: $OUT_I2"
fi
if [ "$(field "$OUT_I2" REFS_CHECKED)" -ge 1 ]; then
  pass "(i2) the sibling emitted line was still scanned (exemption is per-line)"
else
  fail "(i2) expected REFS_CHECKED>=1; got: $OUT_I2"
fi

# --- (h) the REAL repo tree: the enforced scope is clean and non-vacuous ---
echo "--- Test (h): the live repo passes the enforced scope, non-vacuously ---"
OUT_H="$(bash "$GUARD" 2>&1)"; RC_H=$?
if [ "$RC_H" -eq 0 ] && [ "$(field "$OUT_H" STATUS)" = "OK" ]; then
  pass "(h) live repo: enforced scope is clean"
else
  fail "(h) live repo should pass; got rc=$RC_H: $OUT_H"
fi
if [ "$(field "$OUT_H" FILES_SCANNED)" -ge 1 ] && [ "$(field "$OUT_H" REFS_CHECKED)" -ge 1 ] &&
   [ "$(field "$OUT_H" TRUTH_COUNT)" -ge 1 ]; then
  pass "(h) live repo: the scan and the ground-truth walk both produced work"
else
  fail "(h) live repo scan looks collapsed; got: $OUT_H"
fi

echo ""
echo "=== RESULTS ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
if [ "$FAIL" -eq 0 ]; then
  echo "STATUS=OK"
  exit 0
else
  echo "STATUS=ERROR"
  exit 1
fi
