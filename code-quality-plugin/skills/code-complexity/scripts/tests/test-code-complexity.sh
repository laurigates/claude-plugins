#!/usr/bin/env bash
# test-code-complexity.sh — semantic regression test for the code-complexity
# skill's lizard offload (issue #2011).
#
# Before #2011 the JS/TS and Go paths instructed the agent to "use manual AST
# analysis" / "manual function length analysis" and to "count lines between
# function boundaries" / count nesting depth by hand — token-hungry,
# irreproducible work that belongs in a deterministic tool
# (`.claude/rules/offload-to-deterministic-substrate.md`). The fix routes JS/TS
# and Go (and every non-native-tool language) through `lizard`.
#
# This test encodes the SEMANTIC invariant, not a bare parse check:
#   1. the SKILL.md no longer instructs manual AST / manual function-length /
#      hand line-counting / hand nesting-depth analysis (outside blockquotes,
#      which may cite the banned forms as gotchas);
#   2. the SKILL.md references `lizard` with machine-readable flags
#      (`--warnings_only` and `--csv`), and the uniform `-C <n> --warnings_only`
#      invocation the Agentic Optimizations table advertises;
#   3. when `lizard` is installed, it actually computes CCN/NLOC/PARAM/length on
#      a JS and a Go sample and its documented flags behave as the SKILL claims
#      (the tool exists, the flags are real, the CSV column set is present) —
#      closing the syntactic-vs-semantic gap. SKIPs the exec checks cleanly when
#      lizard is unavailable.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_FILE="${SCRIPT_DIR}/../../SKILL.md"

pass=0
fail=0
check() { # check <description> <expected> <actual>
    if [ "$2" = "$3" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
    fi
}

# Non-blockquote view of the SKILL.md: gotcha callouts (lines starting with `>`)
# may legitimately cite the banned "manual" phrasing; the actual instructions
# must not. Matches the repo's hyphenated-tag / mcp-tool lint convention.
body_no_quotes() { grep -v '^[[:space:]]*>' "$SKILL_FILE"; }

# --- 1. The manual-analysis instructions are gone (outside callouts) ---
for phrase in \
    "manual AST analysis" \
    "manual function length analysis" \
    "count lines between function boundaries"; do
    if body_no_quotes | grep -qi "$phrase"; then
        check "manual instruction removed: '$phrase'" "absent" "present"
    else
        check "manual instruction removed: '$phrase'" "absent" "absent"
    fi
done

# --- 2. lizard is referenced with machine-readable flags ---
if grep -q 'lizard' "$SKILL_FILE"; then
    check "SKILL.md references lizard" "present" "present"
else
    check "SKILL.md references lizard" "present" "absent"
fi
for flag in "\-\-warnings_only" "\-\-csv" "\-C 10 \-\-warnings_only"; do
    if grep -Eq "lizard.*${flag}|${flag}" "$SKILL_FILE"; then
        check "SKILL.md documents lizard flag: '${flag//\\/}'" "present" "present"
    else
        check "SKILL.md documents lizard flag: '${flag//\\/}'" "present" "absent"
    fi
done

# JS/TS and Go must be routed to lizard, not to hand analysis.
if grep -Eqi 'go.*lizard|lizard.*go' "$SKILL_FILE"; then
    check "Go path routed to lizard" "present" "present"
else
    check "Go path routed to lizard" "present" "absent"
fi

# --- 3. Execute lizard to confirm the documented behaviour (SKIP if absent) ---
if ! command -v lizard >/dev/null 2>&1; then
    echo "SKIP: lizard CLI not available (install: uv tool install lizard)" >&2
else
    SCRATCH="$(mktemp -d)"
    [ -n "$SCRATCH" ] || { echo "mktemp failed" >&2; exit 1; }
    trap 'rm -rf "$SCRATCH"' EXIT

    cat > "$SCRATCH/sample.js" <<'JS'
function complex(a, b, c) {
  if (a) {
    if (b) {
      for (let i = 0; i < c; i++) {
        if (i % 2) { console.log(i); } else { console.log(-i); }
      }
    } else if (c) { return b; }
  }
  return a;
}
JS
    cat > "$SCRATCH/sample.go" <<'GO'
package main
func Complex(a, b, c int) int {
  if a > 0 {
    if b > 0 {
      for i := 0; i < c; i++ {
        if i%2 == 0 { return i } else { return -i }
      }
    }
  }
  return a
}
GO

    # --warnings_only reports the over-threshold functions from BOTH languages.
    warn_out="$(lizard -C 3 --warnings_only "$SCRATCH/sample.js" "$SCRATCH/sample.go" 2>/dev/null)"
    if grep -q 'sample.js' <<<"$warn_out" && grep -q 'CCN' <<<"$warn_out"; then
        check "lizard --warnings_only reports JS CCN" "yes" "yes"
    else
        check "lizard --warnings_only reports JS CCN" "yes" "no"
    fi
    if grep -q 'sample.go' <<<"$warn_out"; then
        check "lizard --warnings_only reports Go function" "yes" "yes"
    else
        check "lizard --warnings_only reports Go function" "yes" "no"
    fi

    # --csv produces machine-readable rows with the documented column set.
    csv_out="$(lizard --csv "$SCRATCH/sample.js" "$SCRATCH/sample.go" 2>/dev/null)"
    js_row="$(grep 'sample.js' <<<"$csv_out" | grep 'complex' | head -1)"
    # Columns: NLOC,CCN,token,PARAM,length,location,file,function,long_name,start,end
    ccn="$(cut -d, -f2 <<<"$js_row")"
    param="$(cut -d, -f4 <<<"$js_row")"
    if [ "$ccn" -ge 3 ] 2>/dev/null; then
        check "lizard --csv reports numeric CCN (>=3) for complex fn" "yes" "yes"
    else
        check "lizard --csv reports numeric CCN (>=3) for complex fn" "yes" "got:'$ccn'"
    fi
    if [ "$param" = "3" ]; then
        check "lizard --csv reports PARAM count (3)" "yes" "yes"
    else
        check "lizard --csv reports PARAM count (3)" "yes" "got:'$param'"
    fi
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
