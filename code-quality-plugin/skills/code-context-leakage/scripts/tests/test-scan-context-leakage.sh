#!/usr/bin/env bash
# shellcheck disable=SC2016
# SC2016: fixture lines hold literal `$HOME/...` text the scanner must match.
# Regression test for code-context-leakage/scripts/scan-context-leakage.py
# (#3306).
#
# The scanner finds names and defaults that only make sense in one person's
# setup: home-directory paths, a personal checkout layout, personal
# notification channels, dated run tags used as defaults, time-of-day recipe
# names, OS-specific commands, and self-references that name an old repository.
# Each hit is a candidate for the skill's classification step, so the test
# pins both sides: every category fires on its fixture, and a neutral control
# tree stays clean.
#
# Guards:
#   A. every built-in category fires on its fixture line
#   B. a neutral control tree reports STATUS=OK with zero hits
#   C. changelogs and ADRs are excluded by default (historical records)
#   D. [identifiers] from a config are hits; [allow] passes them with a reason;
#      an allow entry that matches nothing is ERROR (stale_allowlist)
#   E. --name is the rename gate: hits before the rename, none after, and
#      --strict turns a remaining hit into exit 1
#   F. untracked and binary files are not scanned
#   G. an empty scope is ERROR (nothing_scanned); a non-repo is a usage error
#   H. --only limits the categories; an unknown category is a usage error
#   I. the self-reference check reads the repository name from the git remote
#   J. parity: on the marketplace tree, the scanner with the marketplace's own
#      identifier config finds the same hits as check-skill-portability.sh
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scanner="$script_dir/../scan-context-leakage.py"

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

tmp_root="$(mktemp -d)" || { echo "mktemp failed" >&2; exit 1; }
if [ -z "$tmp_root" ] || [ ! -d "$tmp_root" ]; then
  echo "mktemp failed" >&2
  exit 1
fi
trap 'rm -rf "$tmp_root"' EXIT

# new_tree <name> [remote-url] -- a git fixture with one neutral tracked file.
new_tree() {
  local root="$tmp_root/$1"
  mkdir -p "$root"
  printf '# Demo\n\nBuilds the report.\n' >"$root/README.md"
  git -C "$root" init -q
  if [ -n "${2:-}" ]; then
    git -C "$root" remote add origin "$2"
  fi
  git -C "$root" add -- README.md
  echo "$root"
}

# track <root> <relative path> <content> -- write a file and stage it.
track() {
  mkdir -p "$(dirname "$1/$2")"
  printf '%s\n' "$3" >"$1/$2"
  git -C "$1" add -- "$2"
}

run() {
  OUT="$(python3 "$scanner" --project-dir "$@" 2>&1)"
  RC=$?
}

tab=$'\t'

echo "=== TEST A: every built-in category fires ==="
t="$(new_tree a https://github.com/acme/shore-scan.git)"
track "$t" scripts/fetch.sh 'cp out.csv /Users/alice/Desktop/'
track "$t" scripts/sync.sh 'cd ~/src/shore-scan && make'
track "$t" justfile "$(printf '%s\n' 'telegram-send msg:' '    curl -s https://api.telegram.org/bot/send' \
  'overnight:' '    ./run.sh --tag manual-2026-10-23' 'mtime:' "    stat -f %m data.csv" \
  'fix:' "    sed -i '' s/a/b/ notes.txt")"
track "$t" Dockerfile 'LABEL org.opencontainers.image.source=https://github.com/acme/data-processing'
run "$t"
assert "A: exits 0 (hits are a report)" "$(rc_is 0)"
assert "A: STATUS=WARN" "$(contains "$OUT" '^STATUS=WARN$')"
assert "A: home-path hit" "$(contains "$OUT" '^HIT=home-path|scripts/fetch.sh:1|/Users/alice|')"
assert "A: checkout-layout hit" "$(contains "$OUT" '^HIT=checkout-layout|scripts/sync.sh:1|~/src/|')"
assert "A: personal-channel hit" "$(contains "$OUT" '^HIT=personal-channel|justfile:1|telegram|')"
assert "A: time-of-day hit on the recipe name" "$(contains "$OUT" '^HIT=time-of-day|justfile:3|overnight|')"
assert "A: dated-tag hit" "$(contains "$OUT" '^HIT=dated-tag|justfile:4|manual-2026-10-23|')"
assert "A: os-specific hit for BSD stat" "$(contains "$OUT" '^HIT=os-specific|justfile:6|stat -f|')"
assert "A: os-specific hit for BSD sed -i" "$(contains "$OUT" "^HIT=os-specific|justfile:8|sed -i ''|")"
assert "A: stale-repo-name hit" "$(contains "$OUT" '^HIT=stale-repo-name|Dockerfile:1|acme/data-processing|')"
assert "A: per-category count line" "$(contains "$OUT" '^CATEGORY_OS_SPECIFIC=2$')"
assert "A: REPO_NAME read from the remote" "$(contains "$OUT" '^REPO_NAME=acme/shore-scan$')"
assert "A: REASON names the first hit" "$(contains "$OUT" '^REASON=')"

echo "=== TEST B: a neutral control tree is clean ==="
t="$(new_tree b https://github.com/acme/shore-scan.git)"
track "$t" justfile "$(printf '%s\n' 'build:' '    cargo build --release' 'mtime:' '    stat -c %Y data.csv')"
track "$t" Dockerfile 'LABEL org.opencontainers.image.source=https://github.com/acme/shore-scan'
track "$t" docs/usage.md 'Set NOTIFY_URL to your own webhook; outputs go to $XDG_DATA_HOME/shore-scan.'
# Generic placeholders a document uses on purpose are not one person's setup.
track "$t" docs/install.md "$(printf '%s\n' 'Clone into /home/user/project or /Users/USER/project.' \
  '"repository": "https://github.com/owner/repo"')"
run "$t"
assert "B: exits 0" "$(rc_is 0)"
assert "B: STATUS=OK" "$(contains "$OUT" '^STATUS=OK$')"
assert "B: HITS_TOTAL=0" "$(contains "$OUT" '^HITS_TOTAL=0$')"
assert "B: no REASON on OK" "$(lacks "$OUT" '^REASON=')"
assert "B: files were scanned" "$(lacks "$OUT" '^FILES_SCANNED=0$')"

echo "=== TEST C: changelogs and ADRs are excluded by default ==="
t="$(new_tree c)"
track "$t" CHANGELOG.md '- moved results off /Users/alice/Desktop'
track "$t" docs/adr/0001-telegram.md 'We send alerts to telegram.'
run "$t"
assert "C: STATUS=OK" "$(contains "$OUT" '^STATUS=OK$')"
assert "C: excluded files counted" "$(contains "$OUT" '^FILES_EXCLUDED=2$')"
run "$t" --no-default-excludes
assert "C: --no-default-excludes scans them" "$(contains "$OUT" '^HITS_TOTAL=2$')"

echo "=== TEST D: config identifiers and the allowlist ==="
t="$(new_tree d)"
track "$t" config/sites.toml 'default_sites = ["harbour-west"]'
track "$t" docs/history.md 'First run at harbour-west (provenance).'
printf '%s\n' '[identifiers]' 'harbour-west' '' '[allow]' >"$tmp_root/d.conf"
run "$t" --config "$tmp_root/d.conf"
assert "D: identifier hit in config" "$(contains "$OUT" '^HIT=identifier|config/sites.toml:1|harbour-west|')"
assert "D: identifier hit in docs" "$(contains "$OUT" '^HIT=identifier|docs/history.md:1|harbour-west|')"
printf 'docs/history.md%sharbour-west%sprovenance, not a default\n' "$tab" "$tab" >>"$tmp_root/d.conf"
run "$t" --config "$tmp_root/d.conf"
assert "D: allowlisted line passes" "$(lacks "$OUT" '^HIT=identifier|docs/history.md')"
assert "D: ALLOWED_HITS=1" "$(contains "$OUT" '^ALLOWED_HITS=1$')"
assert "D: the other hit still reported" "$(contains "$OUT" '^HIT=identifier|config/sites.toml:1|')"
printf 'docs/gone.md%sharbour-west%sstale\n' "$tab" "$tab" >>"$tmp_root/d.conf"
run "$t" --config "$tmp_root/d.conf"
assert "D: stale allow entry exits 1" "$(rc_is 1)"
assert "D: TYPE=stale_allowlist" "$(contains "$OUT" 'TYPE=stale_allowlist')"

echo "=== TEST E: --name is the rename gate ==="
t="$(new_tree e)"
track "$t" bundle/README.md 'The data-processing bundle.'
run "$t" --name data-processing --only old-name
assert "E: old name found before the rename" "$(contains "$OUT" '^HIT=old-name|bundle/README.md:1|data-processing|')"
run "$t" --name data-processing --only old-name --strict
assert "E: --strict exits 1 on a remaining hit" "$(rc_is 1)"
assert "E: --strict STATUS=ERROR" "$(contains "$OUT" '^STATUS=ERROR$')"
track "$t" bundle/README.md 'The shore-scan bundle.'
run "$t" --name data-processing --only old-name --strict
assert "E: clean after the rename" "$(rc_is 0)"
assert "E: CATEGORY_OLD_NAME=0" "$(contains "$OUT" '^CATEGORY_OLD_NAME=0$')"
track "$t" scripts/data-processing-cleanup.sh 'echo cleanup'
run "$t" --name data-processing --only old-name --strict
assert "E: a file left under its old name exits 1" "$(rc_is 1)"
assert "E: old name in the file path is a hit" "$(contains "$OUT" '^HIT=old-name|scripts/data-processing-cleanup.sh:0|data-processing|')"
git -C "$t" mv scripts/data-processing-cleanup.sh scripts/shore-scan-cleanup.sh
run "$t" --name data-processing --only old-name --strict
assert "E: clean after git mv" "$(rc_is 0)"

echo "=== TEST F: untracked and binary files are not scanned ==="
t="$(new_tree f)"
printf 'cp x /Users/alice/\n' >"$t/untracked.sh"
printf 'a\0/Users/alice/\n' >"$t/blob.bin"
git -C "$t" add -- blob.bin
run "$t"
assert "F: STATUS=OK" "$(contains "$OUT" '^STATUS=OK$')"
assert "F: binary skipped" "$(contains "$OUT" '^FILES_SKIPPED_BINARY=1$')"

echo "=== TEST G: empty scope and non-repo ==="
t="$(new_tree g)"
run "$t" --include 'nothing/**'
assert "G: empty scope exits 1" "$(rc_is 1)"
assert "G: TYPE=nothing_scanned" "$(contains "$OUT" 'TYPE=nothing_scanned')"
mkdir -p "$tmp_root/plain"
run "$tmp_root/plain"
assert "G: non-repo exits 2" "$(rc_is 2)"

echo "=== TEST H: --only ==="
t="$(new_tree h)"
track "$t" run.sh "$(printf '%s\n' 'cp x /Users/alice/' 'pbcopy < out.txt')"
run "$t" --only os-specific
assert "H: os-specific kept" "$(contains "$OUT" '^HIT=os-specific|run.sh:2|pbcopy|')"
assert "H: home-path dropped" "$(lacks "$OUT" '^HIT=home-path')"
run "$t" --only no-such-category
assert "H: unknown category exits 2" "$(rc_is 2)"

echo "=== TEST I: no remote means no self-reference check ==="
t="$(new_tree i)"
track "$t" Dockerfile 'LABEL org.opencontainers.image.source=https://github.com/acme/data-processing'
run "$t"
assert "I: REPO_NAME empty" "$(contains "$OUT" '^REPO_NAME=$')"
assert "I: no stale-repo-name hit" "$(lacks "$OUT" '^HIT=stale-repo-name')"

echo "=== TEST J: parity with the marketplace check ==="
repo_root="$(cd "$script_dir/../../../../.." && pwd)"
checker="$repo_root/scripts/check-skill-portability.sh"
conf="$repo_root/scripts/skill-portability.conf"
if [ -f "$checker" ] && [ -f "$conf" ]; then
  OUT="$(bash "$checker" 2>&1)"
  want="$(sed -n 's/^HITS_TOTAL=//p' <<<"$OUT")"
  run "$repo_root" --config "$conf" --only identifier --no-default-excludes \
    --include '*-plugin/skills/**' --include '*-plugin/agents/**' --include '*-plugin/hooks/**'
  got="$(sed -n 's/^CATEGORY_IDENTIFIER=//p' <<<"$OUT")"
  assert "J: marketplace check reported a total" "$([ -n "$want" ] && echo true || echo false)"
  assert "J: scanner finds the same hits ($got vs $want)" "$([ "$got" = "$want" ] && echo true || echo false)"
else
  echo "SKIP J: not inside the marketplace checkout"
fi

echo
if [ "$fail_count" -gt 0 ]; then
  echo "FAIL: test-scan-context-leakage ($fail_count failed, $pass_count passed)"
  exit 1
fi
echo "PASS: test-scan-context-leakage ($pass_count assertions)"
