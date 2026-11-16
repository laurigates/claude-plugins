#!/usr/bin/env bash
# run-test-cycle.sh — deterministic per-cycle driver for /project:test-loop.
#
# THE PROBLEM (issue #1920)
# The test-fix-refactor loop used to be pure prose the model re-derived on every
# invocation: detect the test command, run it, count cycles, decide whether the
# suite is green, whether it's stuck, whether the --max-cycles ceiling is hit.
# That is exactly the mechanical, repeatable, verifiable work that belongs in a
# deterministic substrate, not the agent's reasoning loop
# (.claude/rules/offload-to-deterministic-substrate.md).
#
# WHAT THIS DRIVES (and what it deliberately does NOT)
# The model still does the one genuinely model-shaped step — reading the failure
# and making the minimal fix — between invocations. This script does everything
# mechanical AROUND that:
#   - detect the test command (or take --test-cmd)
#   - run the suite once, bound the captured output (last N lines)
#   - read + increment a persistent cycle counter (survives across invocations)
#   - hash the failing-suite signature to detect no-progress (same failure 3x)
#   - enforce the --max-cycles ceiling
#   - emit a single VERDICT the model branches on
#
# This is the mechanical, INDEPENDENT stop condition loop-integrity.md Pillar 1
# asks for: the suite's own exit code — not the worker's opinion — decides
# "done". STUCK and CAP_REACHED are the runaway ceiling.
#
# VERDICT (the line the model reads):
#   GREEN        test command exited 0 — suite passes, stop and (optionally) refactor
#   CONTINUE     suite failing, progress still possible — model fixes, re-invokes
#   STUCK        same failing signature 3 cycles running — no progress, stop
#   CAP_REACHED  cycle count reached --max-cycles — stop
#   SETUP_ERROR  no test command could be detected / it could not run
#
# OUTPUT: structured KEY=VALUE per .claude/rules/structured-script-output.md,
# plus a bounded === TEST OUTPUT === tail so the model can read the failure.
#
# Usage:
#   run-test-cycle.sh [--pattern <p>] [--max-cycles <N>] [--test-cmd <cmd>]
#                     [--state-file <path>] [--project-dir <dir>] [--reset]
#
# Exit code parallels STATUS: 0 for OK/WARN (GREEN/CONTINUE/STUCK/CAP_REACHED),
# 1 for ERROR (SETUP_ERROR) — see structured-script-output.md.

set -uo pipefail

pattern=""
max_cycles=10
test_cmd_override=""
state_file=""
project_dir="."
reset=0
tail_lines=100
stuck_threshold=3

while [ $# -gt 0 ]; do
  case "$1" in
    --pattern) pattern="${2:-}"; shift 2 ;;
    --max-cycles) max_cycles="${2:-}"; shift 2 ;;
    --test-cmd) test_cmd_override="${2:-}"; shift 2 ;;
    --state-file) state_file="${2:-}"; shift 2 ;;
    --project-dir) project_dir="${2:-}"; shift 2 ;;
    --tail-lines) tail_lines="${2:-}"; shift 2 ;;
    --stuck-threshold) stuck_threshold="${2:-}"; shift 2 ;;
    --reset) reset=1; shift ;;
    *) shift ;;
  esac
done

# --max-cycles must be a positive integer; fall back to the default otherwise.
case "$max_cycles" in
  ''|*[!0-9]*) max_cycles=10 ;;
esac
[ "$max_cycles" -lt 1 ] && max_cycles=1

emit_setup_error() {
  local msg="$1"
  echo "=== TEST CYCLE ==="
  echo "VERDICT=SETUP_ERROR"
  echo "TEST_COMMAND="
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=test_setup MSG=$msg"
  echo "=== END TEST CYCLE ==="
  exit 1
}

# --- Resolve state file (persists the cycle counter + failure history) --------
# Default lives under the git dir (never committed, gitignored) so repeated runs
# accumulate state without polluting the working tree; falls back to cwd.
if [ -z "$state_file" ]; then
  git_dir="$(git -C "$project_dir" rev-parse --git-dir 2>/dev/null)"
  if [ -n "$git_dir" ]; then
    case "$git_dir" in
      /*) state_file="$git_dir/project-test-loop-state" ;;
      *) state_file="$project_dir/$git_dir/project-test-loop-state" ;;
    esac
  else
    state_file="$project_dir/.project-test-loop-state"
  fi
fi

if [ "$reset" -eq 1 ]; then
  rm -f "$state_file"
fi

# State file schema (deterministic, grep-parseable):
#   CYCLE=<int>
#   SIG=<hash>        (repeated, most-recent-last — the failure-signature history)
prev_cycle=0
if [ -f "$state_file" ]; then
  prev_cycle="$(grep -E '^CYCLE=' "$state_file" 2>/dev/null | tail -n1 | cut -d= -f2)"
  case "$prev_cycle" in ''|*[!0-9]*) prev_cycle=0 ;; esac
fi

# --- Detect the test command --------------------------------------------------
# A detected runner is held as an argument array (test_argv), never as a string
# a shell re-parses, and --pattern is appended to it as exactly one argument.
# The pattern used to be concatenated into a string and eval'd, so `;`, `$(…)`
# or a backtick in a test name ran as a command (issue #3676).
test_argv=()
detect_test_command() {
  local dir="$1"
  if [ -f "$dir/package.json" ] && grep -qE '"test"[[:space:]]*:' "$dir/package.json"; then
    test_argv=(npm test); return 0
  fi
  if [ -f "$dir/pyproject.toml" ] || [ -f "$dir/pytest.ini" ] || [ -f "$dir/setup.cfg" ] || [ -f "$dir/tox.ini" ]; then
    test_argv=(pytest); return 0
  fi
  if [ -f "$dir/Cargo.toml" ]; then
    test_argv=(cargo test); return 0
  fi
  if [ -f "$dir/go.mod" ]; then
    test_argv=(go test ./...); return 0
  fi
  if [ -f "$dir/Makefile" ] && grep -qE '^test:' "$dir/Makefile"; then
    test_argv=(make test); return 0
  fi
  return 1
}

pattern_args=()
[ -n "$pattern" ] && pattern_args=("$pattern")

if [ -n "$test_cmd_override" ]; then
  # --test-cmd is an arbitrary command by design, so it runs through `bash -c`.
  # With a pattern, "$@" carries the pattern in as one positional argument; the
  # pattern text itself is never parsed by a shell.
  if [ -n "$pattern" ]; then
    run_argv=(bash -c "$test_cmd_override \"\$@\"" run-test-cycle "${pattern_args[@]}")
  else
    run_argv=(bash -c "$test_cmd_override")
  fi
  cmd_display="$test_cmd_override"
else
  detect_test_command "$project_dir" \
    || emit_setup_error "no test command detected (checked package.json, pytest/pyproject, Cargo.toml, go.mod, Makefile) — pass --test-cmd or configure it in CLAUDE.md"
  run_argv=("${test_argv[@]}" "${pattern_args[@]}")
  cmd_display="${test_argv[*]}"
fi
# Report the pattern shell-quoted so the printed command is unambiguous.
[ -n "$pattern" ] && cmd_display="$cmd_display $(printf '%q' "$pattern")"

# --- Run the suite ------------------------------------------------------------
output_log="$(mktemp)"
trap 'rm -f "$output_log"' EXIT

( cd "$project_dir" && "${run_argv[@]}" ) >"$output_log" 2>&1
test_exit=$?

# --- Compute a stable failure signature ---------------------------------------
# Normalize volatile parts (durations, timestamps, memory addresses, tmp paths)
# so an identical failure across cycles hashes identically — that is what lets us
# detect "no progress". Bounded to the last $tail_lines to keep the hash cheap.
hash_cmd=""
if command -v sha256sum >/dev/null 2>&1; then
  hash_cmd="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
  hash_cmd="shasum -a 256"
fi

signature=""
if [ -n "$hash_cmd" ]; then
  signature="$(
    tail -n "$tail_lines" "$output_log" \
      | sed -E \
          -e 's/[0-9]+\.[0-9]+ ?(s|ms|seconds|secs)//g' \
          -e 's/in [0-9]+\.[0-9]+s//g' \
          -e 's/0x[0-9a-fA-F]+//g' \
          -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9:]+//g' \
          -e 's#/tmp/[^ ]+##g' \
      | $hash_cmd | cut -d' ' -f1
  )"
fi

# --- Decide the verdict -------------------------------------------------------
this_cycle=$((prev_cycle + 1))

status="WARN"
issue_count=0

if [ "$test_exit" -eq 0 ]; then
  verdict="GREEN"
  status="OK"
  # Reset the state on green — the loop is complete.
  rm -f "$state_file"
else
  # Persist the incremented cycle + signature history (most recent last).
  prior_sigs=""
  if [ -f "$state_file" ]; then
    prior_sigs="$(grep -E '^SIG=' "$state_file" 2>/dev/null || true)"
  fi
  {
    echo "CYCLE=$this_cycle"
    [ -n "$prior_sigs" ] && printf '%s\n' "$prior_sigs"
    [ -n "$signature" ] && echo "SIG=$signature"
  } >"$state_file"

  # Count trailing identical signatures (no-progress detection).
  repeat_run=0
  if [ -n "$signature" ]; then
    while IFS= read -r s; do
      if [ "$s" = "SIG=$signature" ]; then
        repeat_run=$((repeat_run + 1))
      else
        repeat_run=0
      fi
    done < <(grep -E '^SIG=' "$state_file" 2>/dev/null)
  fi

  if [ -n "$signature" ] && [ "$repeat_run" -ge "$stuck_threshold" ]; then
    verdict="STUCK"
    issue_count=1
  elif [ "$this_cycle" -ge "$max_cycles" ]; then
    verdict="CAP_REACHED"
    issue_count=1
  else
    verdict="CONTINUE"
  fi
fi

# --- Emit structured result ---------------------------------------------------
echo "=== TEST CYCLE ==="
echo "VERDICT=$verdict"
echo "TEST_COMMAND=$cmd_display"
echo "TEST_EXIT=$test_exit"
echo "CYCLE=$this_cycle"
echo "MAX_CYCLES=$max_cycles"
echo "STUCK_THRESHOLD=$stuck_threshold"
[ -n "$signature" ] && echo "FAILURE_SIGNATURE=$signature"
echo "STATUS=$status"
echo "ISSUE_COUNT=$issue_count"
echo "=== END TEST CYCLE ==="

# Bounded transcript so the model can read the failure without re-running.
echo "=== TEST OUTPUT (last $tail_lines lines) ==="
tail -n "$tail_lines" "$output_log"
echo "=== END TEST OUTPUT ==="

# Exit 0 for every non-setup verdict (OK/WARN) so callers batching this stay safe.
exit 0
