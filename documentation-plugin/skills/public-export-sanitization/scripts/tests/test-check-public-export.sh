#!/usr/bin/env bash
# Regression test for check-public-export.sh.
# Auto-discovered by scripts/run-skill-script-tests.sh via
# */skills/*/scripts/tests/test-*.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/../check-public-export.sh"

pass=0
fail=0
ok()  { printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL - %s\n' "$1"; fail=$((fail + 1)); }

SANDBOX="$(mktemp -d)"
[ -n "$SANDBOX" ] || { echo "mktemp failed"; exit 1; }
trap 'rm -rf "$SANDBOX"' EXIT

# expect NAME WANT_EXIT WANT_REGEX(optional) -- args...
expect() {
  local test_name="$1" want_exit="$2" want_re="$3"; shift 4
  local out rc
  out="$(bash "$CHECK" "$@" 2>&1)"; rc=$?
  if [[ "$rc" -ne "$want_exit" ]]; then
    bad "$test_name (exit $rc, want $want_exit)"; printf '%s\n' "$out" | sed 's/^/    /'; return
  fi
  if [[ -n "$want_re" ]] && ! grep -Eq -- "$want_re" <<<"$out"; then
    bad "$test_name (output lacks /$want_re/)"; printf '%s\n' "$out" | sed 's/^/    /'; return
  fi
  ok "$test_name"
}

# --- A: genericized tree with placeholders is clean ---------------------------
mkdir -p "$SANDBOX/clean"
cat > "$SANDBOX/clean/doc.md" <<'MD'
# Setup
The service account `<sa-name>@<gcp-project-id>.iam.gserviceaccount.com` runs in
project `<project-number>`. See [the other doc](other.md).
MD
printf '# Other\n' > "$SANDBOX/clean/other.md"
expect "A: placeholders are not flagged" 0 'clean' -- "$SANDBOX/clean"

# --- B: built-in leak classes fire --------------------------------------------
mkdir -p "$SANDBOX/leaky"
cat > "$SANDBOX/leaky/doc.md" <<'MD'
Runs as deployer@acme-prod.iam.gserviceaccount.com in project 123456789012.
Config lives at /Users/alice/work/config.yaml.
MD
expect "B1: SA email flagged" 1 'GCP service-account email' -- "$SANDBOX/leaky"
expect "B2: project number flagged" 1 'GCP project number' -- "$SANDBOX/leaky"
expect "B3: home path flagged" 1 'Absolute home path' -- "$SANDBOX/leaky"

# --- C: org shapes come from --patterns, not the script -----------------------
mkdir -p "$SANDBOX/org"
printf 'Dashboard at grafana.corp.example for the team.\n' > "$SANDBOX/org/doc.md"
cat > "$SANDBOX/org.patterns" <<'PAT'
# org-specific leak classes
Internal hostname (corp.example)::\b[a-z0-9-]+\.corp\.example\b

PAT
expect "C1: org hostname not flagged without --patterns" 0 'clean' -- "$SANDBOX/org"
expect "C2: org hostname flagged with --patterns" 1 'Internal hostname \(corp\.example\)' -- --patterns "$SANDBOX/org.patterns" "$SANDBOX/org"
expect "C3: --allow dismisses a known-benign hit" 0 'clean' -- --patterns "$SANDBOX/org.patterns" --allow 'grafana\.corp' "$SANDBOX/org"

printf 'no separator here\n' > "$SANDBOX/broken.patterns"
expect "C4: malformed pattern line is a usage error" 2 "lacks 'label::regex'" -- --patterns "$SANDBOX/broken.patterns" "$SANDBOX/org"
expect "C5: missing patterns file is a usage error" 2 'not found' -- --patterns "$SANDBOX/nope.patterns" "$SANDBOX/org"

# --- D: link boundary ---------------------------------------------------------
mkdir -p "$SANDBOX/repo/export"
printf 'License\n' > "$SANDBOX/repo/LICENSE"
printf 'See [license](../LICENSE) and [missing](gone.md).\n' > "$SANDBOX/repo/export/doc.md"
expect "D1: link escaping the export is flagged" 1 'link escapes boundary' -- "$SANDBOX/repo/export"
expect "D2: broken link flagged under --repo-root" 1 'broken link -> gone.md' -- --repo-root "$SANDBOX/repo" "$SANDBOX/repo/export"
out="$(bash "$CHECK" --repo-root "$SANDBOX/repo" "$SANDBOX/repo/export" 2>&1)"
if grep -q 'escapes boundary' <<<"$out"; then bad "D3: sibling link allowed under --repo-root"; else ok "D3: sibling link allowed under --repo-root"; fi

# --- E: dot-directories are scanned; .git/ is not (#2820) ---------------------
# rg skips hidden paths unless --hidden, so a hit that lives only under
# .claude/ or .github/ used to come back "clean".
mkdir -p "$SANDBOX/dotdir/.claude/rules" "$SANDBOX/dotdir/.github/workflows"
printf 'Runs as deployer@acme-prod.iam.gserviceaccount.com.\n' > "$SANDBOX/dotdir/.claude/rules/infra.md"
expect "E1: hit under .claude/rules/ is flagged" 1 'GCP service-account email' -- --no-links "$SANDBOX/dotdir"
printf 'path: /home/alice/ci\n' > "$SANDBOX/dotdir/.github/workflows/ci.yml"
expect "E2: hit under .github/ is flagged" 1 '\.github/workflows/ci\.yml' -- --no-links "$SANDBOX/dotdir"
mkdir -p "$SANDBOX/gitdir/.git"
printf 'project 123456789012\n' > "$SANDBOX/gitdir/.git/config"
printf '# Clean\n' > "$SANDBOX/gitdir/doc.md"
expect "E3: .git/ internals are not scanned" 0 'clean' -- --no-links "$SANDBOX/gitdir"
# The link scan honours the same .git/ skip as the rg scans.
printf 'See [x](../../outside.md).\n' > "$SANDBOX/gitdir/.git/x.md"
expect "E4: .git/ is skipped by the link scan too" 0 'clean' -- "$SANDBOX/gitdir"

# --- F: --names comment syntax (#2820) -----------------------------------------
# Only a bare '#' or '#'+whitespace starts a comment; '#13280' is a literal entry.
mkdir -p "$SANDBOX/names"
printf 'Fixed in PR #13280 by the platform team.\n' > "$SANDBOX/names/doc.md"
printf '#13280\n' > "$SANDBOX/hash.names"
expect "F1: '#'-prefixed names entry is matched" 1 'Personal name: #13280' -- --no-links --names "$SANDBOX/hash.names" "$SANDBOX/names"
printf '# platform\n  #\n\n' > "$SANDBOX/comment.names"
expect "F2: '# comment' and bare '#' lines are ignored" 0 'clean' -- --no-links --names "$SANDBOX/comment.names" "$SANDBOX/names"
printf '# authors\nplatform team\n' > "$SANDBOX/mixed.names"
expect "F3: entry after a comment line still matches" 1 'Personal name: platform team' -- --no-links --names "$SANDBOX/mixed.names" "$SANDBOX/names"
# A trailing '<ws># ...' is stripped, so an inline-commented entry still matches.
printf 'platform team  # owners\n' > "$SANDBOX/inline.names"
expect "F4: inline '# comment' tail is stripped" 1 'Personal name: platform team  \(' -- --no-links --names "$SANDBOX/inline.names" "$SANDBOX/names"
# Names scan reaches dot-directories, and an unterminated final line is read.
mkdir -p "$SANDBOX/names/.claude"
printf 'Reviewed by Bob Jones.\n' > "$SANDBOX/names/.claude/r.md"
printf 'Bob Jones' > "$SANDBOX/nonl.names"
expect "F5: no-newline names entry matches under .claude/" 1 'Personal name: Bob Jones' -- --no-links --names "$SANDBOX/nonl.names" "$SANDBOX/names"

# --- G: 12-digit project number vs decimal fractions (#3272) -------------------
# '\b[0-9]{12}\b' matched the 12 fractional digits of a float ('.' is a word
# boundary), flagging every 12-decimal measurement in a CSV fixture.
gcp_case() { # NAME WANT(flag|clean) LINE
  local test_name="$1" want="$2" line="$3" dir out
  dir="$(mktemp -d "$SANDBOX/gcp.XXXXXX")"
  printf '%s\n' "$line" > "$dir/data.txt"
  out="$(bash "$CHECK" --no-links "$dir" 2>&1)"
  if grep -q 'GCP project number' <<<"$out"; then
    [[ "$want" == flag ]] && ok "$test_name" || { bad "$test_name (flagged, want clean)"; printf '%s\n' "$out" | sed 's/^/    /'; }
  else
    [[ "$want" == clean ]] && ok "$test_name" || { bad "$test_name (not flagged, want flag)"; printf '%s\n' "$out" | sed 's/^/    /'; }
  fi
}
gcp_case "G1: 12 fractional digits are not a project number" clean 'sharp.jpg,12800.711543199157'
gcp_case "G2: second decimal fixture row is clean" clean 'blurry.jpg,13433.692314702685'
gcp_case "G3: number ending a sentence is flagged" flag 'Deployed to project 123456789012.'
gcp_case "G4: bare number on its own line is flagged" flag '123456789012'
gcp_case "G5: mid-sentence number is flagged" flag 'id 123456789012 here'
gcp_case "G6: 12-digit integer part of a decimal is not flagged" clean 'value 123456789012.5'
gcp_case "G7: 13-digit run is not flagged" clean 'big 1234567890123 number'
gcp_case "G8: digits glued to letters stay unflagged (word boundary kept)" clean 'hash abc123456789012def'
gcp_case "G9: number in a comma-separated field is flagged" flag 'name,123456789012,other'
# The reported line is the whole source line, counted once per line.
mkdir -p "$SANDBOX/gcpline"
printf 'a 123456789012 b 210987654321.\n' > "$SANDBOX/gcpline/d.txt"
out="$(bash "$CHECK" --no-links "$SANDBOX/gcpline" 2>&1)"
if grep -qF 'GCP project number (12-digit)  (1)' <<<"$out" && grep -qF 'd.txt:1:a 123456789012 b 210987654321.' <<<"$out"; then
  ok "G10: report prints the full line, counted once"
else
  bad "G10: report prints the full line, counted once"; printf '%s\n' "$out" | sed 's/^/    /'
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
