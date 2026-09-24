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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
