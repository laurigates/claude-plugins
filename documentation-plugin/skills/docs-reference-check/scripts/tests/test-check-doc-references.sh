#!/usr/bin/env bash
# Regression test for check-doc-references.py.
# Auto-discovered by scripts/run-skill-script-tests.sh via
# */skills/*/scripts/tests/test-*.sh.
#
# Pins the precision/recall contract in throwaway git repos: dead links and
# anchored dead paths are flagged; live paths, unanchored tokens, placeholders,
# slash commands, domains, fenced examples and a nested package's own paths are
# not. chezmoi mode is pinned in both directions (auto-detected on, forced off).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/../check-doc-references.py"
CONTRACT="$SCRIPT_DIR/../../../../../scripts/check-structured-output-contract.sh"

# Keep an inherited GIT_DIR/GIT_WORK_TREE from pointing git at the real repo.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR

pass=0
fail=0
ok()  { printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL - %s\n' "$1"; fail=$((fail + 1)); }

SANDBOX="$(mktemp -d)" || { echo 'mktemp failed' >&2; exit 1; }
if [ -z "$SANDBOX" ] || [ ! -d "$SANDBOX" ]; then echo 'bad sandbox dir' >&2; exit 1; fi
trap 'rm -rf "$SANDBOX"' EXIT

# run REPO ARGS... -> sets OUT and RC
run() {
  local repo="$1"; shift
  OUT="$(cd "$repo" && python3 "$CHECK" "$@" 2>&1)"; RC=$?
}
dump() { printf '%s\n' "$OUT" | sed 's/^/    /'; }
has() {
  if grep -qE -- "$2" <<<"$OUT"; then ok "$1"; else bad "$1 (no /$2/)"; dump; fi
}
hasnt() {
  if grep -qE -- "$2" <<<"$OUT"; then bad "$1 (found /$2/)"; dump; else ok "$1"; fi
}
exit_is() {
  if [ "$RC" -eq "$2" ]; then ok "$1"; else bad "$1 (exit $RC, want $2)"; fi
}
validate() {
  if [ ! -f "$CONTRACT" ]; then ok "$1 (contract validator absent, skipped)"; return; fi
  if bash "$CONTRACT" --validate - <<<"$OUT" >/dev/null 2>&1; then ok "$1"; else bad "$1 (contract --validate failed)"; fi
}
flagged() { has "$1" "MSG=$2\$"; }
clean()   { hasnt "$1" "MSG=$2\$"; }

# --- plain repo ------------------------------------------------------------------
PLAIN="$SANDBOX/plain"
mkdir -p "$PLAIN/scripts" "$PLAIN/docs" "$PLAIN/pkg/scripts"
git -C "$PLAIN" init -q
printf '#!/bin/sh\n' > "$PLAIN/scripts/live.sh"
printf '#!/bin/sh\n' > "$PLAIN/pkg/scripts/own.sh"
printf '#!/bin/sh\n' > "$PLAIN/run.sh"
printf '# Other\n' > "$PLAIN/docs/other.md"
cat > "$PLAIN/docs/guide.md" <<'MD'
# Guide

Dead ref: `scripts/gone.sh`
Dead root script: `./missing.sh`
Dead link: [gone](../nowhere/gone.md)

Live ref: `scripts/live.sh`
Live root script: `./run.sh`
Live link: [other](other.md)
Root-anchored link: [live](/scripts/live.sh)
Unanchored token: `consumer/scripts/thing.sh`
Placeholder: `docs/adrs/NNNN-title.md`
Slash command: `/configure:mcp`
Domain: `github.com/acme/repo`
Home path: `~/.config/app/config.toml`
Anchor only: [section](#guide)

```bash
bash scripts/fenced-example.sh
```
MD
cat > "$PLAIN/pkg/README.md" <<'MD'
# pkg
Own script: `scripts/own.sh`
MD
git -C "$PLAIN" add -A

run "$PLAIN"
exit_is "A0: advisory run exits 0 with findings" 0
has     "A1: advisory findings report STATUS=WARN" '^STATUS=WARN$'
has     "A2: ISSUE_COUNT matches the 3 dead references" '^ISSUE_COUNT=3$'
has     "A3: CHEZMOI_MODE off without a marker" '^CHEZMOI_MODE=off$'
flagged "A4: dead anchored path flagged" 'scripts/gone\.sh'
flagged "A5: dead ./name flagged" '\./missing\.sh'
flagged "A6: dead relative link flagged" '\.\./nowhere/gone\.md'
has     "A7: link finding typed dangling_link" 'TYPE=dangling_link FILE=docs/guide\.md:5 '
clean   "A8: live path clean" 'scripts/live\.sh'
clean   "A9: unanchored token clean" 'consumer/scripts/thing\.sh'
clean   "A10: placeholder clean" 'docs/adrs/NNNN-title\.md'
clean   "A11: slash command clean" '/configure:mcp'
clean   "A12: domain clean" 'github\.com/acme/repo'
hasnt   "A13: fenced example skipped" 'fenced-example'
clean   "A14: nested package's own path resolves from the doc dir" 'scripts/own\.sh'
has     "A15: REASON names the first finding's TYPE" '^REASON=dangling_[a-z]+: '
validate "A16: advisory output passes the structured-output contract"

run "$PLAIN" --strict
exit_is "B0: --strict exits 1 on findings" 1
has     "B1: --strict reports STATUS=ERROR" '^STATUS=ERROR$'
validate "B2: strict output passes the structured-output contract"

run "$PLAIN" docs/other.md
exit_is "B3: file argument limits the scan; clean file exits 0" 0
has     "B4: clean scan reports STATUS=OK" '^STATUS=OK$'
hasnt   "B5: no REASON on OK" '^REASON='
validate "B6: OK output passes the structured-output contract"

# --- allowlist -------------------------------------------------------------------
printf '# immutable records\ndocs/guide.md\n' > "$PLAIN/.doc-reference-allow"
run "$PLAIN" --strict
exit_is "C0: default allowlist skips the matching doc" 0
has     "C1: allowlist pattern counted" '^ALLOWLISTED_PATTERNS=1$'
rm "$PLAIN/.doc-reference-allow"
run "$PLAIN" --allow-file "$SANDBOX/no-such.allow"
exit_is "C2: missing --allow-file is a usage error" 2

# --- chezmoi repo ----------------------------------------------------------------
CZ="$SANDBOX/chezmoi"
mkdir -p "$CZ/exact_dot_claude/hooks"
git -C "$CZ" init -q
printf '' > "$CZ/.chezmoiignore"
printf '#!/bin/sh\n' > "$CZ/exact_dot_claude/hooks/executable_nudge.sh.tmpl"
printf '#!/bin/sh\n' > "$CZ/executable_cleanup.sh"
cat > "$CZ/README.md" <<'MD'
# dotfiles
Hook by rendered name: `exact_dot_claude/hooks/nudge.sh`
Root script by rendered name: `./cleanup.sh`
Dead hook: `exact_dot_claude/hooks/gone.sh`
MD
git -C "$CZ" add -A

run "$CZ"
has     "D0: chezmoi marker turns the mode on" '^CHEZMOI_MODE=on$'
clean   "D1: rendered hook name resolves to its source" 'exact_dot_claude/hooks/nudge\.sh'
clean   "D2: rendered ./name resolves to its source" '\./cleanup\.sh'
flagged "D3: dead managed path still flagged" 'exact_dot_claude/hooks/gone\.sh'
run "$CZ" --chezmoi off
flagged "D4: --chezmoi off flags the rendered name (mode has teeth)" 'exact_dot_claude/hooks/nudge\.sh'
run "$PLAIN" --chezmoi on
has     "D5: --chezmoi on forces the mode" '^CHEZMOI_MODE=on$'

# --- edges -----------------------------------------------------------------------
mkdir -p "$SANDBOX/nogit"
run "$SANDBOX/nogit"
exit_is "E0: outside a git repo is a usage error" 2
EMPTY="$SANDBOX/empty"
mkdir -p "$EMPTY"
git -C "$EMPTY" init -q
run "$EMPTY"
has     "E1: zero docs is marked SCANNED_EMPTY" '^SCANNED_EMPTY=true$'

printf '\nPASSED=%d FAILED=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
