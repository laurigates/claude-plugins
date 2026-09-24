#!/usr/bin/env bash
# Offline test for ctx-probe.sh with a stub `claude` on PATH: the stub records
# its environment and cwd, emits a result event, and spawns no subagent. Checks
# that every arm still runs, the child env is an allowlist, and the child cwd
# is outside the repo.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
probe="$here/../scripts/ctx-probe.sh"
repo_root="$(git -C "$here" rev-parse --show-toplevel)"
tmp=$(mktemp -d) || { echo 'mktemp failed' >&2; exit 1; }
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then echo 'bad sandbox dir' >&2; exit 1; fi
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"
cat > "$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
n="$(find "$STUB_LOG_DIR" -name 'env-*' | wc -l)"
env > "$STUB_LOG_DIR/env-$n"
pwd > "$STUB_LOG_DIR/cwd-$n"
echo '{"type":"result","subtype":"success","total_cost_usd":0,"result":""}'
EOF
chmod +x "$tmp/bin/claude"
mkdir -p "$tmp/log"

# The probe passes only an allowlisted env to the child, so the log dir is
# baked into the stub rather than exported.
sed -i "2i STUB_LOG_DIR='$tmp/log'" "$tmp/bin/claude"

out="$(PATH="$tmp/bin:$PATH" ANTHROPIC_API_KEY=dummy CLAUDE_CODE_CHILD_SESSION=1 \
  CLAUDE_CODE_SUBAGENT_MODEL=leaked CLAUDECODE=1 \
  bash "$probe" --models "opus[1m]" --arms "on off" --files 2 --kb 1 \
    --run-id t --results-root "$tmp/results" 2>&1)" || { echo "FAIL probe exited non-zero"; printf '%s\n' "$out"; exit 1; }

# Both helpers are invoked indirectly through check().
# shellcheck disable=SC2317
not_grep() { ! grep -q "$@"; }
# shellcheck disable=SC2317
outside_repo() { case "$1" in "$repo_root"|"$repo_root"/*) return 1 ;; esac; }

fail=0
# check <description> <command...>: PASS when the command succeeds.
check() {
  local desc="$1"; shift
  if "$@"; then echo "PASS $desc"; else echo "FAIL $desc"; fail=1; fi
}

tsv="$tmp/results/t/summary.tsv"
rows="$(wc -l < "$tsv")"
error_rows="$(awk -F'\t' 'NR > 1 && $16 == "ERROR"' "$tsv" | wc -l)"
invocations="$(find "$tmp/log" -name 'env-*' | wc -l)"
check "summary.tsv has header + 2 rows" test "$rows" -eq 3
check "both arms report STATUS=ERROR (no subagent)" test "$error_rows" -eq 2
check "sentinels.txt copied into results" test -f "$tmp/results/t/sentinels.txt"
check "stub invoked once per arm" test "$invocations" -eq 2

for e in "$tmp"/log/env-*; do
  check "no CLAUDE_CODE_CHILD_SESSION" not_grep '^CLAUDE_CODE_CHILD_SESSION=' "$e"
  check "no CLAUDECODE" not_grep '^CLAUDECODE=' "$e"
  check "CLAUDE_CODE_SUBAGENT_MODEL=arm model" grep -qx 'CLAUDE_CODE_SUBAGENT_MODEL=opus\[1m\]' "$e"
  check "pct override set" grep -qx 'CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=10' "$e"
  check "auth passed through" grep -qx 'ANTHROPIC_API_KEY=dummy' "$e"
done
for c in "$tmp"/log/cwd-*; do
  check "child cwd outside repo" outside_repo "$(cat "$c")"
done
exit "$fail"
