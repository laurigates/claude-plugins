#!/usr/bin/env bash
# test-prune-claude-config.sh — regression suite for prune-claude-config.py
#
# Semantic invariants guarded (each case EXECUTES the script on a fixture):
#   1. Legacy projects[*].history arrays are kept by default and dropped only
#      with --drop-legacy-history (prompt history moved to history.jsonl).
#   2. Dropping legacy history never touches the rest of a live project entry
#      or the top-level mcpServers block.
#   3. Orphaned project entries are still removed; --dry-run writes nothing.
#   4. ~/.claude/history.jsonl is never modified.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRUNER="${SCRIPT_DIR}/../prune-claude-config.py"

fail() { printf 'FAIL: %b\n' "$1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

if ! command -v python3 >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: python3 or jq not available"
  exit 0
fi
[ -f "$PRUNER" ] || fail "pruner not found at $PRUNER"

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT
live="${tmp_root}/live-project"
mkdir -p "$live" "${tmp_root}/.claude"

make_config() {
  jq -n --arg live "$live" '{
    mcpServers: {keep: {command: "x"}},
    projects: {
      ($live): {allowedTools: ["Read"], history: [{display: "a"}, {display: "b"}]},
      "/nonexistent/gone": {history: [{display: "c"}]}
    }
  }' > "${tmp_root}/claude.json"
}
echo '{"display":"x","project":"/p"}' > "${tmp_root}/.claude/history.jsonl"
history_sum_before="$(cksum < "${tmp_root}/.claude/history.jsonl")"

# Case 1: --dry-run changes nothing
make_config
before="$(cksum < "${tmp_root}/claude.json")"
python3 "$PRUNER" --config "${tmp_root}/claude.json" --dry-run --drop-legacy-history >/dev/null \
  || fail "dry-run exited non-zero"
[ "$(cksum < "${tmp_root}/claude.json")" = "$before" ] || fail "dry-run modified the config"
pass "--dry-run writes nothing"

# Case 2: default run removes the orphan but keeps legacy history
make_config
python3 "$PRUNER" --config "${tmp_root}/claude.json" >/dev/null || fail "default run exited non-zero"
cfg="${tmp_root}/claude.json"
[ "$(jq -r '.projects | has("/nonexistent/gone")' "$cfg")" = "false" ] || fail "orphan project not removed"
[ "$(jq -r --arg l "$live" '.projects[$l].history | length' "$cfg")" = "2" ] \
  || fail "legacy history dropped without --drop-legacy-history:\n$(cat "$cfg")"
pass "default run removes orphan, keeps legacy history"

# Case 3: --drop-legacy-history drops only the history key
make_config
out="$(python3 "$PRUNER" --config "$cfg" --drop-legacy-history)" || fail "drop run exited non-zero"
[ "$(jq -r --arg l "$live" '.projects[$l] | has("history")' "$cfg")" = "false" ] \
  || fail "legacy history not dropped:\n$(cat "$cfg")"
[ "$(jq -r --arg l "$live" '.projects[$l].allowedTools[0]' "$cfg")" = "Read" ] \
  || fail "other project fields lost:\n$(cat "$cfg")"
[ "$(jq -r '.mcpServers.keep.command' "$cfg")" = "x" ] || fail "mcpServers modified"
echo "$out" | grep -q "2 legacy prompt-history entries" || fail "summary missing legacy count:\n$out"
pass "--drop-legacy-history removes only projects[*].history"

# Case 4: history.jsonl untouched
[ "$(cksum < "${tmp_root}/.claude/history.jsonl")" = "$history_sum_before" ] || fail "history.jsonl modified"
pass "history.jsonl untouched"

echo "ALL PASS"
