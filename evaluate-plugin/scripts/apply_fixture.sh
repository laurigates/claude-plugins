#!/usr/bin/env bash
# Apply (or tear down) an eval's optional `fixture` block in an isolated temp
# workdir, so a context-needing skill can honestly execute during evaluation.
#
# Without an honest execution context, context-needing skills fail on a weak
# model purely for lack of fixtures — a false negative that poisons the Slice-2
# executability gate. This script gives each such eval a real, throwaway workdir.
#
# The `fixture` block is additive and opt-in (see references/schemas.md). Evals
# without it run exactly as before; grade_deterministic.py is unaffected (it
# reads only `expectations`).
#
# Safety (the setup commands are arbitrary shell from evals.json): the workdir
# is always a fresh `mktemp -d` OUTSIDE the repo (honoring the worktree
# write-allowlist, .claude/rules/sandbox-guidance.md); teardown refuses any path
# not under the temp root. The blast radius is one disposable directory.
#
# Usage:
#   apply_fixture.sh --fixture '<json>'  [--repo-root <path>]   # apply
#   apply_fixture.sh --fixture '@file'   [--repo-root <path>]   # apply (from file)
#   apply_fixture.sh --teardown <workdir> [--fixture '<json>']  # teardown
#
# Apply output (KEY=value, see .claude/rules/structured-script-output.md):
#   === APPLY FIXTURE ===
#   FIXTURE_APPLIED=true|false
#   WORKDIR=<absolute temp path>        (only when FIXTURE_APPLIED=true)
#   DIR_COPIED=true|false
#   SETUP_COUNT=<int>
#   STATUS=OK|ERROR
#   === END APPLY FIXTURE ===

set -uo pipefail

mode="apply"
fixture_arg=""
repo_root="$(pwd)"
teardown_dir=""

while [ $# -gt 0 ]; do
  case "$1" in
    --fixture) fixture_arg="$2"; shift 2 ;;
    --repo-root) repo_root="$2"; shift 2 ;;
    --teardown) mode="teardown"; teardown_dir="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Resolve --fixture into JSON text. Empty / "null" / "{}" all mean "no fixture".
fixture_json="${fixture_arg}"
case "$fixture_arg" in
  @*) fixture_json="$(cat "${fixture_arg#@}" 2>/dev/null)" ;;
esac
[ -z "$fixture_json" ] && fixture_json="null"

# Temp root: honor $TMPDIR but never the repo. mktemp -d lands here.
# Normalize the trailing slash ($TMPDIR is slash-terminated on macOS) so the
# teardown prefix guard matches the WORKDIR mktemp produced.
tmp_root="${TMPDIR:-/tmp}"
tmp_root="${tmp_root%/}"

# ---------------------------------------------------------------------------
# Teardown mode
# ---------------------------------------------------------------------------
if [ "$mode" = "teardown" ]; then
  echo "=== TEARDOWN FIXTURE ==="
  if [ -z "$teardown_dir" ]; then
    echo "STATUS=ERROR"
    echo "ERROR=--teardown requires a workdir path"
    echo "=== END TEARDOWN FIXTURE ==="
    exit 1
  fi
  # Refuse to remove anything outside the temp root — the setup commands are
  # untrusted, so this guard is the backstop against a poisoned WORKDIR value.
  abs_teardown="$teardown_dir"
  case "$abs_teardown" in
    "$tmp_root"/*) : ;;
    /tmp/*|/var/folders/*) : ;;  # macOS mktemp lives under /var/folders
    *)
      echo "STATUS=ERROR"
      echo "ERROR=refusing to tear down a path outside the temp root: ${teardown_dir}"
      echo "=== END TEARDOWN FIXTURE ==="
      exit 1
      ;;
  esac
  # Run optional teardown commands first, then discard the dir.
  if [ -d "$abs_teardown" ]; then
    while IFS= read -r cmd; do
      [ -z "$cmd" ] && continue
      ( cd "$abs_teardown" && bash -c "$cmd" ) >/dev/null 2>&1
    done < <(printf '%s' "$fixture_json" | jq -r '.teardown[]?' 2>/dev/null)
    rm -rf "$abs_teardown"
  fi
  echo "TEARDOWN_DONE=true"
  echo "STATUS=OK"
  echo "=== END TEARDOWN FIXTURE ==="
  exit 0
fi

# ---------------------------------------------------------------------------
# Apply mode
# ---------------------------------------------------------------------------
echo "=== APPLY FIXTURE ==="

has_dir="$(printf '%s' "$fixture_json" | jq -r '(.dir // "") | tostring' 2>/dev/null)"
setup_count="$(printf '%s' "$fixture_json" | jq -r '(.setup // []) | length' 2>/dev/null)"
[ -z "$setup_count" ] && setup_count=0

# No-op when the eval carries no fixture (back-compat): the eval runs in the
# repo exactly as today.
if [ "$fixture_json" = "null" ] || { [ -z "$has_dir" ] && [ "$setup_count" = "0" ]; }; then
  echo "FIXTURE_APPLIED=false"
  echo "DIR_COPIED=false"
  echo "SETUP_COUNT=0"
  echo "STATUS=OK"
  echo "=== END APPLY FIXTURE ==="
  exit 0
fi

workdir="$(mktemp -d "${tmp_root%/}/eval-fixture.XXXXXX")"
if [ -z "$workdir" ] || [ ! -d "$workdir" ]; then
  echo "FIXTURE_APPLIED=false"
  echo "STATUS=ERROR"
  echo "ERROR=mktemp -d failed"
  echo "=== END APPLY FIXTURE ==="
  exit 1
fi

dir_copied=false
if [ -n "$has_dir" ]; then
  src="${repo_root%/}/${has_dir}"
  if [ ! -d "$src" ]; then
    rm -rf "$workdir"
    echo "FIXTURE_APPLIED=false"
    echo "STATUS=ERROR"
    echo "ERROR=fixture.dir not found: ${src}"
    echo "=== END APPLY FIXTURE ==="
    exit 1
  fi
  # Copy template contents (including dotfiles) into the workdir.
  cp -R "$src"/. "$workdir"/ 2>/dev/null
  dir_copied=true
fi

# Run setup commands sequentially in the workdir. Fail loudly on first error.
setup_failed=false
while IFS= read -r cmd; do
  [ -z "$cmd" ] && continue
  if ! ( cd "$workdir" && bash -c "$cmd" ) >/dev/null 2>&1; then
    setup_failed=true
    failed_cmd="$cmd"
    break
  fi
done < <(printf '%s' "$fixture_json" | jq -r '.setup[]?' 2>/dev/null)

if [ "$setup_failed" = true ]; then
  rm -rf "$workdir"
  echo "FIXTURE_APPLIED=false"
  echo "DIR_COPIED=${dir_copied}"
  echo "SETUP_COUNT=${setup_count}"
  echo "STATUS=ERROR"
  echo "ERROR=setup command failed: ${failed_cmd}"
  echo "=== END APPLY FIXTURE ==="
  exit 1
fi

echo "FIXTURE_APPLIED=true"
echo "WORKDIR=${workdir}"
echo "DIR_COPIED=${dir_copied}"
echo "SETUP_COUNT=${setup_count}"
echo "STATUS=OK"
echo "=== END APPLY FIXTURE ==="
