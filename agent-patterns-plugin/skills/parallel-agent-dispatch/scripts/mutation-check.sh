#!/usr/bin/env bash
# Mutation probe: snapshot a file, apply a sed mutation, run a gate, and restore
# the file from the snapshot on every exit path. Reports whether the gate
# caught the mutation.
#
# Replaces the hand-written `cp <f> <snap>` + `sed -i ... <f>` + run + `cp <snap>
# <f>` sequence that verifier agents were told to run (verifier-shared-state.md).
# That sequence trips the `sed-inplace` block in bash-antipatterns.sh, and its
# restore step is the one an agent forgets after the gate errors out. This
# helper owns both. Restoring from a snapshot -- never `git checkout --` -- is
# what keeps an uncommitted fix intact (see references/verifier-shared-state.md).
#
# Usage: mutation-check.sh [-E] <path> <sed-expr> -- <gate command...>
#
#   -E          pass -E to sed (extended regex; supported by BSD and GNU sed)
#   <path>      existing regular file to mutate (restored afterwards)
#   <sed-expr>  sed script that must change the file, e.g. 's/>= 3/>= 4/'
#   <gate ...>  command that exits 0 when the suite is green
#
# Output (structured-script-output.md): on stdout, `SNAPSHOT=` first (so a
# SIGKILL'd run can be restored by hand), then `MUTANT=killed|survived`,
# `GATE_EXIT=`, `RESTORED=`, `STATUS=`, `ISSUE_COUNT=`. The gate's own output
# goes to stderr, so stdout stays a parseable block.
#
#   MUTANT=killed    gate failed on the mutant: the tests caught it  -> STATUS=OK
#   MUTANT=survived  gate passed on the mutant: the tests miss it    -> STATUS=WARN
#
# "killed" is only meaningful when the gate is green on the unmutated file: this
# helper does not run a baseline, so confirm that first (a gate that is already
# red reads as killed for every mutant). A gate that cannot start (exit 126 not
# executable, 127 not found) is an ERROR, never a kill.
#
# Exit codes: 0 = verdict reached (killed or survived), 1 = ERROR (no verdict:
# no-op mutation, sed failure, write failure, unrunnable gate, interrupted,
# restore failed), 2 = usage error.
#
# Portability: never uses `sed -i` (its flag differs between BSD and GNU sed).
# The mutant is written to a temp file and copied over the target with `cat >`,
# which keeps the target's inode, mode and symlink. A gate that reads stdin sees
# /dev/null. The gate runs in its own process group (job control), and an
# interrupt signals the whole group so a gate that spawns children (`just test`)
# leaves nothing running against the restored tree. SIGKILL cannot be trapped;
# the printed SNAPSHOT= path is the recovery copy in that case.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: mutation-check.sh [-E] <path> <sed-expr> -- <gate command...>
EOF
}

die_usage() {
  echo "mutation-check.sh: $1" >&2
  usage
  exit 2
}

sed_flags=()
if [ "${1:-}" = "-E" ]; then
  sed_flags=(-E)
  shift
fi
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

[ $# -ge 4 ] || die_usage "need <path> <sed-expr> -- <gate command...>"
target="$1"
expr="$2"
[ "$3" = "--" ] || die_usage "expected '--' between <sed-expr> and the gate command"
shift 3
[ -n "$expr" ] || die_usage "<sed-expr> is empty"

emit_error() {
  # $1 = REASON; the block is closed by the caller's exit.
  echo "STATUS=ERROR"
  echo "REASON=$1"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=${1%%:*} MSG=$1"
  echo "=== END MUTATION CHECK ==="
}

echo "=== MUTATION CHECK ==="
echo "TARGET=$target"

if [ ! -f "$target" ]; then
  echo "RESTORED=n/a"
  emit_error "missing_file: $target is not an existing regular file"
  exit 1
fi

# Refuse a gate that cannot start before touching the file. Checked up front as
# well as via the 126/127 exit below because bash 3.2 reports a failed exec in a
# background job as exit 1, which would otherwise read as a kill.
if ! command -v -- "$1" >/dev/null 2>&1; then
  echo "RESTORED=n/a"
  emit_error "gate_not_runnable: $1 is not an executable command or file; $target was not touched"
  exit 1
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/mutation-check.XXXXXX")"
snap="$work/snapshot"
mutant="$work/mutant"
armed=0
gate_pid=""

# Restore the target from the snapshot and verify it byte-for-byte. Idempotent:
# only acts while armed. On a failed restore the work dir (and snapshot) is kept.
restored="n/a"
restore() {
  [ "$armed" = 1 ] || return 0
  armed=0
  # Skip the copy when the target already matches (a failed write leaves it
  # untouched, and cp over a read-only file would fail for no reason).
  if { cmp -s "$snap" "$target" || cp -p "$snap" "$target"; } && cmp -s "$snap" "$target"; then
    restored=true
    rm -rf "$work"
  else
    restored=false
  fi
}

on_signal() {
  local name="$1" code="$2"
  if [ -n "$gate_pid" ]; then
    # Signal the gate's whole process group (job control gave it its own), so
    # grandchildren die with it; fall back to the gate pid alone.
    kill -TERM -- "-$gate_pid" 2>/dev/null || kill -TERM "$gate_pid" 2>/dev/null || true
    wait "$gate_pid" 2>/dev/null || true
  fi
  restore
  echo "RESTORED=$restored"
  emit_error "interrupted: received SIG$name; gate stopped, file restore attempted"
  exit "$code"
}

# EXIT covers every other path (including `set -e` aborts); the signal traps
# restore first and then exit, which re-enters the (now disarmed) EXIT trap.
trap restore EXIT
trap 'on_signal INT 130' INT
trap 'on_signal TERM 143' TERM
trap 'on_signal HUP 129' HUP

cp -p "$target" "$snap"
armed=1
echo "SNAPSHOT=$snap"

if ! sed ${sed_flags[@]+"${sed_flags[@]}"} -e "$expr" "$target" >"$mutant"; then
  restore
  echo "RESTORED=$restored"
  emit_error "sed_failed: sed rejected the expression: $expr"
  exit 1
fi

if cmp -s "$snap" "$mutant"; then
  restore
  echo "RESTORED=$restored"
  emit_error "no_op_mutation: the sed expression left $target unchanged"
  exit 1
fi

if ! cat "$mutant" >"$target"; then
  restore
  echo "RESTORED=$restored"
  emit_error "write_failed: could not write the mutant to $target"
  exit 1
fi

# Background + wait so a signal to this script is handled while the gate runs
# (bash defers traps until a foreground child exits). `set -m` puts the gate in
# its own process group; stdin is redirected because a job-control background
# job that reads the terminal would be stopped with SIGTTIN.
gate_rc=0
set -m
"$@" >&2 </dev/null &
gate_pid=$!
set +m
wait "$gate_pid" || gate_rc=$?
gate_pid=""

restore
echo "RESTORED=$restored"
echo "GATE_EXIT=$gate_rc"

if [ "$restored" != true ]; then
  echo "SNAPSHOT_KEPT=$snap"
  emit_error "restore_failed: could not restore $target; copy $snap over it"
  exit 1
fi

if [ "$gate_rc" -eq 126 ] || [ "$gate_rc" -eq 127 ]; then
  emit_error "gate_not_runnable: gate exited $gate_rc ($1 is not executable or not found); no verdict"
  exit 1
fi

if [ "$gate_rc" -ne 0 ]; then
  echo "MUTANT=killed"
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
else
  echo "MUTANT=survived"
  echo "STATUS=WARN"
  echo "REASON=mutant_survived: gate passed with $target mutated; the suite does not pin this behaviour"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=WARN TYPE=mutant_survived MSG=gate passed on the mutant"
fi
echo "=== END MUTATION CHECK ==="
